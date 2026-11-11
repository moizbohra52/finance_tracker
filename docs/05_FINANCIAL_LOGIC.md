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

Balance = signed opening balance + the entries' signed amounts
(`ContactTransaction.signedOf`: credit, payment made and adjustment add;
debit and payment received subtract). The contact screen loads its ledger 30
entries at a time, so it takes the entries' total from
`ContactRepository.getEntriesTotal`, which reads only the type and amount
columns, and adds it with `Contact.balanceWith`. The statement PDF and a
contact delete read the whole ledger, never just the loaded pages.

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
A goal tracks progress only: saved_amount is the starting amount (set in the
goal form), the user adds money to it by hand ("Add money") and can put parts
of an income into it, and a goal never moves money, creates a transaction or
changes an account balance (an income keeps its full amount).

totalSaved = saved_amount + sum(live contributions)

Contributions are of two kinds: money added by hand (no income, dated by
added_at) and parts of incomes. A contribution is live when it is not deleted
and, for an income's part, its income transaction is not deleted. Adding
money writes a new row instead of raising saved_amount, so the total is
always derived (a retried or two-device add never counts twice) and every
addition is in the goal's history. Removing a hand-added row from the history
lowers the total by its amount.

remaining = max(target - totalSaved, 0)

progress = totalSaved / target, capped at 100%

reached = totalSaved >= target

overdue = not reached and today is after target_date (the date is inclusive)

Money added by hand: amount > 0, one row per Add money.

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

## Loans
Money borrowed (`taken`) or lent (`given`), repaid in one of two ways. The
`loans` and `loan_payments` tables are the source of truth; the user's account
movements, interest expense/income and the reminder are derived rows written
with them. All maths lives in `domain/services/loan_calculator.dart`, exact
`Decimal`s (never `double` for money), rounded half up to paisa at each step.
A monthly rate is stored as `annual_rate` = rate × 12.

Dates are calendar dates (the local date of `paid_at`, no time). A due date
keeps the day of the month, clamped to the month's length (31 Jan -> 28/29
Feb). Rows with `deleted_at` set are ignored everywhere.

### EMI loans
- r = annual_rate / 1200. EMI = P·r·(1+r)ⁿ / ((1+r)ⁿ − 1); P / n when r = 0.
  Example: ₹5,00,000 at 9% over 60 months = ₹10,379.18.
- A scheduled payment's interest = outstanding × r; its principal = EMI −
  interest. First EMI: 10,379.18 = 6,629.18 principal + 3,750.00 interest. The
  last one takes exactly the outstanding (principal 10,301.71, total 10,378.97);
  interest over the 60 months is ₹1,22,750.59. A zero rate over 3 months of
  ₹1,000 ends 333.33, 333.33, 333.34.
- Due date k = first_due_date + (k − 1) months. The next due date is that of
  (live scheduled payments + 1).
- Remaining EMIs. With no live `extra` payment: tenure − live scheduled
  payments (at least 1 while something is owed), and the last one takes exactly
  the outstanding. With an `extra` payment, the EMI stays and the months
  shrink: ceil(ln(E / (E − O·r)) / ln(1 + r) − 1e-9) (doubles, only to count
  months), or ceil(O / E) when r = 0. Why: the EMI is rounded to paisa, so
  counting months from the EMI alone gives a 61st payment of a few paise on
  most fresh loans (1,454 of 3,000 random ones); counting from the tenure ends
  every fresh loan on its tenure.
- After 12 EMIs and ₹1,00,000 prepaid: ₹3,17,084.97 owed, 35 EMIs left (the
  13th due on 5 Feb 2028, the last numbered 47 at ₹8,592.08).
- The schedule of remaining EMIs is computed for display, never stored.

### Monthly-interest loans
- m = annual_rate / 1200. Interest is counted in whole months: month k is
  complete on its anniversary, start_date + k months, and costs
  `round(m × principal owed at the start of that month)`; the principal owed
  there ignores payments dated after the month's start.
- Unpaid interest at D = interest accrued by D − interest parts of payments
  dated on or before D, never below 0. Part months carry no interest.
- The next due date is the first anniversary of start_date after the latest
  live payment (after the start when there is none), not "after today": it
  needs no clock and an unpaid month stays overdue. The next amount is the
  unpaid interest on that date.
