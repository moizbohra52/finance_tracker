// Runs in Node (node --test supabase/functions/send-push/handler.test.ts) and
// Deno (deno test): only node:test, node:assert and Web APIs are used.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { handle, parseInput, signJwt } from './handler.ts';

const USER = '11111111-2222-4333-8444-555555555555';
const REF = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
const KEY = 'service-role-key';

const keys = await crypto.subtle.generateKey(
  {
    name: 'RSASSA-PKCS1-v1_5',
    modulusLength: 2048,
    publicExponent: new Uint8Array([1, 0, 1]),
    hash: 'SHA-256',
  },
  true,
  ['sign', 'verify'],
);
const pkcs8 = new Uint8Array(
  await crypto.subtle.exportKey('pkcs8', keys.privateKey),
);
const pem = `-----BEGIN PRIVATE KEY-----\n${
  btoa(String.fromCharCode(...pkcs8)).replace(/(.{64})/g, '$1\n')
}\n-----END PRIVATE KEY-----\n`;

const fromBase64Url = (s: string) =>
  Uint8Array.from(
    atob(s.replace(/-/g, '+').replace(/_/g, '/')),
    (c) => c.charCodeAt(0),
  );

function env(email: string) {
  return {
    SUPABASE_URL: 'https://db.example',
    SUPABASE_SERVICE_ROLE_KEY: KEY,
    FCM_SERVICE_ACCOUNT: JSON.stringify({
      project_id: 'demo',
      client_email: email,
      private_key: pem,
    }),
  };
}

type Call = { url: string; init?: RequestInit };

/** A fake fetch: device_tokens read/update, Google token endpoint and FCM. */
function fakeFetch(
  devices: { id: string; token: string }[],
  fcm: (token: string) => Response,
) {
  const calls: Call[] = [];
  const fn = (async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    calls.push({ url, init });
    if (url.startsWith('https://db.example/rest/v1/device_tokens')) {
      return init?.method === 'PATCH'
        ? new Response(null, { status: 204 })
        : Response.json(devices);
    }
    if (url === 'https://oauth2.googleapis.com/token') {
      return Response.json({ access_token: 'google-token', expires_in: 3600 });
    }
    const body = JSON.parse(String(init?.body));
    return fcm(body.message.token);
  }) as typeof fetch;
  return { fn, calls };
}

