# Income → Savings Goals Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** While adding or editing an income, the user can put parts of it into one or more savings goals; goal totals follow edits and deletes automatically.

**Architecture:** New synced table `savings_contributions` (one row per income × goal). A goal's total is derived: `saved_amount` (by hand) + live contributions, summed in Dart with `Decimal`. Transaction and contribution writes happen in one SQLite transaction; pure rules live in `domain/services/savings_split.dart`.

**Tech Stack:** Flutter, GetX, sqflite (local), Supabase (Postgres + RLS), `decimal`.

**Spec:** `docs/superpowers/specs/2026-10-24-income-savings-split-design.md`

## Global Constraints

- Money is `Decimal` in Dart, `NUMERIC(18,2)` on the server, TEXT in SQLite. Never sum money with SQLite `SUM` or `double`.
- Client-generated UUIDs (`Uuid().v4()`); every write is an upsert/update on that id.
- Soft deletes only (`deleted_at` + `tombstone()` + `SyncOperation.delete` queue item).
- No money moves: income amount and account balances never change because of savings.
- Contributions only on `TransactionType.income`.
- Every user-visible string is an English key with `.tr`, plus entries in `lib/core/translations/hinglish.dart` and `hindi.dart`.
- Supabase migrations are run by the user by hand; write the file, do not apply it.
- Existing files that are not `dart format`-clean today (check with `dart format --output=none --set-exit-if-changed <file>`) are edited by hand only; do not run the formatter over them. New files are formatted.
- Commit only the files of the current task (`git add <paths>`), never `git add -A`.
- `flutter analyze` stays at "No issues found!". The two `planning_flow_test.dart` recurring failures are pre-existing; every other test passes.

## Review Focus

- Editing an income's amount below its existing savings (₹50,000 with ₹8,000 saved → ₹5,000) must refuse to save with "Savings can't be more than the income" → test in Task 6.
- A pulled contribution whose transaction row is not on the phone yet must not count toward the goal → test in Task 5.
- Switching an income to expense while editing must soft-delete all its contributions → test in Task 6.
- Exact-decimal boundary: parts `0.10 + 0.20` on an income of `0.30` is allowed; `0.31` total is not → test in Task 1.
- Editing an income whose goal is missing from the loaded goals list (goals failed to load) must show the row labelled "Savings goal", not throw → test in Task 7.

---

### Task 0: Commit the pending fixes separately

The working tree holds the earlier, unrelated fixes (category refresh in the transaction list, "Add money" on goal cards). Tasks 7–8 touch the same files, so commit them first. **Ask the user before running this task.**

- [ ] **Step 1:** `flutter test test/features/finance/transaction_list_category_test.dart test/features/savings/savings_goals_test.dart` → "All tests passed!"
- [ ] **Step 2: Commit**

```bash
git add lib/features/transactions/views/transaction_list_view.dart test/features/finance/transaction_list_category_test.dart lib/features/savings lib/core/translations/hinglish.dart lib/core/translations/hindi.dart test/features/savings/savings_goals_test.dart docs/01_PRODUCT_REQUIREMENTS.md docs/12_UI_NAVIGATION_MAP.md
git commit -m "fix(transactions,savings): refresh category names in the list; add money to a goal"
```

---

### Task 1: Contribution entity and split rules

**Files:**
- Create: `lib/domain/entities/savings_contribution.dart`
- Create: `lib/domain/services/savings_split.dart`
- Test: `test/domain/savings_split_test.dart`

**Interfaces:**
- Produces:
  - `class SavingsContribution { const SavingsContribution({required String id, required String userId, required String transactionId, required String goalId, required Decimal amount, required DateTime createdAt, required DateTime updatedAt, DateTime? deletedAt}); SavingsContribution copyWith({Decimal? amount, DateTime? updatedAt, DateTime? deletedAt}); }`
  - `typedef SavingsPart = ({String goalId, Decimal amount});`
  - `class SplitChanges { const SplitChanges({this.inserts = const [], this.updates = const [], this.deletes = const []}); final List<SavingsContribution> inserts; final List<SavingsContribution> updates; final List<String> deletes; bool get isEmpty; }` — `deletes` holds contribution ids.
  - `abstract final class SavingsSplit` with:
    - `static String? validate({required TransactionType type, required Decimal amount, required List<SavingsPart> parts})`
    - `static SplitChanges diff({required String transactionId, required List<SavingsContribution> current, required List<SavingsPart> wanted, required String Function() newId, required DateTime now})`
    - `static Map<String, Decimal> sumByGoal(Iterable<SavingsContribution> live)`

