# Put part of an income into savings goals — design

Date: 2026-10-24. Status: approved in chat, awaiting spec review.

## Goal
While adding or editing an income, the user can say "of this ₹50,000, put
₹5,000 into *New phone* and ₹3,000 into *Trip*". Each goal's progress then
includes that money. If the income is later edited or deleted, the goals
follow automatically.

Success: add an income with two goal contributions offline, go online, and
both goals show the new totals on another device; edit the income to drop one
goal and that goal's total goes back down; delete the income and both totals
go back down. Nobody else can read or point at these rows.

## Decisions
- Tracking only, as today (docs/05_FINANCIAL_LOGIC.md): no money moves, the
  income amount and every account balance are unchanged.
- Income transactions only (`type = income`). Not expense, transfer, khata or
  opening balance.
- One income can feed several goals; a goal appears at most once per income.
- A goal's total is **derived**, never written back:
  `totalSaved = saved_amount + sum(live contributions)`. `saved_amount` keeps
  meaning "saved by hand" (the goal form's "Saved so far" and the card's
  "Add money"). A contribution is live when neither it nor its transaction is
  deleted. Deriving the total is what makes edits, deletes, retries and
  two-device edits safe (rule 9): nothing is ever added twice.
- Rejected: applying +/- deltas to `saved_amount` on every save (double counts
  on retry or concurrent devices); turning "Add money" into contributions too
  (gives history, but needs a data migration nobody asked for).
- Out of scope: automatic saving on recurring income, a savings rate in
  reports, contribution history screen, contributions on expenses.

## Schema
New migration `supabase/migrations/20261024090000_savings_contributions.sql`
(the user runs it by hand, before shipping the app version that syncs it):

```sql
alter table public.savings_goals
  add constraint savings_goals_user_id_id_key unique (user_id, id);

create table public.savings_contributions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  transaction_id uuid not null,
  goal_id uuid not null,
  amount numeric(18, 2) not null check (amount > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  foreign key (user_id, transaction_id)
    references public.transactions (user_id, id),
  foreign key (user_id, goal_id) references public.savings_goals (user_id, id)
);
```

- Indexes: `(user_id, transaction_id)`, `(user_id, goal_id)` (every foreign
  key gets one), and a partial unique index on `(transaction_id, goal_id)`
  `where deleted_at is null`.
- `set_updated_at` trigger, RLS enabled, `revoke all` from anon/authenticated,
  then `grant select, insert, update, delete` to authenticated and the four
  own-rows policies, copied from `20261023100000_savings_goals.sql`.
- Composite foreign keys mean a row can only reference the same user's
  transaction and goal (finance_core conventions). Default NO ACTION delete;
  deleting the auth user cascades.
- Not enforced by the database, only by the app: the contributions of one
  transaction sum to at most its amount, and the transaction is an income.
  Offline edits upload row by row, so an in-between state can break the sum
  for a moment; a database check would reject a valid sync.

Local SQLite: `databaseVersion` 3 → 4. `upgrade` gets
`if (oldVersion < 4) await _createSavingsContributions(db);`, which is also
called from `onCreate`. Same columns plus `sync_status`, money as TEXT, index
on `transaction_id` and on `goal_id`.

## Domain
- `domain/entities/savings_contribution.dart`: `SavingsContribution`
  (`id, userId, transactionId, goalId, amount: Decimal, createdAt, updatedAt,
  deletedAt`).
- `SavingsGoal` gains `contributedAmount` (Decimal, default zero) and
  `totalSaved => savedAmount + contributedAmount`. `isReached`, `remaining`,
  `progress` and `isOverdue` use `totalSaved`.
