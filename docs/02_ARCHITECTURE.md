# Architecture

## Pattern
Use a pragmatic feature-first layered architecture:

lib/
  core/
    constants/
    errors/
    theme/
    utils/
    widgets/
    services/
    storage/
  data/
    datasources/
    models/
    repositories/
  domain/
    entities/
    services/
    calculators/
  features/
    auth/
    dashboard/
    accounts/
    transactions/
    khata/
    reports/
    budgets/
    recurring/
    reminders/
    notifications/
    profile/
    settings/
  routes/
  bindings/
  main.dart

## Responsibilities
### UI
Displays state and forwards user actions.

### Controller
Owns screen/application state and calls repositories/services.

### Repository
Provides a stable interface for remote/local data.

### Data source
Supabase or local database implementation.

### Domain service
Financial calculations and business rules.

## GetX
Use:
- GetxController
- Bindings
- Get.to/Get.offAll or named routes
- Obx only where reactive updates are needed

Avoid:
- giant controllers
- Get.find everywhere without clear bindings
- database access from widgets

## Folder conventions (decided in Phase 00, updated in Phase 02)
- `lib/bindings/` holds app-wide bindings only (`InitialBinding`), which
  receives the repositories so tests can pass fakes.
- Each feature folder holds presentation code only:
  `features/<feature>/{controllers,views,widgets}/`.
- Screen dependencies are bound on their route in `routes/app_pages.dart`
  (`BindingsBuilder`); a feature gets its own binding file only when that setup
  grows beyond a line or two.
- Data access stays in `lib/data/`, business rules in `lib/domain/`.
- While a repository has a single remote source, it calls the Supabase SDK
  directly (the SDK client is the data source). A separate class in
  `data/datasources/` is added when a repository combines remote and local
  data (offline sync).
- Repositories throw only `AppException` subclasses
  (`core/errors/app_exception.dart`); `guardSupabase` maps SDK errors to
  user-safe messages.
- Route names live in `routes/app_routes.dart`, pages in `routes/app_pages.dart`,
  guards (`AuthGuard`, `GuestGuard`) in `routes/route_guards.dart`.
- Theme tokens live in `core/theme/`; semantic money colours are the
  `FinanceColors` theme extension.

## Auth navigation (Phase 02)
`AuthController` (app-wide) is the only place that navigates on auth
transitions: signed in → dashboard (from guest screens only), signed out →
login (or, since 2026-10-15, another signed-in account via
`AccountSwitchController`), password recovery → reset password. Screens call the repository and
let it route. The splash screen makes the first routing decision; the auth
event stream replays history, so a cold-start reset link is never lost.

## Dependency direction
UI -> Controller -> Repository -> DataSource
Controller/domain orchestration -> Domain services
Never reverse this dependency.

## Error model
Create typed app exceptions/failures for:
- auth
- validation
- network
- database
- sync
- permission
- notification

Convert low-level errors into user-friendly messages at the appropriate boundary.

## Notifications (Phase 09)
`NotificationCoordinator` (`core/services`) is an app-wide GetX service created
in `main()` and injected through `FinanceTrackerApp` -> `InitialBinding`, like
the repositories, so tests pass fakes (`test/helpers/fake_notifications.dart`).
Controllers never touch the notification plugin: they call the coordinator
(`syncReminders`, `raise`), which owns `LocalNotificationService` and
`PushService`. What to schedule is decided by pure domain code
(`ReminderNotificationPlanner`), and the screen a tap opens by
`NotificationTarget`. Details: `docs/08_NOTIFICATION_SYSTEM.md`.

## Account scope (Phase 10)
`bindings/user_scope.dart` owns what happens to per-user state:
- `loadUserScope()` runs on every sign-in and loads the preferences.
- `resetUserScope()` runs after the sign-in screen has replaced the app, on the
  next frame. It resets `SettingsController` and removes the controllers that
  hold a user's data or typed passwords. Controllers registered with `fenix`
  are disposed and rebuilt fresh on next use, so the user's instance is
  replaced even though the registration stays.
- Global infrastructure (repositories, the notifier, the notification
  coordinator, storage) is never removed.

## App lock (2026-10-15)
`AppLockController` (`features/app_lock`, permanent GetX service) is created
and initialised in `main()` before `runApp`, like the notification
coordinator, because its back-button observer must come before the
navigator's. `DeviceAuthService` (`core/services`) wraps `local_auth`;
`AppLockGate` is installed through `GetMaterialApp.builder`, above every
route. Screens that open another app wrap it in `ExternalActivity.run` so
coming back does not lock. Rules: `docs/04_SECURITY_RLS.md`.

## Several signed-in accounts (2026-10-15)
Like a social app, several accounts can be signed in on one device and the
user switches between them (app-bar avatar long press or menu, Profile and
Settings > *Switch account*). `AccountSwitchController`
(`features/auth/controllers`, permanent) owns it:
- `SavedLoginStore` (`data/datasources/local`) keeps every signed-in account
  (`SavedLogin` entity: id, email, name, last used) and its session.
- `AuthRepository` adds `signInDetached`, `holdCurrentSession`,
  `activateSession` and `currentSession`; Supabase types stay inside it.
- Each account has its own local database file (`docs/07_OFFLINE_SYNC.md`).
- A switch shows `/switch-account`, waits for the previous screens' route
  transition to end, runs `resetUserScope()`, activates the other session and
  opens its file with sync paused, then `loadUserScope()` and the dashboard.
- `AuthController` still receives every auth event, and hands sign-in and
  sign-out to `AccountSwitchController`: a sign-in opens that account's file
  before anything reads it; a sign-out removes the account and lets the most
  recently used other account take over, or shows sign-in when none is left.
  At start-up without a session, a saved account takes over (splash).
- `NotificationCoordinator` asks it whether other accounts remain
  (`hasOtherAccounts`) and hands it taps for other accounts
  (`onOtherAccountTarget`); see `docs/08_NOTIFICATION_SYSTEM.md`.
- `resetUserScope()` no longer touches the database; what happens to an
  account's file is the controller's decision.
- In the UI the action is "Sign in to another account", never "Add account",
  which already means adding a cash/bank account.

Formatting is centralised in `AppFormatters`, which reads `UserPreferences`.
Widgets pass no symbols, locales or patterns of their own, except fixed labels
such as chart axes.
