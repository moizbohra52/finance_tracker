// Server-side push sender (docs/08_NOTIFICATION_SYSTEM.md, "Push sender").
// Sends one notification to every active device of one user through the FCM
// HTTP v1 API and deactivates tokens FCM reports as gone. Only Web APIs are
// used (fetch, WebCrypto), so this file runs in Deno and in Node's test runner.

export type Env = {
  SUPABASE_URL?: string;
  SUPABASE_SERVICE_ROLE_KEY?: string;
  /** The Firebase service account key file, as JSON text. */
  FCM_SERVICE_ACCOUNT?: string;
};

export type PushInput = {
  user_id: string;
  type: string;
  reference_id: string | null;
  title: string;
  body: string | null;
};

type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
  token_uri?: string;
};

type Fetch = typeof fetch;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// Same shape as the app's types (reminder, budget_alert, ...); an unknown one
// opens the notification center (NotificationTarget.resolve).
const TYPE = /^[a-z_]{1,40}$/;
export const TITLE_MAX = 100;
export const BODY_MAX = 500;
// The channel the app creates for pushes (LocalNotificationService).
const ANDROID_CHANNEL = 'alerts_sv';
const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
// FCM error codes after which a token never works again.
const DEAD_TOKEN = new Set(['UNREGISTERED', 'SENDER_ID_MISMATCH']);

/** The request body as a [PushInput], or the reason it is not one. */
export function parseInput(raw: unknown): PushInput | string {
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
    return 'Body must be a JSON object';
  }
  const r = raw as Record<string, unknown>;
  const { user_id, type, title } = r;
  const reference_id = r.reference_id ?? null;
  const body = r.body ?? null;
  if (typeof user_id !== 'string' || !UUID.test(user_id)) {
    return 'user_id must be a uuid';
  }
  if (typeof type !== 'string' || !TYPE.test(type)) {
    return 'type must be 1-40 lowercase letters or underscores';
  }
  if (
    reference_id !== null &&
    (typeof reference_id !== 'string' || !UUID.test(reference_id))
  ) {
    return 'reference_id must be a uuid or null';
  }
  if (
    typeof title !== 'string' ||
    title.trim() === '' ||
    title.length > TITLE_MAX
  ) {
    return `title must be 1-${TITLE_MAX} characters`;
  }
  if (body !== null && (typeof body !== 'string' || body.length > BODY_MAX)) {
    return `body must be at most ${BODY_MAX} characters`;
  }
  return {
    user_id: user_id.toLowerCase(),
    type,
    reference_id: typeof reference_id === 'string'
      ? reference_id.toLowerCase()
      : null,
    title: title.trim(),
    body: typeof body === 'string' && body.trim() !== '' ? body.trim() : null,
  };
}

/** The FCM v1 request for one device. `data` is what the app routes by. */
export function fcmMessage(token: string, input: PushInput) {
  const data: Record<string, string> = {
    type: input.type,
    user_id: input.user_id,
  };
  if (input.reference_id) data.reference_id = input.reference_id;
  return {
    message: {
      token,
      notification: input.body
        ? { title: input.title, body: input.body }
        : { title: input.title },
      data,
      android: { priority: 'high', notification: { channel_id: ANDROID_CHANNEL } },
      apns: { payload: { aps: { sound: 'default' } } },
    },
  };
}

/** The FCM error code of a failed send, if it has one. */
export function fcmErrorCode(error: unknown): string | null {
  const details = (error as { error?: { details?: unknown } } | null)?.error
    ?.details;
  if (!Array.isArray(details)) return null;
  for (const d of details) {
    const code = (d as { errorCode?: unknown } | null)?.errorCode;
    if (typeof code === 'string') return code;
  }
  return null;
}

function base64Url(bytes: Uint8Array): string {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/** An RS256 JWT of [claims], signed with a PKCS#8 PEM private key. */
export async function signJwt(
  claims: Record<string, unknown>,
  privateKeyPem: string,
): Promise<string> {
  const der = Uint8Array.from(
    atob(privateKeyPem.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '')),
    (c) => c.charCodeAt(0),
  );
  const key = await crypto.subtle.importKey(
    'pkcs8',
    der,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const text = new TextEncoder();
  const unsigned = `${base64Url(text.encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' })))}.${
    base64Url(text.encode(JSON.stringify(claims)))
  }`;
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    text.encode(unsigned),
  );
  return `${unsigned}.${base64Url(new Uint8Array(signature))}`;
}

// Google access tokens last an hour; a warm function instance reuses one.
let cachedToken: { email: string; token: string; expiresAt: number } | null =
  null;

