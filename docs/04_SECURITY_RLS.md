# Security and RLS

## Authentication
Use Supabase Auth.

## RLS
Every user-owned table must have:
- SELECT policy: auth.uid() = user_id
- INSERT policy: auth.uid() = user_id
- UPDATE policy: auth.uid() = user_id
- DELETE policy: auth.uid() = user_id

For profiles:
- id = auth.uid()

For system categories:
- allow read where is_system = true
- user-created categories require user_id = auth.uid()

### As implemented (Phase 01)
- All policies are `to authenticated` and use `(select auth.uid())`.
- `anon` has no grants on any app table: signed-out requests fail with
  permission denied before RLS is evaluated.
- profiles and user_settings: SELECT and UPDATE only. Rows are created by the
  signup trigger and removed by the `auth.users` cascade, so clients get no
  INSERT/DELETE grant.
- categories: INSERT/UPDATE also require `not is_system`, so no user can create
  or edit a category that is visible to everyone.
- transactions, budgets, recurring_transactions: INSERT/UPDATE also require
  `private.can_use_category(category_id)` (system or own category).
- References to accounts/contacts are composite foreign keys on
  `(user_id, id)`; pointing at another user's row fails with a foreign key
  violation.
- Phase 09: `device_tokens` has the four owner-only policies and no `anon`
  grant. `reminders.transaction_id` is a composite foreign key on
  `(user_id, transaction_id)`, so a reminder cannot point at another user's
  transaction (this needed a `(user_id, id)` unique key on `transactions`).
- Verified by `supabase/checks/cross_user_isolation.sql` (Phases 01-08; the
  Phase 09 additions are not covered by it yet).

## Ownership
Never trust user_id supplied by the Flutter client. Where possible derive ownership from auth.uid() in database policies/functions.

## Financial isolation
A user must never be able to:
- read another user's transactions
- modify another user's account
- access another user's contacts
- access another user's reports through direct table queries

## Secrets
- The Supabase publishable key (or legacy anon key) may be included in the client.
- Supabase service-role key must never be included in Flutter.
- Never commit .env files containing secrets.
- Do not log access/refresh tokens.

## Account deletion
Implement a secure server-side deletion strategy. Deleting auth.users and cascading user data must be deliberate and tested.

Phase 01: every user-owned table cascades from `auth.users`, and the isolation
check verifies that deleting a user removes all of their rows and nothing else.

Phase 02: `public.delete_my_account()` (security definer, authenticated only)
deletes the caller's auth user. It refuses unless the JWT `amr` claim shows a
password sign-in within the last 5 minutes, so a stolen session or refresh
token cannot delete an account. The app asks for the password, re-signs in,
then calls it.

## Attachments
Storage buckets must also use policies based on user ownership/path.

## Security acceptance
Test both authenticated and unauthenticated access, and attempt cross-user reads/writes before release.

### Avatars bucket (Phase 10)
- Bucket `avatars`: **private**, 2 MiB per file, `image/jpeg`, `image/png`,
  `image/webp` only. The bucket enforces these limits as well as the app.
- Objects are named `<user id>/<file>`. Four policies on `storage.objects`
  (select, insert, update, delete), all `to authenticated`, all requiring
  `bucket_id = 'avatars'` and `(storage.foldername(name))[1] = auth.uid()`.
- The app never shows a public URL. It creates a signed link valid for one
  hour, and a link that expires shows the fallback picture.
- Deleting the account removes the photo after the password is confirmed and
  before the account is deleted. Storage objects are not removed by the
  database cascade, so this step is what removes them. If it fails (for example
  offline), the file remains and is not shown to anyone; it is a known gap.
- Sign-out clears no stored secrets: the only values on the device are
  preferences (theme, notification flags, the device id), and the Supabase
  session is cleared by supabase_flutter.

### Account deletion ordering (Phase 10)
`AuthRepository.deleteAccount` re-checks the password, then runs the
`beforeDelete` hook (photo removal), then calls `delete_my_account`, then signs
out. A wrong password therefore changes nothing, including the photo.
