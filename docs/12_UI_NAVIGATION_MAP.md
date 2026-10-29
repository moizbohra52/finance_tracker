# UI Navigation Map (Phases 00–06)

Result of the UI integration pass that followed `UI_INTEGRATION_AUDIT.md`. No schema change.

## Routes

| Route | Screen | Controller / binding | Opened from |
|---|---|---|---|
| `/splash` | Splash | `SplashController` | app start |
| `/onboarding`, `/login`, `/register`, `/forgot-password` | Auth (guest only) | existing | splash, auth links |
| `/reset-password`, `/change-password` | Password flows | existing | recovery link, profile |
| `/dashboard` | App shell, 4 tabs | `ShellBinding` → `HomeController`, `TransactionController`, `ContactController`, `ContactFormController`, `AccountController`, `ProfileController` | splash / sign-in |
| tab 0 | Home (balance, quick actions, today, khata, accounts, recent) | `HomeController` | bottom nav |
| tab 1 | Transactions list (search, filter sheet, day groups, paging) | `TransactionController` | bottom nav |
| tab 2 | Khata (summary, search, receivable/payable filter) | `ContactController` | bottom nav |
| tab 3 | Reports (date filter, totals, charts, categories, accounts, monthly comparison) | `ReportsController` | bottom nav |
| `/reports` | Reports (route form of tab 3) | `ReportsBinding` | Home "Reports" / "Details" |
| `/profile` | Profile (not a tab since 2026-10-14) | `ProfileController` | app-bar avatar, app-bar menu |
| account switcher (bottom sheet) | Signed-in accounts, switch, *Sign in to another account* | `AccountSwitchController` | long press on the app-bar avatar, app-bar menu *Switch account*, Profile and Settings *Switch account* |
| `/add-account` | Sign in to another account (signed-in only) | `AddAccountController` | account switcher |
| app lock cover (not a route) | "Track Day is locked", *Unlock* | `AppLockController` | app start and every return from the background when Settings > Security > *App lock* is on |
| `/switch-account` | "Switching to ..." while the account changes (no guard) | `AccountSwitchController` | account switch, sign-out hand-over, notification of another account |
| `/transactions` | Transaction list (route form of tab 1) | `TransactionBinding` | Home "See all" |
| `/transaction-form` | Add income / add expense / edit (`TransactionFormArgs`); the income form has a savings section (*Put some in savings*: goal + amount rows, shows the amount left) | `TransactionBinding` | Home quick actions, list FAB, detail Edit |
| `/transfer-form` | Transfer between two accounts, or edit one (`TransferFormArgs`) | `TransactionBinding` | Home quick action *Transfer*, list FAB sheet, account detail, transfer detail Edit |
| `/transaction-detail` | Transaction details, edit, delete (arg: id); an income put into goals shows a *Savings* line ("goal amount · goal amount") | `TransactionDetailBinding` | any transaction row |
| `/contacts` | Khata list (route form of tab 2) | `ContactBinding` | Home "Open" |
| `/contact-form` | Add / edit contact (arg: `Contact` for edit) | `ContactBinding` | Khata FAB, contact detail |
| `/contact-detail` | Contact ledger, balance, delete (arg: id) | `ContactDetailBinding` | contact row |
| `/contact-entry` | Add credit / debit / payment (`ContactEntryArgs`) | `ContactBinding` | contact detail, Home Credit/Debit |
| `/split-groups` | Split groups list (name, member count, the user's net) | `SplitGroupBinding` | Khata app bar *Groups* |
| `/split-group-form` | Add / edit / delete a group: name, member chips, member picker sheet (arg: `SplitGroupSummary` for edit) | `SplitGroupBinding` | Groups FAB and empty state |
| `/split-group-detail` | Header totals, balances (`@from → @to @amount` with *Settle*), paged activity; edit via app bar (arg: group id) | `SplitGroupDetailBinding` | group row, after saving in the group form |
| `/split-settlement-form` | Settle up: from → to, amount (outstanding prefilled), date, account when the user is a party, note (`SplitSettlementArgs`) | `SplitSettlementBinding` | detail *Settle* buttons and settlement rows |
| `/accounts`, `/account-form`, `/account-detail` | Accounts, opening balance, detail (arg: id / `Account`) | `AccountBinding`, `AccountDetailBinding` | Home Accounts section *Manage*, app-bar menu |
| `/budgets` | Budget list with progress, spent/left, 75/90/100 state | `BudgetBinding` → `BudgetController` | Home "Plan ahead" |
| `/budget-form` | Add / edit / delete budget (arg: `Budget` for edit) | `BudgetBinding` | Budgets FAB, budget card |
| `/recurring` | Recurring schedules, pause/resume | `RecurringBinding` → `RecurringController` | Home "Plan ahead" |
| `/recurring-form` | Add / edit / delete schedule incl. custom interval (arg: rule for edit) | `RecurringBinding` | Recurring FAB, schedule row |
| `/savings-goals` | Savings goals with progress, left, reached/overdue, the part from income; "Add money" dialog per goal | `SavingsGoalBinding` → `SavingsGoalController` | Home "Plan ahead" |
| `/savings-goal-form` | Add / edit / delete goal (arg: `SavingsGoal` for edit) | `SavingsGoalBinding` | Savings goals FAB, goal card |
| `/settings` | Settings | — | app-bar gear |
| `/categories` | Own and built-in categories, by kind | `CategoryBinding` → `CategoryController` | Settings > Categories |
| `/category-form` | Add / edit / delete an own category (`CategoryFormArgs`); returns the id | `CategoryBinding` | Categories FAB and rows, *New* chip in the income/expense and recurring forms |

Search and filters are part of the transaction list (search field + filter bottom sheet), not separate routes.

## Decisions

- **`AppRepositories`** (`data/repositories/app_repositories.dart`): repositories are built once in `main()` and injected through `FinanceTrackerApp`/`InitialBinding`. `InitialBinding` no longer reads `Supabase.instance`, so widget tests run with in-memory fakes (`test/helpers/fake_finance.dart`).
- **`DataChangeNotifier`** (`core/services`): a version counter bumped after every write; open controllers reload on change, so Home, lists and Khata stay consistent without knowing each other.
- **Write payloads** (`data/repositories/payloads.dart`): inserts take `user_id` from the session and leave `created_at`/`updated_at` to the server; updates never send ownership or timestamps. Creates are `upsert` on the client UUID (idempotent retries, rule 9).
- **Soft deletes**: accounts, transactions, contacts and contact entries are tombstoned with `deleted_at` (per `07_OFFLINE_SYNC.md`); all reads filter `deleted_at is null`.
- **Totals** live in `domain/services/finance_summary_calculator.dart` (account balances, period income/expense, khata receivable/payable). Controllers only hold results.
- **Fixes found while wiring**: numeric JSON parsed `as String`; local timestamps sent without a zone; `DateFormat` locale `en_IN` never initialised; `NumberFormat.currency` showing `INR` instead of `₹`; record `.wait` hiding `AppException` (see `core/utils/parallel.dart`); account edits overwriting `user_id` with `''`; `opening_balance_date` (NOT NULL) possibly null.

## Known limits (documented, not hidden)

- Balances are computed client-side from the full transaction history (paged 500 at a time). Move to a server-side aggregate when history grows large.
- Khata contacts are loaded in full and searched in memory.
- Search matches transaction notes/descriptions, not category names.
- Offline writes are not queued yet (Phase 7+); write failures show an inline error and keep the form open.

## Phase 07 decisions

- **Package added:** `fl_chart` (line, bar and donut charts; hand-rolling them was not justified).
- **Domain:** `report_period.dart` (presets, half-open ranges, Monday weeks) and `report_calculator.dart` (summary, category/account totals, trend buckets, 6-month comparison). Only `income` and `expense` rows count; transfers, adjustments and khata settlements are excluded.
- **Reports data:** `ReportsController` fetches one window (selected period plus the 6-month comparison) and re-computes in memory when the filter stays inside it.
- **Not built (no screen exists yet):** quick actions *Transfer* and *Reminder* (Phase 9), and the notification bell (Phase 9). Omitted rather than shipped as dead buttons.
- **No database change.**

## Phase 08 decisions

- **Migration `20261007100000_recurring_interval.sql`**: adds `recurring_transactions.interval_count` (default 1) for custom schedules. Apply with `supabase db push`. Until then everything except a custom interval works (the column is only sent when it is not 1).
- **Budgets** (`domain/services/budget_calculator.dart`): spent = expenses in the budget's period for its category (or all). Monthly budgets measure the calendar month; custom budgets measure `start..end` inclusive. Thresholds use exact decimal comparison (`spent * 100 >= amount * t`).
- **No duplicate alerts**: an alert's id is a UUID v5 of budget id, period start and threshold, written to `notifications` (type `budget_alert`) with ON CONFLICT DO NOTHING, and each controller also remembers what it already sent. Showing notifications is Phase 9.
- **Recurring** (`domain/services/recurring_scheduler.dart`): occurrences are computed from the start date (so a 31st stays month-end) at 09:00 local. A run turns every due occurrence into a transaction whose id is a UUID v5 of rule id and date, inserted only if absent, and only then advances `next_run_at`. Runs happen when the signed-in shell opens and on pull-to-refresh; a server-side scheduler is a later improvement. A run creates at most 366 occurrences per rule.
- New schedules cannot start in the past, so nothing is back-filled; resuming a paused schedule skips what was missed.

## Phase 09 decisions

New routes:

| Route | Screen | Controller / binding | Opened from |
|---|---|---|---|
| `/reminders` | Reminder list (overdue / upcoming / completed, enable switch, permission banner) | `ReminderBinding` -> `ReminderController` | Home "Reminders" tile |
| `/reminder-form` | Add / edit reminder (arg: `ReminderFormArgs`) | `ReminderBinding` | list FAB, contact detail "Add reminder", transaction detail "Remind me", reminder detail "Edit" |
| `/reminder-detail` | Reminder with Mark as done, Snooze, Edit, Delete, link to contact/transaction (arg: id) | `ReminderBinding` | list row, notification tap |
| `/notifications` | Notification center (paged, mark read, mark all read) | `NotificationCenterBinding` -> `NotificationCenterController` | app-bar bell, Home "Notifications" tile, unknown notification tap |

- The app-bar bell on the shell shows the unread count (`99+` at the cap).
- Settings has a **Notifications** section (master, reminders, budget alerts,
  recurring, sound, vibration, exact-alarm row on Android).
- `ReminderController` and `NotificationCenterController` are created by
  `ShellBinding` with the budget and recurring controllers, because they keep
  the device schedule and the badge current without their screens being open.
- Budget and recurring alerts now go through `NotificationCoordinator.raise`
  (stored once in the center, shown on the device the first time only).
  `NotificationRepository.raiseOnce` returns whether it created the row.
- The Phase 07 note "quick action Reminder and notification bell: not built"
  is resolved by the bell and the Home tiles; the quick-action row was left at
  five buttons (a sixth does not fit narrow phones).
- **Packages added:** `flutter_local_notifications` ^22.3.1 (the documented
  local-notification package), `timezone` and `flutter_timezone` (scheduled
  notifications need the device zone), `firebase_core` and `firebase_messaging`
  (FCM). `connectivity_plus` is pinned to 7.3.1 (was ^7.3.2): the stable
  `flutter_local_notifications` 22.x and `connectivity_plus` 7.3.2 require
  incompatible versions of the Linux-only `nm` package, and the alternative was
  a pre-release notification plugin. Revisit when a compatible pair is published.

## Phase 10 decisions

New routes (all signed-in only):

| Route | Screen | Opened from |
|---|---|---|
| `/settings` | Appearance, region and format, notifications, security, information | app-bar menu |
| `/about` | Version and open-source licences | Settings > About |
| `/privacy-policy` | Placeholder page, says so | Settings > Information |
| `/terms` | Placeholder page, says so | Settings > Information |

- The profile tab is the account page: photo, name, mobile, email and time zone
  (the last two read-only), change password, sign out, and delete account.
- Settings is organised into Appearance, Region and format, Notifications,
  Security and Information. Each region row opens a list; a choice is saved at
  once and confirmed with a message.
- Language offers English only; the row says more are coming.
- The new-transaction form pre-selects the default account when it still exists.
- Removed: the dead "Backup & Export" tiles (Phase 12 scope) and the placeholder
  "Check for updates" row.
- **Package added:** `image_picker` (photo selection). Photos are scaled to 512
  px and JPEG quality 85 at pick time, then checked against the 2 MiB limit.
- **Upload progress** is indeterminate: the storage client does not report byte
  progress, so the photo shows a spinner while uploading.

## 2026-10-14 decisions: transfers, categories, navigation

- **Profile is not a bottom-navigation tab.** It already opened from the
  app-bar avatar and menu, so the tab duplicated it. The shell has four tabs:
  Home, Transactions, Khata, Reports.
- **Transfers** (`/transfer-form`): amount, From, To (the source is not
  offered as a destination), date and note. Both legs are built in
  `domain/services/transfer_legs.dart` and written together by
  `TransactionRepository.createTransfer` (one local database transaction with
  both sync-queue items). Rows show "To <account>" / "From <account>" when the
  other leg is loaded; the detail screen shows From/To, edits open the
  transfer form, and delete removes both legs. Rules and edit behaviour are in
  `docs/05_FINANCIAL_LOGIC.md`.
- The Home quick action *Accounts* became *Transfer* (as
  `docs/11_DESIGN_REFERENCE.md` suggests); accounts open from the Accounts
  section's *Manage*.
- **Categories** (`/categories`, `/category-form`): users add, rename,
  re-icon and delete their own income or expense categories; built-in ones are
  read-only (RLS refuses writes to them). Names must be unique per kind,
  ignoring case and including built-in names. The kind is fixed once created.
  Deleting is a soft delete: rows that used the category keep their amounts.
  The income/expense and recurring forms offer a *New* chip that opens the
  form and selects the result.
- Category chips (`widgets/category_picker.dart`) show no check mark: the
  selected chip has a thicker primary border and the selected fill.
- **No database change.** `categories` RLS already allowed own-row writes and
  `transactions.transfer_id` with its unique indexes already existed.

