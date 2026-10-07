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