- Example (Ravi, ₹10,000 at 2% a month, annual_rate 24, from 1 Jan 2027):
  400 accrued on 15 Mar. A payment of 3,000 that day splits 400 interest +
  2,600 principal; 7,400 is then owed, the next due date is 1 Apr and the next
  amount 200.00 (March's month started on 1 Mar at ₹10,000); on 1 May the
  unpaid interest is 348.00 (April's 148 is on ₹7,400). Closing on 15 Mar is
  10,400 (400 + 10,000).
- Short months: ₹1,000 at 24% from 31 Jan 2027 has 0 complete months on 27 Feb,
  1 on 28 Feb (interest 20), 2 on 31 Mar, 3 on 30 Apr. A payment of 20 on 28
  Feb is all interest and the next due date is 31 Mar.

### Payment splits
`LoanCalculator.suggest` proposes the split; the user can change it. The
principal part reduces the outstanding (outstanding = principal − principal
parts of live payments). Interest comes first:
- EMI `scheduled`, no amount: the next schedule row. With an amount: interest =
  min(amount, outstanding × r), the rest principal (3,000 on the first EMI is
  all interest).
- EMI `extra`: all principal; closing = the whole outstanding (₹4,17,084.97
  after 12 EMIs, no interest). A charge the bank adds is typed as its interest
  part.
- Monthly: interest = min(amount, unpaid interest at `paid_at`), the rest
  principal; no amount = the unpaid interest, or outstanding + unpaid interest
  when closing.

### Validation
Each refusal is an English message key, in this order.

Loan (`validateLoan`): name not blank; account chosen; principal > 0; principal
and EMI have at most 2 decimals; rate 0..60% a year (monthly loans: 0..5% a
month); EMI loans only: tenure 1..480 months, EMI > 0, an EMI that does not
cover the first month's interest (rate > 0 and EMI ≤ P·r) is refused, first due
date chosen and not before the start date. (An EMI of 3,750.00 on the example
loan is refused.)

Payment (`validatePayment`, against the loan's other live payments):
- amount > 0; at most 2 decimals; principal + interest = amount, no negative
  part
- not dated before the latest live payment or the loan start (back-dating would
  leave the stored splits of later payments stale); the same day is allowed
- the loan is not already repaid; the principal part is at most the
  outstanding (417,084.98 on 417,084.97 owed is refused)
- monthly only: the amount is at most outstanding + unpaid interest at
  `paid_at` (10,401 on Ravi at 15 Mar is refused)
- the interest part of an EMI or closing payment is not capped (it is the
  bank's figure); 417,084.97 + a 5,000 charge is accepted

### Derived rows
Deterministic ids (UUID v5), so a retried save upserts the same rows. A part of
zero writes no row. A derived row has `contact_id` null: a loan never touches
the khata.

| Event | Row | Type | Category key | Id seed |
|---|---|---|---|---|
| Loan taken, `moved_money` | money in to `account_id` | `payment_received` | `loan_taken` | `loan:<loan id>` |
| Loan given, `moved_money` | money out of `account_id` | `payment_made` | `loan_given` | `loan:<loan id>` |
| Payment on a loan taken | principal out | `payment_made` | `loan_repayment_made` | `loan-payment:<id>:principal` |
| | interest out | `expense` | `loan_interest_paid` | `loan-payment:<id>:interest` |
| Payment on a loan given | principal in | `payment_received` | `loan_repayment_received` | `loan-payment:<id>:principal` |
| | interest in | `income` | `loan_interest_received` | `loan-payment:<id>:interest` |

`payment_made` and `payment_received` move the account balance and are left
out of income and expense totals, as for khata entries; interest rows count as
expense or income.

## Home insights
`InsightsCalculator` (domain/services), shown on the home screen.

- **Net worth** = current balance of active accounts + total khata
  receivable - total khata payable. Archived accounts are left out, as in the
  overall balance. Shown only when it differs from the balance, that is when
  someone owes or is owed money.
- **Spending so far** compares this month with the same days of last month:
  this month from the 1st to the end of today, last month from the 1st to the
  end of the same day of the month, or to its last day when it is shorter
  (31 March compares with all of February). Spending is expense only, as in
  the monthly summary: transfers, adjustments and deleted rows do not count.
- **Change** = (this month - last month) / last month x 100, rounded to a
  whole percent. No percent is shown when last month had no spending by then.
- **Biggest rise** is the expense category with the largest increase over
  the same two windows; a category new this month counts its whole amount.
  None is shown when no category rose. A tie goes to the category with more
  spending this month.

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