- `domain/services/savings_split.dart` (pure Dart, no Flutter, no I/O):
  - `String? validate({required TransactionType type, required Decimal amount,
    required List<({String goalId, Decimal amount})> parts})`: null when fine,
    else the first message ("Amount must be more than zero", "This goal is
    already used", "Savings can't be more than the income", "Only an income
    can go to savings"). The last one is for non-income with parts;
    non-income without parts is fine. An unpicked goal
    never reaches it: the row's dropdown validator says "Choose a goal".
  - `SplitChanges diff(List<SavingsContribution> current,
    List<({String goalId, Decimal amount})> wanted)`: matched by `goalId`;
    same goal keeps its row id (amount updated only when it changed), new goal
    gets a new row, missing goal is soft-deleted. A non-income transaction
    wants nothing, so all its rows are soft-deleted.
  - `Map<String, Decimal> sumByGoal(Iterable<SavingsContribution> live)`.

## Data
- `data/models/savings_contribution.dart`: row mapping (`amount` as string).
- `TransactionRepository`
  - `createTransaction(tx, {List<SavingsContribution> contributions = const []})`
    and `updateTransaction(tx, {SplitChanges? savings})`: with the local
    database, one `db.transaction` writes the transaction row, the
    contribution rows and their queue items, transaction first (same pattern
    as `createTransfer`). Without it (Supabase only): upsert the transaction,
    then the contributions; every write is an upsert on a client id, so a
    retry repeats it harmlessly.
  - `deleteTransaction` also soft-deletes that transaction's live
    contributions in the same database transaction and queues them.
  - `getContributions(String transactionId)`: live rows, for the form and the
    detail screen.
- `SavingsGoalRepository`
  - `getSavingsGoals()` fills `contributedAmount`. SQLite: select live
    contributions joined to transactions with `deleted_at IS NULL`. Supabase:
    select live contributions, then keep those whose transaction id is among
    the live transactions (second query, `inFilter('id', ...)`). Both then
    add up with `SavingsSplit.sumByGoal` in Dart: amounts are TEXT and a
    SQLite `SUM` would add them as floating point.
  - `deleteSavingsGoal` also soft-deletes the goal's contributions in the same
    database transaction.
- Sync: `savings_contributions` appended to `SyncEngine.downloadDelta`'s list
  after `savings_goals` (pulled with `user_id = me`), and to
  `AppDatabase.clearAllUserData`. A pulled contribution whose transaction or
  goal has not arrived yet is just stored; the sums ignore it until they do.
- Backup: added to `BackupService.supportedTables`, `uploadTables` and the
  restore order after `savings_goals`; label and icon in
  `backup_preview_dialog.dart` and `sync_status_sheet.dart`.

## Presentation
- `TransactionController` takes an optional named
  `SavingsGoalRepository? savingsGoals` (like the receipt store, so existing
  constructions keep working), loads `goals` in `loadLookups`, and
  `saveTransaction` takes `List<({String goalId, Decimal amount})> savings`.
  It validates with `SavingsSplit.validate`, fetches the current rows on edit,
  builds the changes with `SavingsSplit.diff`, and calls the repository.
  `TransactionBinding` passes the repository.
- New widget `features/transactions/widgets/savings_split_field.dart`, shown
  in the transaction form only for income:
  - Collapsed: a "+ Put some in savings" button. No goals yet: "Create a
    savings goal first", opening the goal form.
  - Each row: goal dropdown (live goals not used in another row), amount
    field, remove button. "+ Another goal" adds a row.
  - Footer, recomputed as the user types: "₹8,000 to savings · ₹42,000 left".
  - The validate message shows under the section; the save button stays
    enabled and submit refuses to save while it is invalid.
  - Switching the type to expense hides the section and clears its rows.
  - Editing preloads the transaction's contributions.
- Goal card: progress from `totalSaved`; when `contributedAmount > 0` a line
  "₹8,000 from income".
- Goal form: "Saved so far" edits `saved_amount` only; helper text
  "+ ₹8,000 added from income" when there is some.
- Transaction detail: "Savings: New phone ₹5,000 · Trip ₹3,000" when the
  income has contributions (goal names from the goals list; a deleted goal's
  rows are already soft-deleted).
- All new strings in English keys with Hinglish and Hindi entries; touched
  files stay in `translation_coverage_test.dart`'s list (add the new widget).

## Docs to update
03_DATABASE_SCHEMA (table, index list, migration list), 04_SECURITY_RLS
(policies), 05_FINANCIAL_LOGIC (derived total, validation rules),
07_OFFLINE_SYNC (table order, atomic write), 01_PRODUCT_REQUIREMENTS (scope),
12_UI_NAVIGATION_MAP (form section).

## Testing
- `savings_split` unit tests: each validation message, exact decimals
  (`0.10 + 0.20` against `0.30`), diff keeps ids / updates / inserts /
  deletes, non-income clears everything, `sumByGoal`.
- `SavingsGoal`: `totalSaved` drives reached, remaining, progress, overdue.
- Repository tests on `AppDatabase.inMemory()`: create writes transaction and
  contributions with queue order transaction → contributions; a failure inside
  the database transaction leaves nothing; edit applies a diff; deleting the
  transaction or the goal soft-deletes and queues its contributions; goal sums
  ignore deleted contributions and contributions of deleted transactions;
  upgrade from version 3 creates the table.
- Controller tests with `FakeFinance` (fake contribution storage added):
  invalid split is not saved and shows the message; valid split saves; edit
  and delete change goal totals.
- Widget test: rows add/remove, footer total, error message, section hidden
  for expense, edit preloads rows.
- Translation coverage and the full suite. The two `planning_flow_test.dart`
  recurring failures exist before this work and are not part of it.
