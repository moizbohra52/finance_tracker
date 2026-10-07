# Supabase Database Schema

## Design rules
- PostgreSQL
- UUID primary keys
- Every user-owned table has user_id
- created_at and updated_at
- timestamptz for timestamps
- numeric/decimal for money, never floating point
- indexes on common filters
- foreign keys with deliberate delete behavior
- RLS on every user-owned table

## Core tables

### profiles
id UUID PK references auth.users(id)
full_name TEXT
mobile TEXT
avatar_url TEXT
currency_code TEXT default 'INR'
timezone TEXT
created_at TIMESTAMPTZ
updated_at TIMESTAMPTZ

### user_settings
id UUID PK
user_id UUID unique
theme_mode TEXT
accent_color TEXT
language_code TEXT
date_format TEXT
number_format TEXT
notifications_enabled BOOLEAN
created_at
updated_at

### accounts
id UUID PK
user_id UUID
name TEXT
type TEXT -- cash, bank, upi, card, other
opening_balance NUMERIC(18,2)
opening_balance_date DATE
is_active BOOLEAN
created_at
updated_at
deleted_at

### categories
id UUID PK
user_id UUID nullable for system categories
name TEXT
type TEXT -- income, expense, both
icon TEXT
is_system BOOLEAN
is_active BOOLEAN
created_at
updated_at
deleted_at

### transactions
id UUID PK
user_id UUID
account_id UUID
category_id UUID nullable
contact_id UUID nullable
type TEXT
amount NUMERIC(18,2)
transaction_date TIMESTAMPTZ
note TEXT
description TEXT
payment_method TEXT
attachment_url TEXT nullable
transfer_id UUID nullable -- shared by both legs of a transfer
created_at
updated_at
deleted_at TIMESTAMPTZ nullable

Transaction types:
income, expense, credit, debit, payment_received, payment_made, transfer_in, transfer_out, opening_balance, adjustment

### contacts
id UUID PK
user_id UUID
name TEXT
mobile TEXT
email TEXT
address TEXT
notes TEXT
opening_balance NUMERIC(18,2)
opening_balance_type TEXT -- receivable/payable
created_at
updated_at
deleted_at

### contact_transactions
id UUID PK
user_id UUID
contact_id UUID
type TEXT -- credit/debit/payment_received/payment_made/adjustment
amount NUMERIC(18,2)
transaction_date TIMESTAMPTZ
due_date DATE nullable
note TEXT
created_at
updated_at
deleted_at

### budgets
id UUID PK
user_id UUID
category_id UUID nullable -- null = overall budget across expense categories
amount NUMERIC(18,2)
period_type TEXT -- monthly, custom
start_date DATE
end_date DATE nullable -- required for custom
alert_75 BOOLEAN
alert_90 BOOLEAN
alert_100 BOOLEAN
created_at
updated_at
deleted_at

### recurring_transactions
id UUID PK
user_id UUID
account_id UUID
category_id UUID nullable
type TEXT -- income, expense
amount NUMERIC(18,2)
frequency TEXT -- daily, weekly, monthly, yearly
interval_count INTEGER -- 1..365, default 1; "every N <frequency>" (Phase 08 migration)
start_date DATE
end_date DATE nullable
next_run_at TIMESTAMPTZ
active BOOLEAN
note TEXT
created_at
updated_at
deleted_at

### reminders
id UUID PK
user_id UUID
contact_id UUID nullable
account_id UUID nullable
title TEXT
description TEXT
amount NUMERIC(18,2) nullable
remind_at TIMESTAMPTZ
repeat_rule TEXT nullable
is_completed BOOLEAN
notification_enabled BOOLEAN
created_at
updated_at
deleted_at

### notifications
id UUID PK
user_id UUID
title TEXT
body TEXT
type TEXT
reference_id UUID nullable
read_at TIMESTAMPTZ nullable
created_at

### sync_queue
Not created. The upload queue lives in the client's local database
(docs/07_OFFLINE_SYNC.md); a server-side queue is only needed if a server
process must replay writes, which no phase requires yet.

