# Product Requirements

## Authentication
- Splash
- Onboarding
- Register
- Login
- Forgot password
- Reset password
- Change password
- Logout
- Delete account

## Profile
- Name
- Email
- Mobile
- Avatar
- Currency
- Timezone
- Edit profile

## Finance
- Opening balance
- Multiple accounts
- Income
- Expense
- Transfer
- Categories
- Unified transaction history
- Search/filter
- Monthly summaries
- Tags (2026-10-23): #words in a transaction note, e.g. "Dinner #office".
  No column of their own: the note search finds "#office", the detail screen
  shows them as chips that open that search, and the form suggests recent
  ones. Known limit: "#goa" also finds "#goatrip" (substring search).
- Notes search: transactions match note and description; Khata contacts
  match name, mobile and notes

## Khata
- Contacts/persons
- Opening ledger balance
- Credit/debit
- Receive/pay
- Outstanding receivable/payable
- Transaction timeline
- Due dates/reminders

## Split expenses (2026-10-23, revised 2026-10-26)
- Groups of the user and friends (from Khata contacts), e.g. a trip,
  flatmates or office lunch
- A group expense: total, date, title, category, account and note; who paid
  (the user or several members) and how it is split — equal ticks, exact
  amounts, percentages or share counts, with the unassigned amount shown
- The user's own books stay exact to the paisa: each save writes the user's
  expense (their share), their balance movement (paid for others / paid by
  others) and one khata entry per friend's net
- Group balances: what each member owes whom (pairwise, friend-to-friend
  included), the user's net, and settle-up payments between any two members
- Guards: a derived transaction or khata entry can only be changed through
  its group ("Open in group"); a contact in a live group member cannot be
  deleted until removed from the group
- Out of scope: groups with more than one device-editing user (the data is
  the signed-in user's own), receipts attached to split expenses, currencies
  per group, inviting by link, exporting a group's statement

## Reports
- Income
- Expense
- Net cash flow
- Category analysis
- Account analysis
- Receivable/payable
- Monthly/yearly charts

## Budget
- Monthly/custom budgets
- Category budgets
- 75/90/100% alerts

## Savings goals (2026-10-23)
- Name, target amount, amount saved so far (updated by hand: "Add money" on
  the goal card, or edit the goal), optional target date
- An income can be split into goals when it is added or edited; a goal's total
  is the amount saved by hand plus its income contributions
- Progress, amount left, reached and overdue state
- Tracking only: goals do not move money or change balances
- Not yet: a contributions list on the goal, linking a goal to an account, goal
  alerts

## Recurring
- Daily/weekly/monthly/yearly/custom
- Rent, salary, EMI, subscription, insurance etc.

## Reminder
- One-time and repeating reminders
- Related contact/account/transaction
- Notification time

## Settings
- Theme
- Accent color
- Currency
- Language
- Date/number format
- Notification controls
- Backup/export
- Privacy/terms/about

## Acceptance philosophy
Every feature must support:
- validation
- loading
- success
- empty
- error
- offline behavior where relevant
- confirmation for destructive actions
