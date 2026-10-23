# Split expenses with friends — design

Date: 2026-10-23. Status: approved in chat, awaiting spec review.

## Goal
Let the user share an expense with friends (a trip, flatmates, an office lunch),
see who owes whom inside a group, and settle up — while the user's own books
stay right: their expense is only their share, the account moves by what they
actually paid, and what friends owe them (or they owe friends) lands in the
existing khata.

Success: on a trip group, the user adds a ₹1200 dinner paid ₹800 by them and
₹400 by Rahul, split equally four ways. Their expense report shows ₹300, the
bank account drops ₹800, the khata shows Amit +₹200, Neha +₹200, Rahul +₹100,
and the group screen also shows Amit → Rahul ₹100 and Neha → Rahul ₹100. All of
it works offline and syncs.

## Decisions
- Single-user, like the rest of the app. Friends are khata contacts, not app
  users; only the user sees their groups. Groups shared between app users are a
  later project: `2026-10-23-shared-split-groups-future.md`.
- Groups with fixed members; every expense belongs to a group.
- Several people can pay one expense (each with an amount).
- Split modes: equal (among ticked members), exact amounts, percentages,
  shares.
- Who-owes-whom is pairwise, not simplified (Splitwise "simplify debts"
  would suggest payments that disagree with the khata).
- Settle up from the group, between any two members. When the user is one of
  them it also writes a khata payment (account optional).
- Approach: the split tables are the source of truth; the user's expense,
  account movement and khata entries are derived rows written with them.
- Out of scope: group reminders/notifications (the khata's existing WhatsApp/SMS
  reminder works on each friend), receipts on splits, multi-currency, debt
  simplification, splits outside a group.

## Schema
New migration `supabase/migrations/20261023110000_split_expenses.sql`, same
conventions as `20261023100000_savings_goals.sql`: client UUID `id`, `user_id`
defaulting to `auth.uid()` with `on delete cascade`, `created_at`,
`updated_at` (shared trigger), `deleted_at`, RLS enabled, privileges revoked
from anon, four owner-only policies. References are composite
`(user_id, x) → parent (user_id, id)` like `finance_core`; each parent gets a
`unique (user_id, id)`. Apply before shipping the app version, or sync fails on
the unknown tables.

### split_groups
`name TEXT` not blank.

### split_group_members
`group_id`, `contact_id UUID nullable` → contacts. `contact_id null` is the user
themself; every group has exactly one such row.
Ids are deterministic (uuid v5 of `split-member:<group id>:<contact id | me>`),
so adding the same contact twice, on two devices or after a removal, upserts
(revives) the same row. No extra unique index needed.

### split_expenses
`group_id`, `title TEXT` not blank, `total_amount NUMERIC(18,2) > 0`,
`expense_date TIMESTAMPTZ`, `split_mode TEXT` check in
(`equal`, `exact`, `percent`, `shares`), `category_id UUID nullable`,
`account_id UUID nullable`, `note TEXT`.
Category and account are for the user's own rows; when they are required is in
"Validation".

### split_expense_parts
`split_expense_id`, `member_id`, `paid_amount NUMERIC(18,2) >= 0`,
`share_amount NUMERIC(18,2) >= 0`, `share_input NUMERIC nullable` (the percent
or share count typed, so the form reopens in the same mode).
Id: uuid v5 of `split-part:<expense id>:<member id>`. One table holds both who
paid and who shares, so multiple payers need no extra table. The sums are
checked in the app, not by the database.

### split_settlements
`group_id`, `from_member_id`, `to_member_id` (check: different),
`amount NUMERIC(18,2) > 0`, `settled_at TIMESTAMPTZ`,
`account_id UUID nullable`, `note TEXT`.

### Existing tables
`transactions` and `contact_transactions` gain `split_expense_id UUID nullable`
and `split_settlement_id UUID nullable`, composite references to the new
tables. A row with either set is derived from a split.

### Local database
Same tables in SQLite, `databaseVersion` 3 → 4: `_onUpgrade` creates the five
tables and adds the four columns. Registered wherever `savings_goals` is:
`app_database.dart` (table lists), `sync_engine.dart` (`syncableTables`),
`sync_status_sheet.dart`, `backup_service.dart`, `backup_preview_dialog.dart`,
`supabase/checks/cross_user_isolation.sql`.