async function accessToken(
  account: ServiceAccount,
  fetchFn: Fetch,
): Promise<string> {
  const now = Date.now();
  if (
    cachedToken &&
    cachedToken.email === account.client_email &&
    cachedToken.expiresAt - 60_000 > now
  ) {
    return cachedToken.token;
  }
  const tokenUri = account.token_uri ?? 'https://oauth2.googleapis.com/token';
  const iat = Math.floor(now / 1000);
  const assertion = await signJwt(
    { iss: account.client_email, scope: SCOPE, aud: tokenUri, iat, exp: iat + 3600 },
    account.private_key,
  );
  const res = await fetchFn(tokenUri, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!res.ok) throw new Error(`token endpoint answered ${res.status}`);
  const json = (await res.json()) as {
    access_token: string;
    expires_in: number;
  };
  cachedToken = {
    email: account.client_email,
    token: json.access_token,
    expiresAt: now + json.expires_in * 1000,
  };
  return json.access_token;
}

/** Compares secrets without leaking where they differ through timing. */
async function sameSecret(a: string, b: string): Promise<boolean> {
  const text = new TextEncoder();
  const [x, y] = await Promise.all(
    [a, b].map((s) => crypto.subtle.digest('SHA-256', text.encode(s))),
  );
  const u = new Uint8Array(x);
  const v = new Uint8Array(y);
  let diff = 0;
  for (let i = 0; i < u.length; i++) diff |= u[i] ^ v[i];
  return diff === 0;
}

function parseAccount(raw: string): ServiceAccount | null {
  try {
    const a = JSON.parse(raw) as Partial<ServiceAccount>;
    return typeof a.project_id === 'string' &&
        typeof a.client_email === 'string' &&
        typeof a.private_key === 'string'
      ? (a as ServiceAccount)
      : null;
  } catch {
    return null;
  }
}

const reply = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });

/**
 * POST `{user_id, type, reference_id?, title, body?}` with
 * `Authorization: Bearer <service role key>`. Answers
 * `{sent, failed, deactivated}`: 200, or 502 when nothing could be sent and a
 * retry may help. Tokens and texts are never logged.
 */
export async function handle(
  req: Request,
  env: Env,
  fetchFn: Fetch = fetch,
): Promise<Response> {
  if (req.method !== 'POST') return reply(405, { error: 'Use POST' });
  const { SUPABASE_URL: url, SUPABASE_SERVICE_ROLE_KEY: key } = env;
  const account = env.FCM_SERVICE_ACCOUNT
    ? parseAccount(env.FCM_SERVICE_ACCOUNT)
    : null;
  if (!url || !key || !account) {
    return reply(500, { error: 'Push sender is not configured' });
  }
  // Server-only: any signed-in user could otherwise push to anyone.
  if (!(await sameSecret(req.headers.get('Authorization') ?? '', `Bearer ${key}`))) {
    return reply(401, { error: 'Unauthorized' });
  }

  let raw: unknown;
  try {
    raw = await req.json();
  } catch {
    return reply(400, { error: 'Body must be JSON' });
  }
  const input = parseInput(raw);
  if (typeof input === 'string') return reply(400, { error: input });

  const tokensUrl = `${url}/rest/v1/device_tokens`;
  const db = { apikey: key, Authorization: `Bearer ${key}` };
  const read = await fetchFn(
    `${tokensUrl}?select=id,token&active=is.true&user_id=eq.${input.user_id}`,
    { headers: db },
  );
  if (!read.ok) {
    console.error(`send-push: reading device_tokens failed (${read.status})`);
    return reply(502, { error: 'Could not read device tokens' });
  }
  const devices = (await read.json()) as { id: string; token: string }[];
  if (devices.length === 0) return reply(200, { sent: 0, failed: 0, deactivated: 0 });

  let bearer: string;
  try {
    bearer = await accessToken(account, fetchFn);
  } catch (error) {
    console.error(`send-push: no FCM access token (${(error as Error).message})`);
    return reply(502, { error: 'Could not get an FCM access token' });
  }

  const endpoint =
    `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`;
  const outcomes = await Promise.all(
    devices.map(async (device): Promise<'sent' | 'failed' | 'dead'> => {
      try {
        const res = await fetchFn(endpoint, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${bearer}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(fcmMessage(device.token, input)),
        });
        if (res.ok) return 'sent';
        if (res.status === 401) cachedToken = null;
        const code = fcmErrorCode(await res.json().catch(() => null));
        if (code !== null && DEAD_TOKEN.has(code)) return 'dead';
        console.error(`send-push: FCM answered ${res.status} ${code ?? ''}`);
        return 'failed';
      } catch (error) {
        console.error(`send-push: FCM request failed (${(error as Error).name})`);
        return 'failed';
      }
    }),
  );

  const dead = devices.filter((_, i) => outcomes[i] === 'dead').map((d) => d.id);
  if (dead.length > 0) {
    const update = await fetchFn(`${tokensUrl}?id=in.(${dead.join(',')})`, {
      method: 'PATCH',
      headers: { ...db, 'Content-Type': 'application/json', Prefer: 'return=minimal' },
      body: JSON.stringify({ active: false }),
    });
    if (!update.ok) {
      console.error(`send-push: deactivating tokens failed (${update.status})`);
    }
  }

  const sent = outcomes.filter((o) => o === 'sent').length;
  const failed = outcomes.filter((o) => o === 'failed').length;
  return reply(sent === 0 && failed > 0 ? 502 : 200, {
    sent,
    failed,
    deactivated: dead.length,
  });
}