const request = (body: unknown, auth = `Bearer ${KEY}`) =>
  new Request('https://fn.example/send-push', {
    method: 'POST',
    headers: { Authorization: auth, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });

const valid = {
  user_id: USER,
  type: 'reminder',
  reference_id: REF,
  title: 'Collect payment',
  body: 'Money to collect',
};

test('only the service role key may call it', async () => {
  const { fn, calls } = fakeFetch([], () => Response.json({}));
  assert.equal((await handle(request(valid, 'Bearer anon'), env('a@x'), fn)).status, 401);
  assert.equal((await handle(request(valid, ''), env('a@x'), fn)).status, 401);
  assert.equal(
    (await handle(new Request('https://fn.example', { method: 'GET' }), env('a@x'), fn))
      .status,
    405,
  );
  assert.equal(calls.length, 0);
});

test('input is validated', () => {
  assert.equal(typeof parseInput({ ...valid, user_id: 'x' }), 'string');
  assert.equal(typeof parseInput({ ...valid, type: 'Bad Type' }), 'string');
  assert.equal(typeof parseInput({ ...valid, reference_id: 'x' }), 'string');
  assert.equal(typeof parseInput({ ...valid, title: ' ' }), 'string');
  assert.equal(typeof parseInput({ ...valid, title: 'x'.repeat(101) }), 'string');
  assert.equal(typeof parseInput([]), 'string');
  assert.deepEqual(
    parseInput({ user_id: USER.toUpperCase(), type: 'khata', title: ' Hi ' }),
    { user_id: USER, type: 'khata', reference_id: null, title: 'Hi', body: null },
  );
});

test('sends to every active device and deactivates gone tokens', async () => {
  const { fn, calls } = fakeFetch(
    [
      { id: 'd1', token: 'tok-live' },
      { id: 'd2', token: 'tok-gone' },
    ],
    (token) =>
      token === 'tok-live' ? Response.json({ name: 'm/1' }) : Response.json(
        {
          error: {
            status: 'NOT_FOUND',
            details: [{
              '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError',
              errorCode: 'UNREGISTERED',
            }],
          },
        },
        { status: 404 },
      ),
  );

  const res = await handle(request(valid), env('send@x'), fn);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { sent: 1, failed: 0, deactivated: 1 });

  const read = calls[0];
  assert.match(read.url, new RegExp(`active=is.true&user_id=eq.${USER}$`));
  assert.equal((read.init?.headers as Record<string, string>).apikey, KEY);

  // The Google assertion is a JWT signed with the service account key.
  const tokenCall = calls.find((c) => c.url.includes('oauth2'))!;
  const assertion = new URLSearchParams(String(tokenCall.init?.body)).get('assertion')!;
  const [h, p, s] = assertion.split('.');
  assert.ok(
    await crypto.subtle.verify(
      'RSASSA-PKCS1-v1_5',
      keys.publicKey,
      fromBase64Url(s),
      new TextEncoder().encode(`${h}.${p}`),
    ),
  );
  const claims = JSON.parse(new TextDecoder().decode(fromBase64Url(p)));
  assert.equal(claims.iss, 'send@x');
  assert.equal(claims.scope, 'https://www.googleapis.com/auth/firebase.messaging');

  const send = calls.find((c) => c.url.includes('fcm.googleapis.com'))!;
  assert.equal(send.url, 'https://fcm.googleapis.com/v1/projects/demo/messages:send');
  assert.equal(
    (send.init?.headers as Record<string, string>).Authorization,
    'Bearer google-token',
  );
  const message = JSON.parse(String(send.init?.body)).message;
  assert.deepEqual(message.data, { type: 'reminder', user_id: USER, reference_id: REF });
  assert.deepEqual(message.notification, { title: 'Collect payment', body: 'Money to collect' });
  assert.equal(message.android.notification.channel_id, 'alerts_sv');

  const patch = calls.find((c) => c.init?.method === 'PATCH')!;
  assert.equal(patch.url, 'https://db.example/rest/v1/device_tokens?id=in.(d2)');
  assert.deepEqual(JSON.parse(String(patch.init?.body)), { active: false });
});

test('a user without devices gets nothing sent', async () => {
  const { fn, calls } = fakeFetch([], () => Response.json({}));
  const res = await handle(request(valid), env('none@x'), fn);
  assert.deepEqual(await res.json(), { sent: 0, failed: 0, deactivated: 0 });
  assert.equal(calls.length, 1);
});

test('a temporary FCM failure answers 502 and keeps the token', async () => {
  const { fn, calls } = fakeFetch(
    [{ id: 'd1', token: 'tok' }],
    () => Response.json({ error: { status: 'UNAVAILABLE' } }, { status: 503 }),
  );
  const res = await handle(request(valid), env('busy@x'), fn);
  assert.equal(res.status, 502);
  assert.deepEqual(await res.json(), { sent: 0, failed: 1, deactivated: 0 });
  assert.equal(calls.filter((c) => c.init?.method === 'PATCH').length, 0);
});

test('signJwt output verifies with the public key', async () => {
  const jwt = await signJwt({ a: 1 }, pem);
  const [h, p, s] = jwt.split('.');
  assert.deepEqual(JSON.parse(new TextDecoder().decode(fromBase64Url(h))), {
    alg: 'RS256',
    typ: 'JWT',
  });
  assert.ok(
    await crypto.subtle.verify(
      'RSASSA-PKCS1-v1_5',
      keys.publicKey,
      fromBase64Url(s),
      new TextEncoder().encode(`${h}.${p}`),
    ),
  );
});