## Financial rules
Pure Dart in `lib/domain/services/split_calculator.dart`, exact `Decimal`,
amounts in paise internally. Added to `docs/05_FINANCIAL_LOGIC.md`.

### Allocation
`allocate(total, weights)` splits a paise total by weights with the largest
remainder method; ties go by member id order, so every device gets the same
result. The parts always add up to the total exactly.
- equal: weight 1 for each ticked member, 0 otherwise; at least one ticked.
  `share_input` stays null; a member is ticked when their share is > 0
- exact: the amounts typed (no allocation; must add up to the total)
- percent: weights are the percentages; they must add up to 100
- shares: weights are whole numbers >= 0, at least one > 0

### Validation (one expense)
- total > 0, at most 2 decimals; every paid and share amount >= 0, 2 decimals
- sum of paid = total; sum of shares = total
- at least one member other than the user has a paid or share amount > 0
  (otherwise it is a plain expense)
- user's share > 0 → category required
- user's paid > 0 or user's share > 0 → account required

### The user's net with each friend (one expense)
For friend `f`, with `me` the user and `T` the total:

`n_f = (share_f × paid_me − share_me × paid_f) / T`

Exactly, `Σ n_f = paid_me − share_me`. After rounding each `n_f` to paise, the
largest remainder method forces that sum, so the khata and the account never
drift by a paisa. `n_f > 0`: the friend owes the user.

### Derived rows for the user (one expense)
| Condition | Row (uuid v5 id) |
|---|---|
| share_me > 0 | `transactions` `expense` of share_me, category, account (`split-expense:<id>:share`) |
| paid_me > share_me | `transactions` `payment_made` of paid_me − share_me, contact null (`:balance`) |
| paid_me < share_me | `transactions` `payment_received` of share_me − paid_me, contact null (`:balance`) |
| n_f > 0 | `contact_transactions` `credit` n_f (`:contact:<contact id>`) |
| n_f < 0 | `contact_transactions` `debit` −n_f (same id) |
| n_f = 0 | none (an earlier row with that id is tombstoned) |

Account movement is always `−paid_me`. Date: `expense_date`. Descriptions and
khata notes are written in the app language at save time, like
"Lent to @name": "Split: paid for others · @group",
"Split: others paid your share · @group", khata note "@group · @title".
If the user neither paid nor shares, there are no derived rows.

Checked examples:
- ₹1200, user paid 800, Rahul 400, four × 300: expense 300 + payment_made 500
  (account −800); khata Amit +200, Neha +200, Rahul +100.
- Rahul paid all ₹1200, four × 300: expense 300 + payment_received 300
  (account 0); khata Rahul −300. Paying Rahul back later through the khata
  moves the account −300.

### Group balances
- Each member's net in the group: Σ(paid − share) over expenses, plus
  settlements paid, minus settlements received. Exact; the nets add to zero.
- Pairwise, user with friend: sum of that friend's derived khata amounts in the
  group (`n_f`), minus settlements from the friend to the user, plus
  settlements from the user to the friend. Equals the khata exactly.
- Pairwise, friend with friend: `(share_i × paid_j − share_j × paid_i) / T`
  summed exactly over the group's expenses, minus their settlements, rounded
  to paise once. Display only; may differ from a by-hand sum by a paisa.

### Settlement
`from → to, amount` reduces what `from` owes `to`. The form prefills the
outstanding amount; paying more is allowed and flips the direction (as in the
khata). When the user is a party:
- friend → user: `contact_transactions` `payment_received`
  (`split-settlement:<id>:khata`), plus `transactions` `payment_received` with
  the friend as contact when an account is chosen (`:account`)
- user → friend: the same with `payment_made`

A settlement between two friends writes no derived rows and has no account.

## Data layer
- Entities in `lib/domain/entities/split.dart`: `SplitGroup`, `SplitMember`,
  `SplitExpense`, `SplitPart`, `SplitSettlement`. Models in
  `lib/data/models/split.dart`.
- `Transaction` and `ContactTransaction` (entity + model) gain
  `splitExpenseId` and `splitSettlementId`.
- `SplitRepository` (`lib/data/repositories/split_repository.dart`), built in
  `AppRepositories`, local datasource only (writes go through the sync queue).
  Each operation is one SQLite transaction holding the rows and their queue
  items, parents enqueued first: group → members → expense → parts → derived
  `transactions` and `contact_transactions`. A failure rolls back all of it.
  Pattern: `TransactionRepository.createTransfer`.
