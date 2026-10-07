# UI Navigation Map (Phases 00–06)

Result of the UI integration pass that followed `UI_INTEGRATION_AUDIT.md`. No schema change.

## Routes

| Route | Screen | Controller / binding | Opened from |
|---|---|---|---|
| `/splash` | Splash | `SplashController` | app start |
| `/onboarding`, `/login`, `/register`, `/forgot-password` | Auth (guest only) | existing | splash, auth links |
| `/reset-password`, `/change-password` | Password flows | existing | recovery link, profile |
| `/dashboard` | App shell, 5 tabs | `ShellBinding` → `HomeController`, `TransactionController`, `ContactController`, `ContactFormController`, `AccountController`, `ProfileController` | splash / sign-in |
| tab 0 | Home (balance, quick actions, today, khata, accounts, recent) | `HomeController` | bottom nav |
| tab 1 | Transactions list (search, filter sheet, day groups, paging) | `TransactionController` | bottom nav |
| tab 2 | Khata (summary, search, receivable/payable filter) | `ContactController` | bottom nav |
| tab 3 | Reports (date filter, totals, charts, categories, accounts, monthly comparison) | `ReportsController` | bottom nav |
| `/reports` | Reports (route form of tab 3) | `ReportsBinding` | Home "Reports" / "Details" |
| tab 4 | Profile | `ProfileController` | bottom nav |
| `/transactions` | Transaction list (route form of tab 1) | `TransactionBinding` | Home "See all" |
| `/transaction-form` | Add income / add expense / edit (`TransactionFormArgs`) | `TransactionBinding` | Home quick actions, list FAB, detail Edit |
| `/transaction-detail` | Transaction details, edit, delete (arg: id) | `TransactionDetailBinding` | any transaction row |
| `/contacts` | Khata list (route form of tab 2) | `ContactBinding` | Home "Open" |
| `/contact-form` | Add / edit contact (arg: `Contact` for edit) | `ContactBinding` | Khata FAB, contact detail |
| `/contact-detail` | Contact ledger, balance, delete (arg: id) | `ContactDetailBinding` | contact row |
| `/contact-entry` | Add credit / debit / payment (`ContactEntryArgs`) | `ContactBinding` | contact detail, Home Credit/Debit |
| `/accounts`, `/account-form`, `/account-detail` | Accounts, opening balance, detail (arg: id / `Account`) | `AccountBinding`, `AccountDetailBinding` | Home Accounts, quick action |
| `/budgets` | Budget list with progress, spent/left, 75/90/100 state | `BudgetBinding` → `BudgetController` | Home "Plan ahead" |
| `/budget-form` | Add / edit / delete budget (arg: `Budget` for edit) | `BudgetBinding` | Budgets FAB, budget card |
| `/recurring` | Recurring schedules, pause/resume | `RecurringBinding` → `RecurringController` | Home "Plan ahead" |
| `/recurring-form` | Add / edit / delete schedule incl. custom interval (arg: rule for edit) | `RecurringBinding` | Recurring FAB, schedule row |
| `/settings` | Settings | — | app-bar gear |

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