- [ ] **Step 1: Write the failing tests** in `test/domain/savings_split_test.dart`:
  - `validate`: returns null for `income`, amount `50000`, parts `[(goalId:'g1',amount:5000),(goalId:'g2',amount:3000)]`; null for `expense` with `[]`; `'Only an income can go to savings'` for `expense` with one part; `'Amount must be more than zero'` for a part of `0`; `'This goal is already used'` for two parts on `'g1'`; `'Savings can\'t be more than the income'` for parts totalling `50000.01` on `50000`.
  - Decimal boundary: income `0.30`, parts `0.10` + `0.20` → null; parts `0.10` + `0.21` → the "more than the income" message.
  - `diff`: current `[c1(g1, 5000), c2(g2, 3000)]`, wanted `[(g1, 6000), (g3, 1000)]` → `updates` is one row with `id == c1.id`, `amount == 6000`, `updatedAt == now`; `inserts` is one row with `goalId == 'g3'`, `transactionId` set, `id` from `newId`, `userId == ''`, `createdAt == now`; `deletes == [c2.id]`.
  - `diff` with an unchanged amount produces no update (`isEmpty` true for current `[c1(g1,5000)]`, wanted `[(g1,5000)]`).
  - `diff` with wanted `[]` deletes every current id.
  - `sumByGoal([c(g1,'0.10'), c(g1,'0.20'), c(g2,'5')])` → `{'g1': Decimal.parse('0.3'), 'g2': Decimal.parse('5')}`.
- [ ] **Step 2:** `flutter test test/domain/savings_split_test.dart` → FAIL (files missing).
- [ ] **Step 3: Implement** the entity and `SavingsSplit` per Interfaces. `validate` checks in this order: non-income with parts, any amount `<= 0`, duplicate `goalId`, total `> amount`. It returns the English keys exactly as above (callers apply `.tr`). `diff` matches by `goalId`.
- [ ] **Step 4:** `flutter test test/domain/savings_split_test.dart` → PASS.
- [ ] **Step 5: Commit** — `git add lib/domain/entities/savings_contribution.dart lib/domain/services/savings_split.dart test/domain/savings_split_test.dart` and `git commit -m "feat(savings): contribution entity and split rules"`.

---

### Task 2: Goal total includes contributions

**Files:**
- Modify: `lib/domain/entities/savings_goal.dart`
- Modify: `lib/data/models/savings_goal.dart` (`fromJson` only)
- Test: `test/features/savings/savings_goals_test.dart` (group `progress`)

**Interfaces:**
- Produces: `SavingsGoal({..., Decimal? contributedAmount})` with `final Decimal contributedAmount` (initialised `contributedAmount ?? Decimal.zero`; the constructor stops being `const` because `Decimal.zero` is not a constant) and `Decimal get totalSaved => savedAmount + contributedAmount`. `isReached`, `remaining`, `progress`, `isOverdue` use `totalSaved`.
- Produces: `SavingsGoalModel.fromJson` reads an optional `json['contributed_amount']` (absent → zero). `toJson` is unchanged (the value is never stored).

- [ ] **Step 1: Write the failing test** `'contributions count toward progress, remaining and reached'`: goal target `1000`, saved `250`, contributed `750` → `totalSaved == 1000`, `isReached`, `remaining == 0`, `progress == 1`, and `isOverdue(DateTime(2100))` false with a past target date. Extend the `goal()` helper with `String contributed = '0'`.
- [ ] **Step 2:** `flutter test test/features/savings/savings_goals_test.dart` → FAIL (no named parameter `contributedAmount`).
- [ ] **Step 3: Implement** per Interfaces.
- [ ] **Step 4:** `flutter test test/features/savings/savings_goals_test.dart` → PASS; `flutter analyze` → no issues (fix any `const SavingsGoal(` call sites).
- [ ] **Step 5: Commit** — `git commit -m "feat(savings): goal total includes income contributions"` with the three files.

