# Loans and EMIs — design

Date: 2026-11-11. Status: approved in chat, awaiting spec review.

## Goal
Track loans the user has taken (a home, bike or personal loan from a bank, or
money borrowed from a relative at interest) and loans the user has given (money
lent at interest): what is still owed, the next instalment, how each payment
splits into principal and interest, and the effect on the user's accounts and
net worth.

Success: the user adds a ₹5,00,000 home loan at 9% a year for 60 months,
received into HDFC. The app fills the EMI ₹10,379.18 and reminds them on each
due date. They tap the reminder and save: HDFC drops by ₹10,379.18, the expense
report shows ₹3,750.00 of loan interest (the principal is not an expense), the
loan shows ₹4,93,370.82 still owed, and net worth is lower by what is still
owed. After 12 EMIs they prepay ₹1,00,000; the EMI stays the same and the loan
now ends after 35 more EMIs instead of 48. Separately, they lend Ravi ₹10,000
at 2% a month on 1 January; when Ravi pays ₹3,000 on 15 March the app splits it
into ₹400 interest (two full months) and ₹2,600 principal, and ₹7,400 is still
owed. All of it works offline and syncs.

## Decisions (from the chat)
- Both directions: loans taken and loans given.
- Two methods, chosen per loan, in either direction:
  - `emi`: a fixed EMI on a reducing balance, as banks calculate it.
  - `monthly_interest`: interest at a % per month on the outstanding principal
    ("2 rupaye sekda"); repayments of any amount, at any time.
- Money moves through accounts: receiving or giving the loan, and every
  payment, write account transactions. The principal part moves the balance
  but is not income or expense; the interest part is an expense (loan taken)
  or income (loan given).
- A loan can be linked to a khata contact (optional). The contact screen lists
  their loans, but the khata balance does not include them, so no money is
  counted twice.
- On a due date the app sends a reminder; tapping it opens the payment form
  filled in, and one tap saves. Nothing is recorded automatically.
- EMI loans accept part-prepayments, which shorten the tenure and keep the EMI,
  and closing the loan early (foreclosure).
- Approach A: `loans` and `loan_payments` are the source of truth; the account
  transactions are derived rows written with them, as split expenses do.

## Schema
New migration `supabase/migrations/20261111090000_loans.sql`. Every table has
owner-only RLS with the four standard policies and no `anon` grant (same
pattern as `savings_goals`, docs/04_SECURITY_RLS.md). Money is
`numeric(18, 2)`; ids are client-generated UUIDs.

### loans
- `id uuid` PK, `user_id uuid not null`
- `direction text not null` check `in ('taken', 'given')`
- `method text not null` check `in ('emi', 'monthly_interest')`
- `name text not null` check length 1..80 (lender or borrower, "HDFC Home Loan")
- `contact_id uuid` nullable, composite FK `(user_id, contact_id)` → contacts
- `account_id uuid not null`, composite FK `(user_id, account_id)` → accounts
  (where the loan was received into or given from)
- `principal numeric(18, 2) not null` check `> 0`
- `annual_rate numeric(7, 4) not null` check `>= 0 and <= 60`. A monthly rate is
  stored ×12 (2% a month = 24); the form shows the method's own unit.
- `tenure_months integer` check `between 1 and 480`; required for `emi`, null
  for `monthly_interest`
- `emi_amount numeric(18, 2)` check `> 0`; required for `emi`, null otherwise.
  Filled by the app from the formula; the user can type the bank's figure.
