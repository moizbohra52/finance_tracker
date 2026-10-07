# Claude Documentation Pack — Finance Tracker

## How to use

1. Copy this documentation into the root of the Flutter project.
2. Keep `CLAUDE.md` at the project root.
3. Ask Claude Code to read `CLAUDE.md`.
4. Execute phases in order from `phases/PHASE_00...` through `PHASE_14...`.
5. Do not give all phase files as one coding task. One phase at a time is safer.
6. After each phase, run the acceptance criteria and only then move forward.

## Source of truth

`CLAUDE.md` contains permanent engineering rules.
`docs/` contains product/architecture specifications.
`phases/` contains executable implementation plans.
`checklists/` contains reusable QA/release checklists.

## Recommended Claude command pattern

Read:
- CLAUDE.md
- the current phase file
- every referenced docs file

Then inspect the repository and implement only that phase.

At completion, report changed files, tests, analyzer results, and unresolved issues.

## Development

Requires Flutter 3.44+ (Dart 3.12+). Targets Android and iOS.

### Environment

Configuration is passed at build time with `--dart-define-from-file`, read in
`lib/core/constants/app_env.dart`.

1. Copy `env.example.json` to `env.json` (git-ignored) and fill in values.
2. Run with the file:

```
flutter run --dart-define-from-file=env.json
```

Only public client values (Supabase URL and publishable key, or the legacy
anon key) may go in `env.json`.
Never put the Supabase service-role key or any server secret in the app.

### Checks

```
dart format .
flutter analyze
flutter test
```

### Database (Supabase)

Schema, RLS and seed data are SQL migrations in `supabase/migrations/`
(order and decisions: `docs/03_DATABASE_SCHEMA.md`).

Apply to a hosted project:

```
supabase link --project-ref <project-ref>
supabase db push
```

Or locally (requires Docker): `supabase start`, then `supabase db reset`.

Verify cross-user isolation on a local or development database (never
production): run `supabase/checks/cross_user_isolation.sql` with `psql` or
paste it into the SQL Editor. It rolls back everything it creates; no error
means every check passed.

### Auth settings (hosted project)

`supabase/config.toml` covers local development. On the hosted project, set
these in the dashboard to match the app:

- Authentication → URL Configuration → Redirect URLs: add
  `com.example.financetracker://auth-callback` (used by email confirmation and
  password reset links; must match `AppConstants.authRedirectUrl`).
- Authentication → Providers → Email: minimum password length 8, require
  letters and digits (mirrors `Validators.newPassword`). Keep "Confirm email"
  on; the app handles both confirmation modes.

Auth links open the app only on the device that requested them (PKCE).

### Dependencies

| Package | Why |
|---|---|
| `get` 4.7.3 | State management, routing and DI, mandated by CLAUDE.md. 5.x is still a release candidate. |
| `supabase_flutter` 2.18 | Supabase Auth and database client; persists and refreshes the session, handles auth deep links. |
| `http` 1.6 | Already pulled in by Supabase; imported directly only to recognise `ClientException` as a network failure. |

Other packages (local database, notifications, charts) are added in the phase
that first uses them.