---

### Task 3: Storage — migration, local table, model, sync and backup lists

**Files:**
- Create: `supabase/migrations/20261024090000_savings_contributions.sql`
- Create: `lib/data/models/savings_contribution.dart`
- Modify: `lib/data/datasources/local/app_database.dart` (`databaseVersion`, `upgrade`, `_createTables`, `clearAllUserData`)
- Modify: `lib/core/services/sync_engine.dart` (`downloadDelta` list)
- Modify: `lib/core/services/backup_service.dart` (`supportedTables`, `uploadTables`, `insertOrder`)
- Modify: `lib/features/backup/widgets/backup_preview_dialog.dart` (`_friendlyTableName`), `lib/core/widgets/sync_status_sheet.dart` (icon + `_formatEntityName`)
- Modify: translations (`'Savings contributions'`, `'Savings contribution'`)
- Modify: `docs/03_DATABASE_SCHEMA.md`, `docs/04_SECURITY_RLS.md`, `docs/07_OFFLINE_SYNC.md`
- Test: `test/data/datasources/app_database_test.dart`, `test/data/models/savings_contribution_model_test.dart`

**Interfaces:**
- Produces: `abstract final class SavingsContributionModel { static SavingsContribution fromJson(Map<String, dynamic> json); static Map<String, dynamic> toJson(SavingsContribution c); }` — `toJson` has `id, user_id, transaction_id, goal_id, amount` (amount as string), like `SavingsGoalModel.toJson` (no timestamps). `fromJson` reads timestamps and accepts `amount` as num or string (`.toString()`).
- Produces: local table `savings_contributions(id TEXT PRIMARY KEY, user_id TEXT, transaction_id TEXT NOT NULL, goal_id TEXT NOT NULL, amount TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT, sync_status TEXT NOT NULL DEFAULT 'synced')`, indexes `idx_savings_contributions_tx(transaction_id)` and `idx_savings_contributions_goal(goal_id)`, created by `static Future<void> _createSavingsContributions(DatabaseExecutor db)`; `databaseVersion = 4`.

- [ ] **Step 1: Write the failing tests:**
  - `app_database_test.dart`: `'upgrading a version 3 file adds the savings contributions table'` — open a v3 file (same style as the existing v1 test, `singleInstance: false`), `AppDatabase.upgrade(old, 3, AppDatabase.databaseVersion)`, `PRAGMA table_info(savings_contributions)` contains `goal_id` and `transaction_id`.
  - `savings_contribution_model_test.dart`: round trip; `fromJson` with `amount: 1500.5` (num) → `Decimal.parse('1500.5')`; `toJson` has no `created_at`.
- [ ] **Step 2:** run both files → FAIL.
- [ ] **Step 3: Implement** the model, the local table, `if (oldVersion < 4) await _createSavingsContributions(db);`, the call in `_createTables`, and `'savings_contributions'` appended after `'savings_goals'` in: `clearAllUserData`, `downloadDelta`'s `syncableTables`, `supportedTables`, `uploadTables`, `insertOrder`; `case 'savings_contributions'` in the two label switches (icon `Icons.savings_outlined`).
- [ ] **Step 4: Write the migration** exactly as the spec's Schema section: the `savings_goals_user_id_id_key` constraint, the table, `savings_contributions_user_tx_idx (user_id, transaction_id)`, `savings_contributions_user_goal_idx (user_id, goal_id)`, `create unique index savings_contributions_live_key on public.savings_contributions (transaction_id, goal_id) where deleted_at is null`, the `set_updated_at` trigger, RLS enable, revoke/grant and four policies named `"Users can view|create|update|delete their own savings contributions"`, copied from `20261023100000_savings_goals.sql`. Header comment: apply before shipping the app version that syncs it.
- [ ] **Step 5: Docs:** 03 — the table block, the two indexes in the index list, the migration in the migration list; 04 — the policies line; 07 — table order (after `savings_goals`) and "a transaction and its contributions are written in one local transaction".
- [ ] **Step 6:** run both test files → PASS; `flutter test test/core/translations` → PASS; `flutter analyze` → no issues.
- [ ] **Step 7: Commit** — task files only, `git commit -m "feat(savings): savings_contributions table, local schema v4, sync and backup"`.