## Indexes
At minimum:
- transactions(user_id, transaction_date DESC)
- transactions(user_id, account_id, transaction_date DESC)
- transactions(category_id, user_id, transaction_date DESC) -- category_id leads so it also serves the category foreign key
- contact_transactions(user_id, contact_id, transaction_date DESC)
- reminders(user_id, remind_at)
- notifications(user_id, created_at DESC)
- budgets(user_id, category_id)

## Money rules
Use NUMERIC(18,2). Do not use double/float for persisted monetary values.

Every foreign key also has an index whose leading columns match it.

## Schema migrations
Every schema change must be a new migration. Never edit an already-applied migration in production.

Migrations live in `supabase/migrations/` and apply in filename order:

1. `20261006120000_foundation.sql` — `private` schema, `set_updated_at` trigger
   function, profiles, user_settings, signup trigger.
2. `20261006120100_finance_core.sql` — accounts, categories, contacts,
   transactions, contact_transactions, `private.can_use_category`.
3. `20261006120200_planning.sql` — budgets, recurring_transactions, reminders,
   notifications.
4. `20261006120300_seed_system_categories.sql` — 25 system categories with fixed
   ids (`c0000000-0000-4000-8000-000000000xxx`), re-runnable.
5. `20261007090000_delete_my_account.sql` (Phase 02) — `public.delete_my_account()`
   RPC for self-service account deletion (see docs/04_SECURITY_RLS.md).

6. `20261007100000_recurring_interval.sql` (Phase 08) — adds
   `recurring_transactions.interval_count` (default 1) so custom schedules such
   as "every 2 weeks" or "every 45 days" fit the existing frequency check. No
   new table; existing owner-only RLS policies cover the column. The app reads a
   missing column as 1 and only sends it when it is not 1, so everything except
   custom intervals works before the migration is applied.

### Phase 08 conventions (no schema change)
- Budget threshold events are rows in `notifications` with `type = 'budget_alert'`,
  `reference_id = budget id` and a deterministic id (UUID v5 of budget id, period
  start and threshold), inserted with ON CONFLICT DO NOTHING. The same event can
  never be stored twice.
- Transactions generated from a recurring rule use a deterministic id (UUID v5 of
  rule id and occurrence date) and are inserted only if absent.

Each migration enables RLS in the same file that creates the table, so a
partial apply never leaves a table exposed.

Cross-user checks: `supabase/checks/cross_user_isolation.sql` (see README).

## Implementation decisions (Phase 01)
- **Client-generated ids.** `id` is created on the device (UUID v4) for every
  offline-creatable row and is the idempotency key: uploads upsert on `id`.
  The spec's `transactions.client_id` was dropped as redundant, and
  `transactions.sync_status` was dropped because sync state is local-only
  (every server row is synced by definition).
- **Tombstones.** Every synced table has `deleted_at`; the app soft-deletes so
  deletes propagate. profiles, user_settings and notifications are not synced
  offline and have no `deleted_at`.
- **Server-assigned `updated_at`.** A trigger sets it to `now()` on insert and
  update, ignoring client values, so it is a safe pull cursor. `now()` is the
  transaction start time, so pulls must re-read a small overlap window.
- **Ownership.** `user_id` defaults to `auth.uid()`. References to a user's
  accounts/contacts are composite foreign keys on `(user_id, <ref>_id)`, so a
  row can never point at another user's data. Category references are checked
  by RLS via `private.can_use_category` (system or own) because system
  categories have no owner.
- **Delete behavior.** `user_id` cascades from `auth.users`: deleting the auth
  user removes all of their data. All other references are NO ACTION, so a
  referenced account/contact/category cannot be hard-deleted; the app
  soft-deletes instead.
- **Transfers.** `transfer_id` is required exactly for `transfer_in`/
  `transfer_out`. Unique indexes allow one leg of each type per transfer, on
  different accounts.
- **Constraints.** All amounts `> 0`, except `accounts.opening_balance`, which
  may be negative (cards, overdrafts). `contacts.opening_balance >= 0`, with
  direction in `opening_balance_type`.
- **Enumerated values** are CHECK constraints: account type, category type,
  transaction types, khata types, theme_mode, budget period_type,
  recurring type/frequency. `notifications.type`, `payment_method` and
  `repeat_rule` stay free text until their phases define them.
- **Profiles and settings** are created by the `on_auth_user_created` trigger;
  `profiles.full_name` comes from signup metadata key `full_name`.
