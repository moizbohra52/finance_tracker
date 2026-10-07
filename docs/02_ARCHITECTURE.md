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
login, password recovery → reset password. Screens call the repository and
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
