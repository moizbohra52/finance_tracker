# Split Expenses Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user share an expense with friends in a group, see who owes whom, and settle up, while the user's own expense, account and khata stay exact to the paisa.

**Architecture:** Five new synced tables (groups, members, expenses, parts, settlements) are the source of truth. One local SQLite transaction per operation writes the split rows plus the user's derived `transactions` and `contact_transactions` rows (deterministic uuid v5 ids), queued parent-first, like `TransactionRepository.createTransfer`. All money rules live in pure Dart in `domain/services`, exact `Decimal`, paise internally.

**Tech Stack:** Flutter, GetX, sqflite (local, source of the app's reads), Supabase (Postgres + RLS), `decimal`, `uuid` (v5 already used in `budget_calculator.dart`).

**Spec:** `docs/superpowers/specs/2026-10-23-split-expenses-design.md` (revised 2026-10-26). Read it with this plan; the plan names what the spec leaves open.

## Global Constraints

- Money is `Decimal` in Dart, `NUMERIC(18,2)` on the server, TEXT in SQLite. Never `double`, never SQL `SUM`. Amounts have at most 2 decimals.
- Client-generated UUIDs; split rows and derived rows use the deterministic uuid v5 ids from the spec (`const Uuid().v5(Namespace.url.value, '<name>')`, pattern in `lib/domain/services/budget_calculator.dart`). Every write is an upsert/update on its id.
- Soft deletes only (`deleted_at` + `tombstone()` + `SyncOperation.delete` queue item).
- Local database only: `SplitRepository` has no Supabase fallback. With a null database every method throws `const DatabaseFailure()` (`shortcut: production always passes the database, main.dart; revisit if a web build without it ships`).
- Migration file `supabase/migrations/20261024100000_split_expenses.sql`; the user runs migrations by hand. Local `databaseVersion` 4 → 5 via an `if (oldVersion < 5)` step in `AppDatabase.upgrade` plus `_createTables`.
- Every successful write from a controller calls `DataChangeNotifier.markChanged()` so Home, lists and Khata reload.
- A khata entry or transaction with `split_expense_id` / `split_settlement_id` cannot be edited or deleted directly (spec "Guards").
- Every user-visible string is an English key with `.tr`, plus entries in `lib/core/translations/hinglish.dart` ('lakshya' = goal, 'aamdani' = income, existing vocabulary) and `hindi.dart`; each new view file is added to `translatedFiles` in `test/core/translations/translation_coverage_test.dart`.
- Existing files that are `dart format`-clean today (check with `dart format --output=none --set-exit-if-changed <file>`) may be formatted; files that are not are edited by hand only. New files are formatted.
- Commit only the files of the current task (`git add <paths>`), message ends with a blank line and `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- `flutter analyze` stays at "No issues found!"; the whole suite is green.
- Project rules (`CLAUDE.md`): no Supabase queries or accounting math in widgets; GetX controllers hold presentation state only; destructive actions confirm; handle loading, empty, error, offline states; update docs and migration before/with schema changes.

## Review Focus

- An expense edited so the user's role flips (user paid → a friend paid all) must flip the `:balance` row type in place and leave no stale row → test in Task 6.
- A group whose member's contact was deleted on another device (pulled tombstone) must show "Deleted contact", not crash, and its sums stay exact → test in Task 8.
- Saving an expense twice with a member's part removed on the second save must tombstone that part (no duplicate or stale live rows) → test in Task 6.
- A total of `100.005` (three decimals) or paid amounts one paisa off the total must be refused with a message and write nothing → tests in Tasks 1 and 9.
- Blank amount cells count as 0, and an expense where the user's share is 0 (user paid for others) needs no category → tests in Tasks 1 and 9.

---

### Task 0: Bring in the recurring test fix

`main` has two failing recurring tests; their fix sits on branch `fix/recurring-tests-category` (commit `0181aae`). The new work needs a green baseline.

- [ ] **Step 1:** `git merge-base --is-ancestor 0181aae HEAD && echo already-in`. If it prints `already-in`, skip to Step 3.
- [ ] **Step 2:** `git merge --no-ff fix/recurring-tests-category -m "Merge fix/recurring-tests-category"` (local; do not push).
- [ ] **Step 3:** `flutter test test/features/planning/planning_flow_test.dart` → "All tests passed!"

---

### Task 1: Entities, ids, allocation and expense validation

**Files:**
- Create: `lib/domain/entities/split.dart`, `lib/domain/services/split_ids.dart`, `lib/domain/services/split_calculator.dart`
- Test: `test/domain/split_calculator_test.dart`

**Interfaces:**
- Produces in `split.dart`: `enum SplitMode { equal, exact, percent, shares }` (stored as its `name`); immutable classes (all with `id`, `userId`, `createdAt`, `updatedAt`, `DateTime? deletedAt`): `SplitGroup(name)`, `SplitMember(groupId, String? contactId)` with `bool get isMe => contactId == null`, `SplitExpense(groupId, title, Decimal totalAmount, DateTime expenseDate, SplitMode splitMode, String? categoryId, String? accountId, String? note)`, `SplitPart(splitExpenseId, memberId, Decimal paidAmount, Decimal shareAmount, Decimal? shareInput)`, `SplitSettlement(groupId, fromMemberId, toMemberId, Decimal amount, DateTime settledAt, String? accountId, String? note)`.
- Produces `abstract final class SplitIds` (static, all `String`): `member(String groupId, String? contactId)` (name `split-member:<group id>:<contact id | me>`), `part(String expenseId, String memberId)` (`split-part:<expense id>:<member id>`), `expenseShare(String expenseId)` (`split-expense:<id>:share`), `expenseBalance(String expenseId)` (`:balance`), `expenseContact(String expenseId, String contactId)` (`:contact:<contact id>`), `settlementKhata(String settlementId)` (`split-settlement:<id>:khata`), `settlementAccount(String settlementId)` (`:account`).
- Produces `abstract final class SplitCalculator`:
  - `static Map<String, Decimal> allocate(Decimal total, Map<String, Decimal> weights)` — largest remainder method over paise; keys are member ids; ties go by ascending member id; weight 0 → share 0; result sums to `total` exactly.
  - `static String? validateInputs(SplitMode mode, Decimal total, Map<String, Decimal> inputs)` — mode-specific message or null: equal needs at least one input > 0 (`'Tick at least one person'`), exact amounts must add up to `total` (`'The shares must add up to the total'`), percent must add to 100 (`'Percentages must add up to 100'`), shares need a whole number >= 0 each and one > 0 (`'Enter at least one share'`).
  - `static Map<String, Decimal> sharesFor(SplitMode mode, Decimal total, Map<String, Decimal> inputs)` — equal: weight 1 for every input > 0; exact: the inputs; percent and shares: `allocate` with the inputs as weights.
  - `static String? validate({required Decimal total, required Map<String, Decimal> paid, required Map<String, Decimal> shares, required String meId, required String? categoryId, required String? accountId})` — returns the first English message key, in this order: `'Amount must be more than zero'` (total <= 0), `'Amounts can have at most 2 decimals'` (total, any paid or share), `'What was paid must add up to the total'`, `'The shares must add up to the total'`, `'Add at least one friend to this expense'` (no member other than `meId` has paid or share > 0), `'Choose a category'` (user share > 0 and null category), `'Choose an account'` (user paid > 0 or user share > 0, null account). Negative amounts → `'Amount must be more than zero'`.

- [ ] **Step 1: Write the failing tests** in `test/domain/split_calculator_test.dart`:
  - `allocate(100, {a:1,b:1,c:1})` → `{a: 33.34, b: 33.33, c: 33.33}`; `allocate(100, {a:1,b:2})` → a `33.33`, b `66.67`; `allocate(0.05, {a:50,b:50})` → a `0.03`, b `0.02`; weights `{a:0,b:1}` on `10` → a `0`, b `10`; every result sums to the total (loop over a seeded `Random(7)`, 200 cases, 1-6 members, totals 0.01-9999.99).
  - `sharesFor`: equal with inputs `{a:1,b:1,c:0}` on `100` → `{a:50,b:50,c:0}`; percent `{a:50,b:30,c:20}` on `100` → `{50,30,20}`; exact returns inputs.
  - `validateInputs`: one case per message above (equal all zero, exact off by 0.01, percent 99, shares all zero).
  - `validate`: one case per message in the stated order, including total `100.005` → `'Amounts can have at most 2 decimals'`, paid sum off by `0.01` → `'What was paid must add up to the total'`, user paid for others (share 0, paid 500, friend share) with `categoryId: null` and an account → `null` (no category needed), a blank/absent member in the maps counts as 0 (missing key is read as zero), and the happy case from the spec (total 1200, me paid 800, Rahul 400, four × 300, category and account set) → `null`.
  - `SplitIds`: same inputs give the same id; different inputs differ; `member('g', null)` ≠ `member('g', 'c')`.
- [ ] **Step 2:** `flutter test test/domain/split_calculator_test.dart` → FAIL (files missing).
- [ ] **Step 3: Implement** entities (plain classes; `copyWith` only where a later task needs it), `SplitIds`, and the calculator. Do the paise arithmetic on integers (`(amount * Decimal.fromInt(100)).toBigInt()`); an amount has at most 2 decimals iff `amount * 100` is an integer.
- [ ] **Step 4:** run the file → PASS; `flutter analyze` → no issues.
- [ ] **Step 5: Commit** — `git commit -m "feat(split): entities, ids, allocation and expense validation"`.

---

### Task 2: The user's net with each friend and the derived rows

**Files:**
- Modify: `lib/domain/services/split_calculator.dart`, `docs/05_FINANCIAL_LOGIC.md`
- Test: `test/domain/split_calculator_test.dart`

**Interfaces:**
- Consumes: Task 1 `SplitCalculator`, `SplitIds`.
- Produces: `static Map<String, Decimal> friendNets({required Decimal total, required String meId, required Map<String, Decimal> paid, required Map<String, Decimal> shares})` — keys are every member id except `meId`; value `n_f = (share_f × paid_me − share_me × paid_f) / T`, each rounded to paise with the largest remainder method so the values sum to exactly `paid_me − share_me`; `n_f > 0` means the friend owes the user.
- Produces: `class SplitUserRows { final Decimal expenseShare; final Decimal balanceAmount; final bool balanceIsPaidForOthers; final Map<String, Decimal> contactNets; }` and `static SplitUserRows userRows({required Decimal total, required String meId, required Map<String, Decimal> paid, required Map<String, Decimal> shares})` — `expenseShare = share_me`; `balanceAmount = |paid_me − share_me|`; `balanceIsPaidForOthers = paid_me > share_me` (a `payment_made`; otherwise a `payment_received`; when equal `balanceAmount` is 0 and no row is written); `contactNets = friendNets(...)`.

- [ ] **Step 1: Write the failing tests:**
  - Spec example 1: total 1200, paid `{me:800, rahul:400, amit:0, neha:0}`, shares all 300 → `friendNets` = `{amit:200, neha:200, rahul:100}`; `userRows`: `expenseShare 300`, `balanceAmount 500`, `balanceIsPaidForOthers true`.
  - Spec example 2: Rahul paid all 1200, me paid 0, shares 300 each → nets `{amit:0, neha:0, rahul:-300}`; `expenseShare 300`, `balanceAmount 300`, `balanceIsPaidForOthers false`.
  - User paid but share 0 (me paid 600, share 0; Amit share 600) → `expenseShare 0`, `balanceAmount 600`, `balanceIsPaidForOthers true`, `amit: 600`. User not involved (paid 0, share 0, Amit paid 100, Neha share 100) → `expenseShare 0`, `balanceAmount 0`, every net `0`.
  - Rounding: total `100`, three equal shares, me paid 100 → `friendNets` for the two friends sum with `share_me` to exactly `paid_me − share_me` = `100 − 33.34` (assert the sum equality, not the split).
  - Seeded loop (`Random(11)`, 300 cases: random mode, 2-5 members, random paid split) asserting for every case (a) `Σ contactNets == paid_me − share_me` and (b) the account movement `−expenseShare − (paidForOthers ? balanceAmount : −balanceAmount)` equals `−paid_me`, both exactly.
- [ ] **Step 2:** run → FAIL. **Step 3: Implement** both functions (largest remainder over the signed paise values; ties by ascending member id). **Step 4:** run → PASS.
- [ ] **Step 5: Docs:** `docs/05_FINANCIAL_LOGIC.md` gets a "Split expenses" section with allocation, validation, the net formula, the derived-row table and the two checked examples from the spec (copy their numbers).
- [ ] **Step 6: Commit** — `git commit -m "feat(split): the user's net with each friend and derived rows"`.

---

### Task 3: Group balances and settlements

**Files:**
- Create: `lib/domain/services/split_balances.dart`
- Modify: `docs/05_FINANCIAL_LOGIC.md`
- Test: `test/domain/split_balances_test.dart`

**Interfaces:**
- Consumes: Tasks 1-2 entities and `SplitCalculator.friendNets`.
- Produces: `class PairBalance { final String debtorMemberId; final String creditorMemberId; final Decimal amount; }` (amount > 0: debtor owes creditor) and `class GroupBalances { final Map<String, Decimal> memberNets; final List<PairBalance> pairs; Decimal netOf(String memberId); }`; `abstract final class SplitBalances { static GroupBalances compute({required String meId, required List<SplitExpense> expenses, required Map<String, List<SplitPart>> partsByExpense, required List<SplitSettlement> settlements}); }` (inputs are live rows only).
  - `memberNets[m] = Σ(paid − share) + settlements paid by m − settlements received by m` (a settlement `from → to` of `x` adds `x` to `from` and subtracts `x` from `to`). They add to zero.
  - Pair user↔friend: `Σ n_f` from `friendNets` per expense, then `− settlements friend→user + settlements user→friend`. Pair friend↔friend: `Σ (share_i × paid_j − share_j × paid_i) / T` over expenses, minus settlements `i→j`, plus `j→i`, rounded to paise once. Pairs with amount 0 are omitted; a negative result is stored with debtor and creditor swapped; the list is sorted by amount descending then debtor id.

- [ ] **Step 1: Write the failing tests** (`meId` `me`, members `amit`, `neha`, `rahul`; the ₹1200 dinner of the spec): `memberNets` = `{me:500, amit:-300, neha:-300, rahul:100}` and sum 0; `pairs` (debtor→creditor) are exactly `[amit→me 200, neha→me 200, amit→rahul 100, neha→rahul 100, rahul→me 100]` (sorted by amount descending, then debtor id); a settlement amit→me 200 removes `amit→me`; amit→me 250 flips it to `me→amit 50`; a settlement between two friends (`amit→rahul 100`) removes only that pair and moves `memberNets` accordingly; an empty group gives empty maps.
- [ ] **Step 2:** run → FAIL. **Step 3: Implement.** **Step 4:** run → PASS.
- [ ] **Step 5: Docs:** `docs/05_FINANCIAL_LOGIC.md` — balances, pairwise rules, settlement direction flip.
- [ ] **Step 6: Commit** — `git commit -m "feat(split): group balances and settlements"`.

---

### Task 4: Storage — migration, local tables, link columns, models, sync and backup

**Files:**
- Create: `supabase/migrations/20261024100000_split_expenses.sql`, `lib/data/models/split.dart`
- Modify: `lib/data/datasources/local/app_database.dart`, `lib/core/services/sync_engine.dart`, `lib/core/services/backup_service.dart`, `lib/features/backup/widgets/backup_preview_dialog.dart`, `lib/core/widgets/sync_status_sheet.dart`, `lib/domain/entities/transaction.dart`, `lib/data/models/transaction.dart`, `lib/domain/entities/contact.dart` (`ContactTransaction`), `lib/data/models/contact_transaction.dart`, `supabase/checks/cross_user_isolation.sql`, `docs/03_DATABASE_SCHEMA.md`, `docs/04_SECURITY_RLS.md`, `docs/07_OFFLINE_SYNC.md`, translations
- Test: `test/data/datasources/app_database_test.dart`, `test/data/models/split_models_test.dart`, `test/data/models/split_link_columns_test.dart`, `test/core/services/sync_engine_test.dart`

**Interfaces:**
- Consumes: Task 1 entities.
- Produces: `abstract final class SplitGroupModel|SplitMemberModel|SplitExpenseModel|SplitPartModel|SplitSettlementModel` in `lib/data/models/split.dart`, each `static <Entity> fromJson(Map<String, dynamic>)` and `static Map<String, dynamic> toJson(<Entity>)` (no timestamps in `toJson`, amounts as strings, `fromJson` accepts num or string; `SplitMode` by `name`; `contact_id` null for the user's own member; dates `expense_date`/`settled_at` ISO strings).
- Produces: tables `split_groups`, `split_group_members`, `split_expenses`, `split_expense_parts`, `split_settlements` (server and local, columns as in the spec "Schema"; local adds `sync_status TEXT NOT NULL DEFAULT 'synced'`, money as TEXT, indexes on every `*_id` reference), and nullable `split_expense_id` / `split_settlement_id` on `transactions` and `contact_transactions`, carried by `Transaction`/`TransactionModel` and `ContactTransaction`/`ContactTransactionModel` (constructor params, `fromJson`, `toJson`, and `Transaction.copyWith`).

- [ ] **Step 1: Write the failing tests:**
  - `app_database_test.dart`: `'upgrading a version 4 file adds the split tables and link columns'` — open a v4 file (existing upgrade-test style, `singleInstance: false`) containing `transactions` and `contact_transactions` tables, `AppDatabase.upgrade(old, 4, AppDatabase.databaseVersion)`; `PRAGMA table_info` shows the five tables and `split_expense_id` + `split_settlement_id` on both existing tables; existing rows are kept. A fresh `AppDatabase.inMemory()` has the same.
  - `split_models_test.dart`: a round trip per model; `amount` as num and as string; `SplitMember` with `contact_id: null`; `toJson` has no `created_at`.
  - `test/core/services/sync_engine_test.dart`, in the group `'local data belongs to one user'`: `'the split tables are cleared for another user'` — insert one row into each of `split_groups`, `split_group_members`, `split_expenses`, `split_expense_parts`, `split_settlements` (minimum NOT NULL columns) for `user-a`, `claimLocalData('user-a')`, then `claimLocalData('user-b')` → every one of the five tables is empty (this pins `clearAllUserData`).
  - `split_link_columns_test.dart`: `TransactionModel.fromJson` / `toJson` round-trip `split_expense_id`/`split_settlement_id` (null and set); same for `ContactTransactionModel`; `Transaction.copyWith` keeps them.
- [ ] **Step 2:** run the four files → FAIL.
- [ ] **Step 3: Implement** the local part: `databaseVersion = 5`; `_createSplitTables(DatabaseExecutor db)` called from `_createTables` and from `upgrade`'s `if (oldVersion < 5)`, which also runs `ALTER TABLE transactions ADD COLUMN split_expense_id TEXT` (and `split_settlement_id`, and the same two on `contact_transactions`); the `CREATE TABLE` statements for `transactions` and `contact_transactions` in `_createTables` get the columns too. Add the five tables to `clearAllUserData`, to `SyncEngine.downloadDelta`'s `syncableTables` (after `savings_contributions`), to `BackupService.supportedTables` and `uploadTables`, and the label/icon cases in `backup_preview_dialog.dart` and `sync_status_sheet.dart` (new translation keys `'Split groups'`, `'Group members'`, `'Split expenses'`, `'Expense parts'`, `'Settlements'` and singular entity names, both maps). **Restore order matters for the server's foreign keys:** in `BackupService`'s `insertOrder` the five split tables go after `contacts` and before `transactions`, in the order groups, members, expenses, parts, settlements.
- [ ] **Step 4: Migration** `supabase/migrations/20261024100000_split_expenses.sql`, following the spec's Schema section and `20261023100000_savings_goals.sql` / `20261024090000_savings_contributions.sql`: the five tables (columns, `check` constraints: names/titles not blank, `total_amount > 0`, `split_mode in ('equal','exact','percent','shares')`, `paid_amount >= 0`, `share_amount >= 0`, settlement `amount > 0` and `from_member_id <> to_member_id`); `unique (user_id, id)` on each; composite foreign keys for accounts, contacts, group, member, expense and settlement references; `category_id` a plain foreign key to `categories (id)` with `private.can_use_category(category_id)` in the insert/update policies of `split_expenses`; an index per foreign key (partial `where ... is not null` for nullable ones); `set_updated_at` triggers; RLS enabled, revoke/grant, four owner-only policies each; `alter table public.transactions add column split_expense_id uuid, add column split_settlement_id uuid` with composite foreign keys `(user_id, split_expense_id)` / `(user_id, split_settlement_id)` to the new tables and partial indexes; the same on `public.contact_transactions`. Header comment: apply before shipping the app version that syncs it.
- [ ] **Step 5: Isolation check:** extend `supabase/checks/cross_user_isolation.sql` with the five tables in its existing style (read the file first; a case per table showing user B cannot read, insert into, or reference user A's rows).
- [ ] **Step 6: Docs:** 03 (five tables, the two link columns, indexes, migration #15 with the plain statement that it must be applied before shipping and what a missing migration does: uploads for the new tables fail and retry, the pull error ends every sync in the error state), 04 (policies, isolation check coverage), 07 (table order, parents-first queue, one local transaction per operation, restore order).
- [ ] **Step 7:** run the four test files, `flutter test test/data test/core test/features/sync`, `flutter analyze` → pass.
- [ ] **Step 8: Commit** — `git commit -m "feat(split): split tables, link columns, sync and backup"`.

---

### Task 5: SplitRepository — groups, members, links; wiring and fake

**Files:**
- Create: `lib/data/repositories/split_repository.dart`
- Modify: `lib/data/repositories/app_repositories.dart`, `lib/bindings/initial_binding.dart`, `test/helpers/fake_finance.dart`
- Test: `test/data/repositories/split_repository_test.dart`

**Interfaces:**
- Consumes: Task 1 entities/`SplitIds`, Task 4 models and tables.
- Produces `class SplitRepository { SplitRepository(AppDatabase? database, {SyncEngine? syncEngine}); ... }` with:
  - `Future<List<SplitGroupSummary>> getGroups()` — live groups, newest first; `class SplitGroupSummary { final SplitGroup group; final int memberCount /* live members incl. the user */; final Decimal userNet; }` (the user's net from `SplitBalances`).
  - `Future<SplitGroup> getGroup(String groupId)`; `Future<List<SplitMember>> getMembers(String groupId)` — live, the user's own member first.
  - `Future<void> saveGroup({required String groupId, required String name, required List<String> friendContactIds})` — one local transaction: upserts the group, the user's member (`SplitIds.member(groupId, null)`), a member per friend (`SplitIds.member(groupId, contactId)`, reviving a tombstoned one), tombstones friends no longer listed. Throws `UnexpectedFailure('Give the group a name')` for a blank name, `UnexpectedFailure('Add at least one friend')` for an empty list, and `UnexpectedFailure("This friend is in an expense or settlement and can't be removed")` when a removed friend's member has a live part or settlement (nothing is written then). Queue order: group, members.
  - `Future<String?> groupNameBlockingContactDelete(String contactId)` — the name of a live group that has a live member for that contact, else null.
  - `class SplitLink { final String id; final String groupId; final String groupName; final bool isSettlement; }` and `Future<Map<String, SplitLink>> getLinks({Iterable<String> expenseIds = const <String>[], Iterable<String> settlementIds = const <String>[]})` keyed by expense/settlement id (rows whose group is deleted are omitted).
- Produces: `AppRepositories` gets `final SplitRepository split` (required constructor param; `.supabase` builds `SplitRepository(database, syncEngine: syncEngine)`); `InitialBinding` registers it permanently like `SavingsGoalRepository`.
- Produces `FakeSplitRepository implements SplitRepository` in `test/helpers/fake_finance.dart` backed by new `FakeFinance` lists (`splitGroups`, `splitMembers`, `splitExpenses`, `splitParts`, `splitSettlements`): same public methods, in-memory, using `SplitBalances` for nets; derived `transactions`/`contactTransactions` rows are NOT produced by the fake (the real repository's tests cover them). each method first calls `_f.throwPending()` like the other fakes; `FakeFinance` passes it as `split:`.

- [ ] **Step 1: Write the failing tests** (real repository on `AppDatabase.inMemory()` like `transfer_repository_test.dart`): `saveGroup` writes group + me + friends and queues them in that order; saving again with the same ids adds no extra live rows (retry); removing a friend with no parts tombstones that member and queues a delete; removing a friend who has a live part (insert a part row directly with `database.db.insert`) throws and writes nothing; re-adding a removed friend revives the same member id; blank name and empty friends are refused; `groupNameBlockingContactDelete` returns the group name for a member contact and null after the group is tombstoned; `getGroups` returns `memberCount` and `userNet` (0 for an empty group); `getLinks` resolves an expense id and a settlement id (rows inserted directly) and omits one whose group is deleted; with a null database every method throws `DatabaseFailure`.
- [ ] **Step 2:** run → FAIL. **Step 3: Implement** the repository (queue items via `txn.insert('sync_queue', SyncQueueItem(...).toRow())` inside `_db.db.transaction`, then `_syncEngine?.notifyNewQueueItem()`), the wiring and the fake.
- [ ] **Step 4:** run the file and `flutter test test/features test/data` → pass; `flutter analyze` → no issues.
- [ ] **Step 5: Commit** — `git commit -m "feat(split): split repository groups, members and links"`.

---

### Task 6: SplitRepository — expenses and their derived rows

**Files:**
- Modify: `lib/data/repositories/split_repository.dart`, `test/helpers/fake_finance.dart`
- Test: `test/data/repositories/split_repository_test.dart`

**Interfaces:**
- Consumes: Tasks 1-2 (`SplitCalculator.validate/friendNets/userRows`, `SplitIds`), Task 5.
- Produces: `class SplitExpenseDetail { final SplitExpense expense; final List<SplitPart> parts; }`; `Future<SplitExpenseDetail> getExpense(String expenseId)`; `Future<void> saveExpense({required SplitExpense expense, required List<SplitPart> parts})`; `Future<void> deleteExpense(String expenseId)`. The fake gains the same three methods (store/replace by id, soft-delete).
- `saveExpense` rules: re-runs `SplitCalculator.validate` (member ids → paid/share maps, the user's member found by `isMe`) and throws `UnexpectedFailure(message)` on a message; then one local transaction in this queue order: expense, parts, derived `transactions`, derived `contact_transactions`. It upserts (id from the caller; parts use `SplitIds.part`), tombstones any previous part of this expense that is not in `parts`, then the derived rows from `SplitCalculator.userRows`:
  - `share_me > 0` → `transactions` `expense` of `expenseShare`, with the expense's category and account, id `SplitIds.expenseShare`; else tombstone that id if it exists.
  - `balanceAmount > 0` → `transactions` `payment_made` (`balanceIsPaidForOthers`) or `payment_received` of `balanceAmount`, `contactId` null, expense account, id `SplitIds.expenseBalance`; if the id exists with the other type it is updated in place (same id, new type); `balanceAmount == 0` → tombstone it.
  - per friend member with a contact: `n_f > 0` → `contact_transactions` `credit` n_f, `n_f < 0` → `debit` −n_f, id `SplitIds.expenseContact(expenseId, contactId)`; `n_f == 0` → tombstone that id if it exists. A friend removed from the expense also gets its row tombstoned.
  - Every derived row carries `split_expense_id`, date `expense_date`, and text built with `.tr` at save time: `transactions.description` — `'Split: paid for others · @group'` (payment_made) / `'Split: others paid your share · @group'` (payment_received) and the `:share` expense row's `description` is the expense `title` (decision: the spec leaves it open); khata `note` — `'@group · @title'` (`trParams` with `group` and `title`). If the user neither paid nor shares, no derived rows are written.
  - `deleteExpense` tombstones the expense, its parts and every derived row (live `transactions`/`contact_transactions` with that `split_expense_id`) in one local transaction; each affected row gets a `SyncOperation.delete` queue item with `tombstone()`.

- [ ] **Step 1: Write the failing tests** (real repository; seed a group with members me/Amit/Neha/Rahul via `saveGroup`, plus matching rows in `contacts` and an `accounts` row if the tables need them):
  - Spec example 1 (₹1200, me 800, Rahul 400, four × 300): after `saveExpense`, live `transactions` for the expense are `expense 300` and `payment_made 500`, the account movement is `-800`, khata nets `credit 200` (Amit), `credit 200` (Neha), `credit 100` (Rahul); the queue entities in order are `split_expenses`, then 4 `split_expense_parts`, then `transactions` ×2, then `contact_transactions` ×3.
  - Spec example 2 (Rahul paid all): `expense 300` + `payment_received 300` (account net 0), khata Rahul `debit 300`, Amit and Neha none.
  - A retry with the same ids adds no new queue-visible rows beyond update items and no duplicate live rows (count live rows before/after).
  - **Role flip:** edit example 1 to example 2 → the `:balance` row keeps its id and changes type from `payment_made` to `payment_received` with amount 300; no stale live derived row remains; Rahul's khata row changes from `credit 100` to `debit 300` (same id).
  - **Part removal:** save with four parts, save again with Neha's part removed and Amit/Rahul only → Neha's part row and her khata row are soft-deleted; live rows per (expense, member) are at most one.
  - User paid for others with share 0 → no `:share` expense row, no category needed.
  - Invalid input (paid sum one paisa off) throws `UnexpectedFailure` and writes nothing (queue empty, tables unchanged); a failure inside the database transaction (drop `split_expense_parts` first) leaves nothing behind.
  - `deleteExpense` tombstones expense, parts and all derived rows and queues a delete per row; the account balance via `FinanceSummaryCalculator.accountBalances` and the khata balance via `Contact.getCurrentBalance` return to their values before the expense.
- [ ] **Step 2:** run → FAIL. **Step 3: Implement.** **Step 4:** run → PASS; `flutter analyze` → no issues.
- [ ] **Step 5: Commit** — `git commit -m "feat(split): save and delete split expenses with derived rows"`.

---

### Task 7: SplitRepository — settlements, group delete and group reads

**Files:**
- Modify: `lib/data/repositories/split_repository.dart`, `test/helpers/fake_finance.dart`
- Test: `test/data/repositories/split_repository_test.dart`

**Interfaces:**
- Consumes: Tasks 3, 5, 6.
- Produces on `SplitRepository` (and the fake):
  - `Future<SplitSettlement> getSettlement(String settlementId)`; `Future<void> saveSettlement(SplitSettlement settlement)`; `Future<void> deleteSettlement(String settlementId)`.
  - `Future<void> deleteGroup(String groupId)`.
  - `class SplitGroupDetail { final SplitGroup group; final List<SplitMember> members; final GroupBalances balances; final Decimal totalSpent; final Decimal userShareTotal; }` and `Future<SplitGroupDetail> getGroupDetail(String groupId)`.
  - `sealed class SplitActivityItem { DateTime get date; }` with `SplitActivityExpense(SplitExpense expense, SplitPart? userPart)` and `SplitActivitySettlement(SplitSettlement settlement)`; `Future<List<SplitActivityItem>> getActivity(String groupId, {int limit = 50, int offset = 0})` — expenses and settlements merged, newest first (ties by id).
  - `Future<({int expenses, int khataEntries})> getGroupDeleteImpact(String groupId)` — live expenses, and live derived `contact_transactions` + `transactions` rows linked to the group's expenses/settlements.
- `saveSettlement` writes (one local transaction, settlement first): when the user's member is a party and the other party is a friend with a contact: `contact_transactions` `payment_received` (friend → user) or `payment_made` (user → friend), id `SplitIds.settlementKhata`, `note` built with `.tr` as `'Settlement · @group'` (decision: the spec leaves the text open; the same text is the `description` of the `:account` row); and, only when `accountId != null`, `transactions` `payment_received` / `payment_made` with the friend as `contactId`, id `SplitIds.settlementAccount`; clearing the account on an edit tombstones that row. Rows carry `split_settlement_id` and date `settled_at`. A settlement between two friends writes no derived rows; `accountId` for such a settlement is refused (`UnexpectedFailure('Only a settlement with you can use an account')`). `deleteSettlement` / `deleteGroup` tombstone everything they own (group: expenses, parts, derived rows, settlements, members, the group) in one transaction.

- [ ] **Step 1: Write the failing tests:** a friend→user settlement of 200 writes `contact_transactions` `payment_received 200` and, with an account, `transactions` `payment_received 200` with the friend as contact; user→friend writes the `payment_made` pair; friend↔friend writes nothing and refuses an account; editing to clear the account tombstones the `:account` row; after the spec dinner, settling Amit→me 200 removes `amit→me` from `getGroupDetail(...).balances.pairs` and the khata balance for Amit returns to 0; overpaying 250 flips to `me→amit 50`; `getGroupDetail` totals (`totalSpent` 1200, `userShareTotal` 300, `balances.netOf(meId)` 500); `getActivity` returns expenses and settlements newest first and pages 50 at a time (insert 120 expenses; pages of 50, 50, 20); `getGroupDeleteImpact` counts; `deleteGroup` tombstones every row and the account/khata balances return to their pre-group values; `deleteSettlement` tombstones its rows.
- [ ] **Step 2:** run → FAIL. **Step 3: Implement** (repository and fake). **Step 4:** run → PASS; `flutter analyze` → no issues.
- [ ] **Step 5: Commit** — `git commit -m "feat(split): settlements, group delete and group reads"`.

---

### Task 8: Controllers — group list, group form and group detail

**Files:**
- Create: `lib/features/split/controllers/split_group_controller.dart`, `lib/features/split/controllers/split_group_detail_controller.dart`
- Test: `test/features/split/split_group_controllers_test.dart`

**Interfaces:**
- Consumes: Tasks 5 and 7 repository methods; `ContactRepository.getContacts()`; `DataChangeNotifier`; `SubmitState`; `routeIdArgument()` tagging as in `feature_bindings.dart`.
- Produces `SplitGroupController(SplitRepository, ContactRepository, DataChangeNotifier)`: `RxList<SplitGroupSummary> groups`, `RxBool isLoading`, `RxnString error`, `RxList<Contact> contacts`, `SubmitState save`, `SubmitState deletion`; `Future<void> load({bool silent = false})` (reloads on the notifier like other controllers, worker disposed in `onClose`); `String contactName(String? contactId)` (the contact's name, `'You'.tr` for null, `'Deleted contact'.tr` when the contact is missing or deleted); `Future<bool> saveGroup({required String groupId, required String name, required List<String> friendContactIds})`; `Future<bool> deleteGroup(String groupId)`; `Future<({int expenses, int khataEntries})> deleteImpact(String groupId)`; `static String newId()`.
- Produces `SplitGroupDetailController(SplitRepository, ContactRepository, DataChangeNotifier, String groupId)`: `Rxn<SplitGroupDetail> detail`, `RxList<SplitActivityItem> activity`, `RxBool isLoading`, `RxBool isLoadingMore`, `RxBool hasMore`, `RxnString error`, `RxList<Contact> contacts`; `Future<void> load({bool silent = false})`, `Future<void> loadMore()` (pages of 50), `String memberName(SplitMember m)` and `String memberNameById(String memberId)` (same naming rules as `contactName`); `Decimal outstanding(String fromMemberId, String toMemberId)` (from the balances: how much `from` owes `to`, 0 if none); `Future<bool> deleteGroup()`.

- [ ] **Step 1: Write the failing tests** (`FakeFinance` with contacts Amit/Neha/Rahul and a saved group; controllers built directly like `savings_goals_test.dart`): list loads groups and shows `userNet`; `saveGroup` with a name and two friends creates the group and reloads; a blank name shows the repository's message in `save.error`; **a member whose contact is soft-deleted shows `'Deleted contact'`** in `memberName` and the nets are unchanged; `deleteImpact` returns the counts and `deleteGroup` removes the group; detail loads header numbers and the first 50 activity items, `loadMore` appends the next page and sets `hasMore` false at the end; `outstanding` returns 200 for amit→me after the spec dinner and 0 for the reverse; a failed load sets `error` (set `f.nextError = const NetworkFailure()`).
- [ ] **Step 2:** run → FAIL. **Step 3: Implement.** **Step 4:** run → PASS; `flutter analyze` → no issues.
- [ ] **Step 5: Commit** — `git commit -m "feat(split): group list and detail controllers"`.

---

### Task 9: Controllers — expense form and settlement form

**Files:**
- Create: `lib/features/split/controllers/split_expense_controller.dart`, `lib/features/split/controllers/split_settlement_controller.dart`
- Test: `test/features/split/split_form_controllers_test.dart`

**Interfaces:**
- Consumes: Tasks 1-2 calculator, Task 6-7 repository, `AccountRepository`, `CategoryRepository`, `ContactRepository`.
- Produces `SplitExpenseController(SplitRepository, AccountRepository, CategoryRepository, ContactRepository, DataChangeNotifier)` holding the form's draft state: `RxList<SplitMember> members`, `Rx<SplitMode> mode`, per-member `RxMap<String, String> paidText` and `RxMap<String, String> inputText` (the typed values; a blank string counts as 0), `RxSet<String> ticked` (equal mode), `RxString totalText`, `RxnString categoryId`, `RxnString accountId`, `RxBool multiplePayers`, `RxString payerId` (single payer), `SubmitState save`, `SubmitState deletion`; computed (no widget math): `Decimal? get total`, `Map<String, Decimal> get paid`, `Map<String, Decimal> get shares`, `String? get error` (the first message from `SplitCalculator.validateInputs` then `validate`, null while the form is incomplete or valid), `Decimal get paidLeft`, `Decimal get sharesLeft`, `({Decimal yourShare, Decimal youGet})? get preview` (`yourShare` and `userRows.balanceAmount` signed: positive = the user gets); `Future<void> start({required String groupId, SplitExpenseDetail? existing})` (loads members, accounts, categories, prefilled from `existing`; the account and category default to the last used on a saved split, else null); `Future<bool> saveExpense({required String id, required String title, required DateTime date, required String? note})`; `Future<bool> deleteExpense(String id)`.
- Produces `SplitSettlementController(SplitRepository, AccountRepository, ContactRepository, DataChangeNotifier)`: `Future<void> start({required String groupId, SplitSettlement? existing, String? fromMemberId, String? toMemberId})` (prefills the outstanding amount from the group's balances; `members`, `accounts`), `RxnString fromId`, `RxnString toId`, `RxString amountText`, `RxnString accountId`, `bool get userIsParty`, `SubmitState save` and `SubmitState deletion`, `Future<bool> saveSettlement({required String id, required DateTime date, required String? note})`, `Future<bool> deleteSettlement(String id)`; `from == to` and amount <= 0 are refused with `'Choose two different people'` / `'Amount must be more than zero'`; `accountId` is cleared when the user is not a party.

- [ ] **Step 1: Write the failing tests** (`FakeFinance`; spec values): equal split of 1200 among four, me paid 800 and Rahul 400 (`multiplePayers`) → `error` null, `preview` = `(yourShare 300, youGet 500)`, `saveExpense` stores an expense with 4 parts; `paidLeft` shows 400 after typing 800 only; **3 decimals (`100.005`) → `error` is `'Amounts can have at most 2 decimals'` and `saveExpense` returns false with nothing stored**; **paid sum one paisa off → `'What was paid must add up to the total'`**; **blank paid/share cells count as 0** (only Rahul's paid cell typed with `1200`, others blank → accepted); user paid for others (single payer me, ticked = Amit and Neha only) → no category required (`error` null with `categoryId` null); percent mode with 50/30/20 and mode switch keeps the typed amounts; shares mode `1:2`; editing an existing expense prefills `mode`, inputs (from `share_input`) and paid cells; settlement: prefilled outstanding 200 for amit→me, overpay allowed, `from == to` refused, account cleared for a friend↔friend settlement.
- [ ] **Step 2:** run → FAIL. **Step 3: Implement.** **Step 4:** run → PASS; `flutter analyze` → no issues.
- [ ] **Step 5: Commit** — `git commit -m "feat(split): expense and settlement form controllers"`.

---

### Task 10: Screens — groups list, group form, member picker, entry point, routes

**Files:**
- Create: `lib/features/split/views/split_group_list_view.dart`, `lib/features/split/views/split_group_form_view.dart`, `lib/features/split/widgets/split_member_picker_sheet.dart`
- Modify: `lib/routes/app_routes.dart`, `lib/routes/app_pages.dart`, `lib/bindings/feature_bindings.dart`, `lib/bindings/user_scope.dart`, `lib/features/contacts/views/contact_list_view.dart` (Khata app bar action), `docs/12_UI_NAVIGATION_MAP.md`, translations, `test/core/translations/translation_coverage_test.dart`
- Test: `test/features/split/split_group_views_test.dart`

**Interfaces:**
- Consumes: Task 8 `SplitGroupController`.
- Produces routes `AppRoutes.splitGroups = '/split-groups'` and `AppRoutes.splitGroupForm = '/split-group-form'` (argument: `SplitGroupSummary` for edit), pages with `AuthGuard` and `SplitGroupBinding` (puts `SplitGroupController`; `user_scope.dart` removes it on sign-out). Screens use the existing widgets (`AppAppBar`, `AppCard`, `SkeletonList`, `EmptyState`, `LoadFailureView`, `AppButton`, `AppTextField`, `confirmDestructive`, `AppSnackbar`).
- Produces `Future<List<String>?> pickSplitMembers({required List<String> selectedContactIds})` — a bottom sheet with checkboxes over `ContactController`'s contacts (multi-select), a "New contact" action opening `AppRoutes.contactForm` (the contact form already offers "Pick from Phone Contacts") and reloading the list on return; returns the chosen contact ids (null on dismiss). The shared `pickContact()` is left untouched.
- Screens: **list** — group name, member count, net text (`'You get @amount'`, `'You owe @amount'`, `'Settled'`), FAB "New group", empty state "No groups yet — make one for a trip, flatmates or office lunch", error with retry; tapping a row opens `AppRoutes.splitGroupDetail` (Task 11 registers it; until then the tap target is wired in Task 11). **Form** — name, member chips with remove, "Add friends" opens the picker, Save, and for edit a Delete button with the dialog "This deletes @expenses expenses and @entries khata entries.".

- [ ] **Step 1: Write the failing widget tests** (`pumpApp` with `FakeFinance`, as `finance_flow_test.dart`): empty state with the exact text; a seeded group shows its name, "3 members" style count and `You get ₹500.00`; creating a group (name, add two contacts through the fake-backed picker, Save) stores it and returns to the list; a blank name shows the error; the Khata app bar has a Groups action that opens the list; edit shows the delete dialog with the counts and deletes after confirm; a load failure shows retry.
- [ ] **Step 2:** run → FAIL. **Step 3: Implement** (views, picker sheet, routes/binding/user scope, app bar action, translations in both maps, `translatedFiles` entries). **Step 4:** run → PASS; `flutter test test/core/translations test/features` → pass; `flutter analyze` → no issues.
- [ ] **Step 5: Docs:** `docs/12_UI_NAVIGATION_MAP.md` rows for `/split-groups`, `/split-group-form`, and the Khata app bar entry.
- [ ] **Step 6: Commit** — `git commit -m "feat(split): groups list and group form screens"`.

---

### Task 11: Screens — group detail and settlement form

**Files:**
- Create: `lib/features/split/views/split_group_detail_view.dart`, `lib/features/split/views/split_settlement_form_view.dart`
- Modify: `lib/routes/app_routes.dart`, `lib/routes/app_pages.dart`, `lib/bindings/feature_bindings.dart`, `lib/features/split/views/split_group_list_view.dart` (row tap), `docs/12_UI_NAVIGATION_MAP.md`, translations, `test/core/translations/translation_coverage_test.dart`
- Test: `test/features/split/split_group_detail_test.dart`

**Interfaces:**
- Consumes: Task 8 `SplitGroupDetailController` (tagged per group via `routeIdArgument()`), Task 9 `SplitSettlementController`.
- Produces routes `AppRoutes.splitGroupDetail = '/split-group-detail'` (argument: the group id String) and `AppRoutes.splitSettlementForm = '/split-settlement-form'` (argument: `SplitSettlementArgs({required String groupId, SplitSettlement? existing, String? fromMemberId, String? toMemberId})`); `SplitGroupDetailBinding` / `SplitSettlementBinding`.
- Detail screen: header (total spent, the user's total share, the user's net text), **Balances** rows `"@from → @to @amount"` each with a *Settle* button opening the settlement form prefilled, **Activity** by day (expenses: title, total, "Your share" amount; settlements: "@from paid @to"), paged on scroll, FAB "Add expense" (opens `AppRoutes.splitExpenseForm`, registered in Task 12), tapping an expense/settlement opens its form, states loading / empty ("No expenses yet") / error with retry. Settlement form: from, to, amount (outstanding prefilled), date, account (only when the user is a party), note, Delete when editing with confirmation.

- [ ] **Step 1: Write the failing widget tests** (`FakeFinance` with the spec dinner as stored split rows): header shows `₹1,200.00` spent, share `₹300.00`, `You get ₹500.00`; balances list shows `Amit → You ₹200.00` and `Amit → Rahul ₹100.00` (names from contacts; a deleted-contact member shows `Deleted contact`); tapping *Settle* opens the form with `200` prefilled, Save stores the settlement and the row disappears; overpaying 250 shows the flipped row `You → Amit ₹50.00`; an empty group shows "No expenses yet"; activity with 120 items loads the next page on scroll.
- [ ] **Step 2:** run → FAIL. **Step 3: Implement** (views, routes, bindings, list-row navigation, translations, coverage entries). **Step 4:** run → PASS; `flutter test test/core/translations test/features` → pass; `flutter analyze` → no issues.
- [ ] **Step 5: Docs:** `docs/12_UI_NAVIGATION_MAP.md` rows for the two routes.
- [ ] **Step 6: Commit** — `git commit -m "feat(split): group detail and settlement screens"`.

---

### Task 12: Screens — expense form and the "Split expense" entry

**Files:**
- Create: `lib/features/split/views/split_expense_form_view.dart`
- Modify: `lib/routes/app_routes.dart`, `lib/routes/app_pages.dart`, `lib/bindings/feature_bindings.dart`, `lib/features/transactions/views/transaction_list_view.dart` (`showAddTransactionSheet`), `docs/01_PRODUCT_REQUIREMENTS.md`, `docs/12_UI_NAVIGATION_MAP.md`, translations, `test/core/translations/translation_coverage_test.dart`
- Test: `test/features/split/split_expense_form_test.dart`

**Interfaces:**
- Consumes: Task 9 `SplitExpenseController`; Task 10 `SplitGroupController` for the group chooser.
- Produces route `AppRoutes.splitExpenseForm = '/split-expense-form'` (argument: `SplitExpenseArgs({required String groupId, SplitExpenseDetail? existing})`) with `SplitExpenseBinding`; the add-transaction sheet gets a fourth option "Split expense" (`Icons.groups_outlined`, subtitle "Share a bill with friends") that opens a group chooser (list of groups; none → the group form) and then the form.
- Screen: title, amount, date; **Paid by** (the user by default, "Multiple" shows an amount per member with `'@amount left'`); **Split** segmented Equal / Exact / % / Shares with a row per member (tick for equal, amount/percent/share count otherwise) and the amount left; category and account (`'Choose a category'` / `'Choose an account'` only when the controller's `error` says so); note; live preview line `'Your share @share · You get @amount'` / `'You owe @amount'`; Save, and Delete with confirmation when editing. All numbers come from the controller getters (no math in the widget).

- [ ] **Step 1: Write the failing widget tests:** the spec dinner end to end — amount 1200, Multiple payers (me 800, Rahul 400), Equal with all four ticked, category and account chosen → preview shows `Your share ₹300.00 · You get ₹500.00`, Save stores the split and the list/group shows it; paid sum off by a paisa shows `What was paid must add up to the total` and Save does nothing; `100.005` shows the two-decimals message; switching to Percent and typing 50/30/20 shows the amounts left; user paid for others (untick the user) needs no category; editing reopens in the same mode with the same numbers; delete confirms and removes; the add-transaction sheet shows "Split expense".
- [ ] **Step 2:** run → FAIL. **Step 3: Implement** (view, route, binding, sheet entry, translations, coverage entry). **Step 4:** run → PASS; `flutter test test/core/translations test/features` → pass; `flutter analyze` → no issues.
- [ ] **Step 5: Docs:** `docs/01_PRODUCT_REQUIREMENTS.md` gets a "Split expenses" section (scope and out-of-scope from the spec); `docs/12_UI_NAVIGATION_MAP.md` the expense-form row and the sheet entry.
- [ ] **Step 6: Commit** — `git commit -m "feat(split): split expense form and entry point"`.

---

### Task 13: Guards and group chips on existing screens

**Files:**
- Modify: `lib/features/contacts/controller/contact_detail_controller.dart` (`deleteContact`, `deleteEntry`), `lib/features/contacts/views/contact_detail_view.dart` (entry tap, ledger chip), `lib/features/contacts/views/contact_entry_view.dart` (edit/delete of a linked entry), `lib/features/transactions/views/transaction_detail_view.dart` (`_editable`, delete), `lib/features/transactions/controller/transaction_controller.dart` (`deleteTransaction`), `lib/features/transactions/views/transaction_list_view.dart` and `lib/widgets/transaction_list_item.dart` (chip), translations, `docs/12_UI_NAVIGATION_MAP.md`
- Test: `test/features/split/split_guards_test.dart`

**Interfaces:**
- Consumes: Task 4 link columns, Task 5 `groupNameBlockingContactDelete`, `getLinks`, `SplitLink`.
- Produces: controllers load `Map<String, SplitLink> splitLinks` for the rows they show (`SplitRepository.getLinks(expenseIds: …, settlementIds: …)`); `TransactionListItem` gets an optional `String? groupLabel` rendered as a small chip; a derived transaction or khata entry shows **"Open in group"** (opens `AppRoutes.splitExpenseForm` / `AppRoutes.splitSettlementForm` for its link) instead of Edit/Delete; `ContactDetailController.deleteContact()` fails when `groupNameBlockingContactDelete` returns a name, with `UnexpectedFailure('@name is in the group @group. Remove them from the group first.'.trParams({...}))` (built already translated, so the exception's own `.tr` is a no-op; the English key still goes into both translation maps); `TransactionController.deleteTransaction` and `ContactDetailController.deleteEntry` refuse a row that has `splitExpenseId` or `splitSettlementId` with `UnexpectedFailure('Open it in the group to change or delete it')`.

- [ ] **Step 1: Write the failing tests** (`FakeFinance` with a group, the dinner's derived rows added to `transactions`/`contactTransactions` with `splitExpenseId`, and a plain khata entry): deleting a contact that is a live member is refused with the group name, deleting an unrelated contact works; the transaction detail of a derived row shows "Open in group" and no Edit/Delete, a normal transaction still shows both; `deleteTransaction`/`deleteEntry` on a linked row return false with the message and delete nothing; the khata ledger and the transaction list show the group name chip on derived rows only; "Open in group" opens the split expense form for that expense.
- [ ] **Step 2:** run → FAIL. **Step 3: Implement.** **Step 4:** run → PASS; `flutter test test/features test/core/translations` → pass; `flutter analyze` → no issues.
- [ ] **Step 5: Docs:** `docs/12_UI_NAVIGATION_MAP.md` — the "Open in group" behaviour on transaction detail and khata entry.
- [ ] **Step 6: Commit** — `git commit -m "feat(split): guards and group chips on transactions and khata"`.

---

### Task 14: Final verification

- [ ] **Step 1:** `dart format --output=none --set-exit-if-changed` on every file this plan created; `flutter analyze` → "No issues found!".
- [ ] **Step 2:** `flutter test` → everything passes (the suite was green after Task 0).
- [ ] **Step 3:** remind the user to run `supabase/migrations/20261024100000_split_expenses.sql` before releasing this build, and `supabase/checks/cross_user_isolation.sql` afterwards.