- `start_date date not null` (when the money moved; interest runs from here)
- `first_due_date date` (first EMI; required for `emi`)
- `moved_money boolean not null default true` (false for a loan entered part
  way through, so today's account balance is not changed)
- `closed_at timestamptz` (set when nothing is owed; cleared if that payment is
  removed)
- `note text`, `created_at`, `updated_at`, `deleted_at`
- `unique (user_id, id)`
- CHECK: `method = 'emi'` exactly when `tenure_months`, `emi_amount` and
  `first_due_date` are all set.

### loan_payments
- `id uuid` PK, `user_id uuid not null`
- `loan_id uuid not null`, composite FK `(user_id, loan_id)` → loans
- `account_id uuid not null`, composite FK → accounts
- `kind text not null` check `in ('scheduled', 'extra')`. `scheduled`: an EMI,
  or a repayment of a `monthly_interest` loan. `extra`: a prepayment or the
  closing payment of an `emi` loan.
- `paid_at timestamptz not null`
- `amount numeric(18, 2) not null` check `> 0`
- `principal_part`, `interest_part numeric(18, 2) not null` check `>= 0`, and
  CHECK `principal_part + interest_part = amount`
- `note text`, `created_at`, `updated_at`, `deleted_at`
- `unique (user_id, id)`; index on `(user_id, loan_id)`

The split is filled by the calculator and editable in the form; once saved it
is stored and never recalculated. Only a loan's latest live payment can be
edited or deleted, so no later stored split goes stale.

### Changes to existing tables
- `transactions.loan_id uuid` nullable, composite FK `(user_id, loan_id)` →
  loans, partial index. A row with it set is derived from a loan: it is edited
  or deleted only through the loan (as `split_expense_id` rows are).
- `reminders.loan_id uuid` nullable, composite FK → loans, and `'loan'` added
  to the `reminder_type` CHECK.
- Six system categories with `system_key`s, seeded like the khata ones, at the
  next free ids (101-109 and 201-220 are taken, locally and on the server):
  `c0000000-0000-4000-8000-000000000110` `loan_taken`, `…111`
  `loan_repayment_received`, `…112` `loan_interest_received` (type income), and
  `…221` `loan_given`, `…222` `loan_repayment_made`, `…223`
  `loan_interest_paid` (type expense).

### Local database
Version 10: the same two tables and two columns, the new categories seeded,
and both tables added to the sync engine's push and pull lists, backup, and
`clearAllUserData`.

## Money flows (derived transactions)
Deterministic ids (UUID v5), so a retried save upserts the same rows:

| Event | Row | Type | Category key | Id seed |
|---|---|---|---|---|
| Loan taken, `moved_money` | money in to `account_id` | `payment_received` | `loan_taken` | `loan:<loan id>` |
| Loan given, `moved_money` | money out of `account_id` | `payment_made` | `loan_given` | `loan:<loan id>` |
| Payment on a loan taken | principal out | `payment_made` | `loan_repayment_made` | `loan-payment:<id>:principal` |
| | interest out | `expense` | `loan_interest_paid` | `loan-payment:<id>:interest` |
| Payment on a loan given | principal in | `payment_received` | `loan_repayment_received` | `loan-payment:<id>:principal` |
| | interest in | `income` | `loan_interest_received` | `loan-payment:<id>:interest` |

A part of zero writes no row. `payment_made` and `payment_received` move the
account balance and are left out of income and expense totals
(FinanceSummaryCalculator, reports), as for khata entries; interest rows count
as expense or income. A loan, its payments, their derived rows and the
reminder are written in one local database transaction, loan rows queued
before the transactions that reference them (the server FK needs the loan
first).

## Calculations (`LoanCalculator`, domain/services, Decimal, rounded to paisa)

### `emi`
- Monthly rate r = annual_rate / 12 / 100.
- EMI = P·r·(1+r)ⁿ / ((1+r)ⁿ − 1); P / n when r = 0. Rounded half up.
  Example: P ₹5,00,000, 9%, n 60 → ₹10,379.18.
- A scheduled payment's interest = outstanding × r; its principal =
  EMI − interest. The last one takes exactly the outstanding: in the example
  its principal is ₹10,301.71 and it totals ₹10,378.97. Total interest over
  60 months: ₹1,22,750.59.
- Due date k = first_due_date + (k − 1) months, the day clamped to the month's
  length (31 Jan → 28/29 Feb). The next due date is that of (live scheduled
  payments + 1).
- An `extra` payment is all principal; the EMI is unchanged and the remaining
  months are ceil(ln(EMI / (EMI − O·r)) / ln(1 + r)), or ceil(O / EMI) when
  r = 0. Example: after 12 EMIs and ₹1,00,000 prepaid, ₹3,17,084.97 is owed
  and 35 EMIs remain.
- Closing early: an `extra` payment of the whole outstanding principal, with
  any charge the bank adds entered as its interest part.
- The schedule of remaining EMIs is computed for display from the
  outstanding; it is never stored.

### `monthly_interest`
- Monthly rate m = annual_rate / 12 / 100.
- Interest is counted in whole months: a month is complete on each
  anniversary of start_date (the day clamped to the month's length). Interest
  accrued up to date D = the sum, over the months completed by D, of the
  principal outstanding at the start of that month × m, each rounded.
- Unpaid interest at D = accrued up to D − interest parts paid by D. A payment
  goes to unpaid interest first and the rest to principal. Example: ₹10,000 at
  2% from 1 Jan; ₹3,000 paid on 15 Mar → ₹400 interest (two months) and
  ₹2,600 principal; ₹7,400 owed, and April's interest is on ₹7,400.
- Part months carry no interest; when the other side counted differently, the
  user changes the split in the form.
- The next due date is the next anniversary after today; the form fills the
  unpaid interest as the amount.

### Both methods
- Outstanding = principal − principal parts of live payments. When it reaches
  zero the loan gets `closed_at`.
- Net worth (InsightsCalculator) = accounts + khata receivable − khata payable
  + outstanding of loans given − outstanding of loans taken.
- Validation: principal > 0; rate 0..60% a year; tenure 1..480 months; an EMI
  that does not cover the first month's interest (EMI ≤ P·r) is refused; a
  payment cannot exceed outstanding + unpaid interest; parts must add up to
  the amount; the first due date cannot be before the start date.

## Screens
- Home "Plan" section: a Loans tile, route `/loans`.
- Loans list: "Taken" and "Given" segments, the total outstanding of each on
  top; per loan the name, outstanding, a progress bar of principal repaid, and
  the next due date and amount. Closed loans in a collapsed section.
- Loan form: direction, method, name, contact (optional), principal, rate (a
  year for `emi`, a month for `monthly_interest`), tenure and EMI (`emi`; the
  EMI fills itself and can be changed), start date, first due date, account,
  the "money moved" switch, note. Once a loan has a live payment, only the
  name, contact and note can change.
- Loan detail: outstanding, progress, next instalment; actions "Record
  payment", "Prepay" (`emi`), "Close loan"; the remaining schedule (`emi`) as a
  lazy list; the payment history, newest first, with edit and delete on the
  latest only. Delete loan (confirmation) removes the loan, its payments,
  their derived rows and its reminder.
- Payment form: date, account, amount (filled with the EMI, or the unpaid
  interest), the principal and interest split (filled, editable), note.
- Contact detail: a "Loans" section listing the contact's loans; the khata
  balance is unchanged.
- Transactions: rows with `loan_id` cannot be swiped or edited; their detail
  shows "Open loan" instead of Edit and Delete.

## Reminders
One reminder per open loan (type `loan`, `reminders.loan_id`, id UUID v5 of
`loan-reminder:<loan id>`) at the next due date. Tapping it opens the payment
form filled in. After each payment it moves to the next due date; it is
removed when the loan closes or is deleted.

## Out of scope (v1)
Floating rate changes; choosing to reduce the EMI on a prepayment; processing
fees; daily or compound interest; loans paid out in several parts; a loan PDF
statement; WhatsApp reminders for loans given; moratoriums; loans in the export
screen.

## Testing
- Calculator unit tests: the EMI formula against the examples, rounding, the
  last EMI, a zero rate, due dates across short months, the tenure after a
  prepayment, closing, whole-month interest across short months, payment
  splitting, validation.
- Repository tests: a loan and a payment write their derived rows and the
  reminder in one transaction; a retried save does not duplicate; deleting a
  payment or a loan removes its rows; only the latest payment can change.
- Controller and widget tests: the loan form (EMI fill, validation, locked
  terms), the detail screen, recording a payment from a reminder, the guard on
  derived rows in the transactions list, the contact's Loans section, net
  worth.
- `supabase/checks/cross_user_isolation.sql` covers both new tables.

## Rollout
Apply the migration before shipping the app version with loans; until then
loans stay on the phone and their uploads retry (nothing is lost). Docs to
update: 03 (schema), 04 (RLS), 05 (loan maths, net worth), 07 (sync order), 08
(the loan reminder), 12 (navigation).