---

### Task 4: Transaction writes carry contributions

**Files:**
- Modify: `lib/data/repositories/transaction_repository.dart`
- Modify: `test/helpers/fake_finance.dart` (`FakeFinance.contributions`, `FakeTransactionRepository`)
- Test: `test/data/repositories/savings_contributions_repository_test.dart`

**Interfaces:**
- Consumes: Task 1 `SavingsContribution`, `SplitChanges`; Task 3 `SavingsContributionModel`, local table.
- Produces on `TransactionRepository`:
  - `Future<void> createTransaction(Transaction transaction, {bool onlyIfAbsent = false, List<SavingsContribution> contributions = const []})`
  - `Future<void> updateTransaction(Transaction transaction, {SplitChanges? savings})`
  - `Future<void> deleteTransaction(String transactionId)` — also soft-deletes that transaction's live contributions.
  - `Future<List<SavingsContribution>> getContributions(String transactionId)` — live rows only.
- Produces on `FakeFinance`: `final List<SavingsContribution> contributions`; the fake repository mirrors the four behaviours above (soft delete via `copyWith(deletedAt: DateTime.now())`).

- [ ] **Step 1: Write the failing tests** (real `TransactionRepository` on `AppDatabase.inMemory()` with a `SyncEngine`, as in the savings offline group):
  - `'create writes the income and its contributions, queued in that order'` — queue entities in order: `transactions`, `savings_contributions`, `savings_contributions`; `getContributions('t1')` has both.
  - `'a failure while writing contributions leaves nothing behind'` — `database.db.execute('DROP TABLE savings_contributions')`, then `createTransaction(..., contributions: [c])` throws; `transactions` table has no `t1`; queue empty.
  - `'update applies inserts, updates and deletes'` — after a create with `c1(g1)`, `c2(g2)`, update with `SplitChanges(inserts: [c3(g3)], updates: [c1.copyWith(amount: 6000)], deletes: [c2.id])` → live rows are c1 (6000) and c3; queue ends with `create`, `update`, `delete` for `savings_contributions`.
  - `'deleting the income soft-deletes its contributions and queues them'` — `getContributions('t1')` empty; raw rows have `deleted_at` set; queue has a `delete` per contribution.
- [ ] **Step 2:** run the file → FAIL.
- [ ] **Step 3: Implement.** Local path: one `_db.db.transaction((txn) async {...})` per call, writing with `txn.insert/update` and queue rows with `txn.insert('sync_queue', SyncQueueItem(...).toRow())` (the `createTransfer` pattern), transaction row first; `notifyNewQueueItem()` after the transaction. Contribution local rows are `{...SavingsContributionModel.toJson(c), 'created_at', 'updated_at', 'deleted_at': null, 'sync_status': 'pending'}`; inserts use `ConflictAlgorithm.replace`. Supabase-only path: upsert the transaction, then `upsert` the inserts as a list, `update(updatePayload(...))` per update, `update(tombstone()).inFilter('id', deletes)`; `deleteTransaction` also tombstones `.eq('transaction_id', id).isFilter('deleted_at', null)`.
- [ ] **Step 4:** run the file → PASS; `flutter test test/features/finance test/unit/receipts` → PASS (existing callers unaffected).
- [ ] **Step 5: Commit** — `git commit -m "feat(transactions): write savings contributions with the income"`.

---

### Task 5: Goals load their contributed totals

