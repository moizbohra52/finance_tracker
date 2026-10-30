# Financial Logic

## Money representation
Persist money as decimal NUMERIC(18,2). In Dart use a decimal-safe strategy; do not rely on binary floating-point for critical persisted calculations.

## Account balance
For an account:

balance =
opening_balance
+ income
+ transfer_in
+ adjustments_in
- expense
- transfer_out
- adjustments_out

Credit/debit khata entries do not automatically change a cash/bank account unless a corresponding payment/receipt transaction is recorded.

## Overall balance
overall_balance =
sum(account balances)

Do not count transfers twice.

## Khata
A contact ledger has two directions:
- receivable: user should receive money
- payable: user should pay money

Example:
Contact owes user ₹5,000 -> receivable ₹5,000.
User pays ₹2,000 -> receivable becomes ₹3,000.

If user owes contact ₹5,000 -> payable ₹5,000.
User pays ₹2,000 -> payable becomes ₹3,000.

## Opening balance
Opening balance is the starting point for an account/contact. It must be included in current balance.

Changing opening balance should be auditable. Prefer an adjustment/history record rather than silently rewriting historical transactions.

## Transfer
A transfer creates two linked entries:
- source: transfer_out
- destination: transfer_in

Both share a transfer reference/id.

Transfer must not affect total net worth.

Implementation (`domain/services/transfer_legs.dart`):
- Both legs carry the same amount, date and note, and no category.
- Ids (transfer id and both leg ids) are generated once per form, so a retried
  save upserts the same rows.
- Both legs are written in one local database transaction together with their
  sync-queue items, outgoing first; deleting a transfer tombstones both legs
  in one transaction.
- Editing updates both rows in place, except when the new source is the old
  destination: the server allows one leg per account per transfer
  (`transactions_transfer_account_key`), and the two updates sync one after
  the other, so that edit would be rejected half-way. It is recorded instead
  as a new transfer that replaces (tombstones) the old one in the same step.

## Income/expense
Income increases account balance.
Expense decreases account balance.

## Monthly summary
closing_balance =
opening_balance
+ total_income
- total_expense
+ net_adjustments
+ net_external_receipts/payments where applicable

For reports, clearly distinguish:
- cash flow
- income/expense
- receivable/payable

## Budget
spent = sum(expense transactions for category and period)

remaining = budget - spent

percentage = spent / budget * 100

Alerts:
- >= 75%
- >= 90%
- >= 100%

Prevent duplicate alerts for the same budget threshold and period.

## Savings goal
A goal tracks progress only: the user updates saved_amount by hand and can put
parts of an income into it, and a goal never moves money, creates a transaction
or changes an account balance (an income keeps its full amount).

totalSaved = saved_amount + sum(live contributions)

A contribution is live when neither it nor its income transaction is deleted.

remaining = max(target - totalSaved, 0)

progress = totalSaved / target, capped at 100%

reached = totalSaved >= target

overdue = not reached and today is after target_date (the date is inclusive)

Income savings (contributions) rules:
- each part > 0
- a goal at most once per income
- parts total <= the income amount
- income transactions only

Calculated in `domain/entities/savings_goal.dart` with exact decimals.

## Split expenses
Friends share a bill inside a group while the user's own books stay exact to
the paisa. The split tables are the source of truth; the user's expense,
account movement and khata entries are derived rows written with them. All
maths lives in `domain/services/split_calculator.dart` and
`domain/services/split_balances.dart`, exact decimals, paise internally.

### Allocation
`SplitCalculator.allocate(total, weights)` splits the paise total by weights
with the largest remainder method; ties go by ascending member id, so every
device gets the same result. The parts always add up to the total exactly.

- equal: weight 1 for each ticked member, 0 otherwise; at least one ticked
- exact: the amounts typed (no allocation; must add up to the total)
- percent: weights are the percentages; they must add up to 100
- shares: weights are whole numbers >= 0, at least one > 0

### Validation (one expense)
In this order, each refusal is an English message key:
- total > 0 and no negative amount
- total, paid and share amounts have at most 2 decimals
- sum of paid = total
- sum of shares = total
- at least one member other than the user has a paid or share amount > 0
- the user's share > 0 → category required
- the user's paid > 0 or the user's share > 0 → account required

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

Account movement is always `−paid_me`. Date: `expense_date`. If the user
neither paid nor shares, there are no derived rows.

Checked examples:
- ₹1200, user paid 800, Rahul 400, four × 300: expense 300 + payment_made 500
  (account −800); khata Amit +200, Neha +200, Rahul +100.
- Rahul paid all ₹1200, four × 300: expense 300 + payment_received 300
  (account 0); khata Rahul −300.

### Group balances
`SplitBalances.compute` (live rows only):
- each member's net: Σ(paid − share) over expenses, plus settlements paid,
  minus settlements received; the nets add to zero
- pairwise, user with friend: sum of that friend's `n_f` over the group's
  expenses, minus settlements from the friend to the user, plus settlements
  from the user to the friend; equals the khata exactly
- pairwise, friend with friend: `(share_i × paid_j − share_j × paid_i) / T`
  summed exactly over the expenses, minus their settlements, rounded to paise
  once; display only, may differ from a by-hand sum by a paisa

Pairs with amount 0 are omitted; a negative result is stored with debtor and
creditor swapped. A settlement `from → to` of `x` reduces what `from` owes
`to`; paying more than the outstanding amount flips the direction.

## Validation
- amount > 0
- maximum supported precision 2 decimals for INR
- valid date
- required account/category based on transaction type
- transfer source and destination must differ

## Required unit tests
Test:
- opening balance only
- income only
- expense only
- income + expense
- transfers
- credit/debit settlement
- negative/invalid amounts
- monthly boundary dates
- multiple accounts
- zero balance
- large amounts