- `saveExpense` serves create and edit: ids come from the form (generated once),
  so a retry upserts. It recomputes the derived rows, upserts the needed ones,
  tombstones the ones no longer needed, and updates the `:balance` row in place
  when its type flips.
- `deleteExpense`, `deleteGroup`, `saveSettlement`, `deleteSettlement`
  tombstone everything they own in one transaction.
- Reads: groups with the user's net, a group's members, balances, and its
  activity (expenses and settlements, newest first, paged 50 at a time).
- Writes call `DataChangeNotifier.markChanged()` so Home, lists and Khata
  reload.

## Guards
- A group needs a name that is not blank and at least one friend besides the
  user.
- A khata entry or transaction with `split_expense_id` or
  `split_settlement_id` cannot be edited or deleted directly; its screens show
  "Open in group" instead.
- A contact who is a member of a group that is not deleted cannot be deleted
  (inline error naming the group).
- A member with a part or settlement that is not deleted cannot be removed
  from the group.
- Deleting an expense, settlement or group asks for confirmation; the group
  dialog states how many expenses and khata entries go with it.

## UI
Feature folder `lib/features/split/` (controllers, views), bindings in
`feature_bindings.dart`, routes in `app_routes.dart` / `app_pages.dart`,
documented in `docs/12_UI_NAVIGATION_MAP.md`. Existing widgets and patterns
only.

Entry points: a "Groups" action in the Khata tab app bar; "Split expense" in
the transactions FAB sheet (pick a group, then the expense form).

| Route | Screen |
|---|---|
| `/split-groups` | Groups: name, member count, the user's net ("You get ₹500" / "You owe ₹200" / "Settled"). FAB: new group |
| `/split-group-form` | Name and members: multi-select from `contact_picker_sheet`, new contact, or from phone contacts. Edit, delete |
| `/split-group-detail` | Header: total spent, the user's total share, the user's net. Balances: pairwise rows ("Amit → You ₹200", "Amit → Rahul ₹100"), each with *Settle*. Activity: expenses and settlements by day, paged. FAB: add expense |
| `/split-expense-form` | Title, amount, date. Paid by: the user by default, "Multiple" shows an amount per member with "₹X left". Split: Equal / Exact / % / Shares with a row per member and the amount left. Category and account (last used prefilled). Note. Live preview: "Your share ₹300 · You get ₹500" |
| `/split-settlement-form` | From, to, amount (outstanding prefilled), date, account (only when the user is a party), note |

Changes to existing screens: derived rows in the contact ledger and the
transaction list show a group chip and open the split expense or settlement;
transaction detail and khata entry show "Open in group" instead of Edit/Delete.

States: loading, empty ("No groups yet — make one for a trip, flatmates or
office lunch"), error with retry, offline, using the existing widgets. Every
string in English, Hindi and Hinglish.

## Docs to update
`01_PRODUCT_REQUIREMENTS.md` (Split expenses section), `03_DATABASE_SCHEMA.md`,
`04_SECURITY_RLS.md`, `05_FINANCIAL_LOGIC.md`, `07_OFFLINE_SYNC.md`,
`12_UI_NAVIGATION_MAP.md`.

## Testing
- `test/domain/split_calculator_test.dart`: allocation (₹100 / 3, percent,
  shares, exact sum mismatch), each validation error, nets for single payer,
  multiple payers, friend paid all, user paid but share 0, user not involved;
  a seeded random loop asserting Σ khata = paid_me − share_me and account
  movement = −paid_me to the paisa; group balances with settlements and an
  overpayment flip.
- `test/data/repositories/split_repository_test.dart` (like
  `transfer_repository_test.dart`, in-memory SQLite): save writes every row and
  queue item parent first; a retry with the same ids adds nothing; an edit
  tombstones stale derived rows and flips the balancing type; deleting an
  expense or group tombstones everything; a failure mid-write leaves nothing;
  account and khata balances from `finance_summary_calculator` match.
- Guards: contact delete blocked for a member; direct edit of a derived khata
  entry or transaction blocked.
- Widget tests with `fake_finance`: expense form validation and live preview,
  group detail empty and balances states.
- `translation_coverage_test` covers the new strings; `sync_engine_test`
  covers the new tables.
- `dart format`, `flutter analyze`, `flutter test`. After the user applies the
  migration: `supabase/checks/cross_user_isolation.sql`.