**Files:**
- Modify: `lib/data/repositories/savings_goal_repository.dart`
- Modify: `test/helpers/fake_finance.dart` (`FakeSavingsGoalRepository`)
- Test: `test/data/repositories/savings_contributions_repository_test.dart`

**Interfaces:**
- Consumes: Task 1 `SavingsSplit.sumByGoal`; Task 2 `contributed_amount` in `SavingsGoalModel.fromJson`; Task 4 `createTransaction(..., contributions:)`.
- Produces: `getSavingsGoals()` returns goals with `contributedAmount` filled; `deleteSavingsGoal(id)` also soft-deletes and queues that goal's live contributions (one local transaction). The fake does the same from `FakeFinance.contributions` and `transactions`.

- [ ] **Step 1: Write the failing tests:**
  - `'goal totals add live contributions only'` — goal g1 saved `100`; income t1 with c(g1,`5000`), income t2 with c(g1,`0.10`) then t2 deleted, and a contribution c(g1,`7`) whose transaction `t9` does not exist locally → `getSavingsGoals().single.contributedAmount == Decimal.parse('5000')`, `totalSaved == 5100`.
  - `'deleting a goal soft-deletes its contributions'` — afterwards `getContributions('t1')` is empty and the queue has a `savings_contributions` `delete`.
- [ ] **Step 2:** run the file → FAIL.
- [ ] **Step 3: Implement.** SQLite: `rawQuery('SELECT c.* FROM savings_contributions c JOIN transactions t ON t.id = c.transaction_id WHERE c.deleted_at IS NULL AND t.deleted_at IS NULL')`, map with `SavingsContributionModel.fromJson`, `SavingsSplit.sumByGoal`, then `SavingsGoalModel.fromJson({...row, 'contributed_amount': sums[id]?.toString()})`. Supabase: live contributions, then `transactions.select('id').inFilter('id', ids).isFilter('deleted_at', null)` to keep only live ones (skip the second query when there are none).
- [ ] **Step 4:** run the file and `test/features/savings` → PASS.
- [ ] **Step 5: Commit** — `git commit -m "feat(savings): goals include contributions from income"`.

---

### Task 6: Controllers

**Files:**
- Modify: `lib/features/transactions/controller/transaction_controller.dart`
- Modify: `lib/features/transactions/controller/transaction_detail_controller.dart`
- Modify: `lib/bindings/feature_bindings.dart` (`TransactionBinding`)
- Modify: translations (the four `validate` messages)
- Test: `test/features/finance/income_savings_test.dart`

**Interfaces:**
- Consumes: Tasks 1, 4, 5.
- Produces on `TransactionController`:
  - constructor named param `SavingsGoalRepository? savingsGoals` (stored as `_savingsGoals`); `TransactionBinding` passes `Get.find<SavingsGoalRepository>()` when registered.
  - `final RxList<SavingsGoal> goals` — loaded in `loadLookups` after the tags block; an `AppException` leaves it empty (same as tags).
  - `saveTransaction({..., List<SavingsPart> savings = const []})` — inside `save.run`: `final List<SavingsPart> wanted = type == TransactionType.income ? savings : const <SavingsPart>[]`; `SavingsSplit.validate(type: type, amount: amount, parts: wanted)` non-null → `throw UnexpectedFailure(message)`; create → `createTransaction(tx, contributions: diff(current: const [], ...).inserts)`; edit → `diff(current: await getContributions(id), ...)` then `updateTransaction(tx, savings: changes)`. `newId` is `Uuid().v4`.
  - `Future<List<SavingsContribution>> contributionsOf(String transactionId)` — repository passthrough for the form.
- Produces on `TransactionDetailController`: `final RxList<SavingsContribution> savings` — filled in `load()` for a live income, cleared otherwise.

- [ ] **Step 1: Write the failing tests** (`FakeFinance` with account, goals g1 'New phone' and g2 'Trip', controller built with `savingsGoals: f.repositories.savingsGoals`):
  - `'saves an income with two goals and goal totals follow'` — save income 50000 with `[(g1,5000),(g2,3000)]` → `true`; `f.contributions` live count 2; `getSavingsGoals()` totals 5000 and 3000.
  - `'refuses savings above the income'` — `[(g1,60000)]` on 50000 → `false`, `save.error.value == "Savings can't be more than the income"`, no transaction stored.
  - `'editing the amount below its savings is refused'` — create 50000 with `[(g1,8000)]`, edit to 5000 with the same savings → `false`, stored amount still 50000.
  - `'switching an income to expense drops its savings'` — edit type to expense, savings `[(g1,8000)]` passed → `true`; no live contributions.
  - `'edit keeps, changes and removes rows'` — `[(g1,5000),(g2,3000)]` → `[(g1,6000)]`: c(g1) keeps its id with 6000; c(g2) soft-deleted.
  - `'deleting the income lowers the goal totals'` — after `deleteTransaction`, g1 total back to 0.
  - `'detail controller lists the income savings'` — `TransactionDetailController(..., 't1').load()` → `savings.length == 2`.
- [ ] **Step 2:** `flutter test test/features/finance/income_savings_test.dart` → FAIL.
- [ ] **Step 3: Implement** per Interfaces; add the four messages to both translation maps.
- [ ] **Step 4:** run the file, `test/features/finance`, `test/unit/receipts` → PASS; `flutter analyze` → no issues.
- [ ] **Step 5: Commit** — `git commit -m "feat(transactions): save income savings from the controller"`.

---

### Task 7: Savings section in the transaction form

**Files:**
- Create: `lib/features/transactions/widgets/savings_split_field.dart`
- Modify: `lib/features/transactions/views/transaction_form_view.dart`
- Modify: translations; `test/core/translations/translation_coverage_test.dart` (`translatedFiles` += the new widget)
- Test: `test/features/finance/income_savings_form_test.dart`

**Interfaces:**
- Consumes: Task 6 `goals`, `contributionsOf`, `saveTransaction(savings:)`; Task 1 `SavingsSplit.validate`, `SavingsPart`.
- Produces: `class SavingsSplitField extends StatefulWidget { const SavingsSplitField({super.key, required TextEditingController amount, required List<SavingsGoal> goals, required List<SavingsPart> initial, required ValueChanged<List<SavingsPart>> onChanged, required VoidCallback onCreateGoal}); }`
  - Rows: `BottomSheetDropdown<String>` (options: goal ids not picked in another row, plus the row's own id; `labelOf` falls back to `'Savings goal'.tr` for an id not in `goals`; validator `'Choose a goal'.tr`) + `AppTextField` (`label: 'Amount'.tr`, `Validators.positiveAmount`) + `IconButton` (tooltip `'Remove'.tr`).
  - No rows: `TextButton.icon` `'Put some in savings'.tr`; with no goals at all, `TextButton` `'Create a savings goal first'.tr` calling `onCreateGoal`.
  - With rows: `TextButton.icon` `'Another goal'.tr` (hidden when every goal is used); footer `'@saved to savings · @left left'.trParams({'saved': AppFormatters.money(total), 'left': AppFormatters.money(amount - total)})`, rebuilt from the `amount` controller via `ListenableBuilder`; a `FormField<void>` whose validator returns `SavingsSplit.validate(...)?.tr` over rows that parse, so the parent `Form.validate()` covers it.
  - `onChanged` gets only rows with a picked goal and a parseable amount.
- Form changes: holds `List<SavingsPart> _savings`; renders `SavingsSplitField` after the account dropdown only when `_type == TransactionType.income`; switching type clears `_savings`; when editing an income, `initState` loads `contributionsOf(existing.id)` into the initial rows (then `setState`); `onCreateGoal` → `Get.toNamed<void>(AppRoutes.savingsGoalForm)`; `_submit` passes `savings: _savings`.

- [ ] **Step 1: Write the failing widget tests** (boot with `pumpApp` from `test/helpers/fakes.dart` like `finance_flow_test.dart`; seed an account and goals g1 'New phone', g2 'Trip'):
  - `'income form puts part of the income into two goals'` — open Income, amount `50000`, category Salary, tap `Put some in savings`, pick New phone `5000`, `Another goal`, pick Trip `3000`; footer shows `₹8,000.00 to savings · ₹42,000.00 left` (match the app's money format); Save → `f.contributions` has 2 live rows.
  - `'savings above the income show the error and do not save'` — one row `60000` on `50000` → `Savings can't be more than the income` visible; `f.transactions` unchanged.
  - `'the section is hidden for an expense'` — Expense form has no `Put some in savings`.
  - `'editing an income preloads its savings rows'` — seeded income with c(g1, 5000) opened from detail → `Edit` shows a row with `New phone` and `5000`.
  - `'a preloaded row whose goal is not loaded shows a fallback label'` — seeded contribution to goal id `gone` not in `f.savingsGoals` → row shows `Savings goal`, no exception (`tester.takeException()` is null).
- [ ] **Step 2:** run the file → FAIL.
- [ ] **Step 3: Implement** the widget and form changes; add the new keys (`'Put some in savings'`, `'Another goal'`, `'Create a savings goal first'`, `'Choose a goal'`, `'@saved to savings · @left left'`; `'Savings goal'` and `'Remove'` already exist) to both maps.
- [ ] **Step 4:** run the file, `test/features/finance`, `test/core/translations` → PASS; `flutter analyze` → no issues.
- [ ] **Step 5: Commit** — `git commit -m "feat(transactions): put part of an income into savings goals from the form"`.

---

### Task 8: Show contributions on goals and the transaction detail

**Files:**
- Modify: `lib/features/savings/views/savings_goal_list_view.dart` (`_GoalCard`)
- Modify: `lib/features/savings/views/savings_goal_form_view.dart` ("Saved so far" helper)
- Modify: `lib/features/transactions/views/transaction_detail_view.dart`
- Modify: translations; `docs/01_PRODUCT_REQUIREMENTS.md`, `docs/05_FINANCIAL_LOGIC.md`, `docs/12_UI_NAVIGATION_MAP.md`
- Test: `test/features/savings/savings_goals_test.dart`, `test/features/finance/income_savings_form_test.dart`

**Interfaces:**
- Consumes: Task 2 `totalSaved`, `contributedAmount`; Task 6 `TransactionDetailController.savings`, `TransactionController.goals`.
- Produces copy: card line `'@amount from income'` (only when `contributedAmount > Decimal.zero`); card amounts use `totalSaved` (`'@spent of @amount'` gets `totalSaved`); goal form `helperText: '+ @amount added from income'` when editing a goal with contributions; detail `_Row('Savings'.tr, '<goal name> <money> · ...')` for an income with savings, goal name from `TransactionController.goals` falling back to `'Savings goal'.tr`.

- [ ] **Step 1: Write the failing tests:**
  - savings test: `'goal card shows the total and the part from income'` — goal saved `250`, contributed `500`, target `1000` → `₹750.00 of ₹1,000.00` and `₹500.00 from income` visible.
  - form test: `'detail shows where the income went'` — seeded income with c(g1,5000), c(g2,3000) → detail shows `New phone ₹5,000.00 · Trip ₹3,000.00`.
- [ ] **Step 2:** run both → FAIL.
- [ ] **Step 3: Implement**; add `'@amount from income'`, `'+ @amount added from income'`, `'Savings'` (if absent) to both maps.
- [ ] **Step 4: Docs:** 01 — scope line for income savings; 05 — `totalSaved` formula and the four validation rules; 12 — form section and detail line.
- [ ] **Step 5:** run both files and `test/core/translations` → PASS.
- [ ] **Step 6: Commit** — `git commit -m "feat(savings): show income contributions on goals and transaction detail"`.

---

### Task 9: Final verification

- [ ] **Step 1:** `flutter analyze` → "No issues found!"
- [ ] **Step 2:** `flutter test` → only the two known `planning_flow_test.dart` recurring tests fail.
- [ ] **Step 3:** remind the user to run `supabase/migrations/20261024090000_savings_contributions.sql` before releasing this build.
