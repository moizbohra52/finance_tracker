-- Loans and EMIs: money the user borrowed or lent, and each payment on it
-- split into principal and interest (docs/05_FINANCIAL_LOGIC.md). The loan
-- tables are the source of truth; the account movements and the interest
-- income/expense are derived rows in transactions, linked through the new
-- nullable loan_id column (as split_expense_id does for split expenses). A loan
-- never touches the khata: derived rows carry no contact_id.
--
-- Same conventions as 20261024100000_split_expenses.sql and
-- 20261023100000_savings_goals.sql: client UUID id, user_id defaulting to
-- auth.uid() with on delete cascade, created_at/updated_at (shared trigger),
-- deleted_at, RLS enabled, privileges revoked from anon, four owner-only
-- policies. References to the user's own rows are composite
-- (user_id, <ref>) -> parent (user_id, id); accounts, contacts and
-- transactions already have the (user_id, id) key they need.
--
-- Apply this before shipping the app version with loans. Until then loan and
-- loan_payment uploads fail and stay queued (they retry; nothing is lost),
-- transactions that carry a loan_id and loan reminders wait behind them, and
-- everything else keeps syncing because plain transactions and reminders are
-- sent without loan_id.
--
-- Not enforced here, only by the app: the payment splits match the loan's
-- calculation, and the derived rows match the payments. Offline edits upload
-- row by row, so a cross-row check would reject a valid sync.

-- ---------------------------------------------------------------------------
-- loans
-- ---------------------------------------------------------------------------
create table public.loans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  direction text not null check (direction in ('taken', 'given')),
  method text not null check (method in ('emi', 'monthly_interest')),
  -- The lender or borrower, or a label such as "HDFC Home Loan".
  name text not null check (btrim(name) <> '' and char_length(name) <= 80),
  contact_id uuid,
  -- Where the loan was received into or given from.
  account_id uuid not null,
  principal numeric(18, 2) not null check (principal > 0),
  -- Percent a year; a monthly rate is stored times 12 (2% a month = 24).
  annual_rate numeric(7, 4) not null
    check (annual_rate >= 0 and annual_rate <= 60),
  tenure_months integer check (tenure_months between 1 and 480),
  emi_amount numeric(18, 2) check (emi_amount > 0),
  -- When the money moved; interest runs from here.
  start_date date not null,
  first_due_date date,
  -- False for a loan entered part way through, so today's balance is kept.
  moved_money boolean not null default true,
  -- Set when nothing is owed; cleared if that payment is removed.
  closed_at timestamptz,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, id),
  check (first_due_date is null or first_due_date >= start_date),
  check (
    (method = 'emi'
      and tenure_months is not null
      and emi_amount is not null
      and first_due_date is not null)
    or (method = 'monthly_interest'
      and tenure_months is null
      and emi_amount is null
      and first_due_date is null)
  ),
  foreign key (user_id, contact_id)
    references public.contacts (user_id, id),
  foreign key (user_id, account_id)
    references public.accounts (user_id, id)
);

create trigger set_updated_at
  before insert or update on public.loans
  for each row execute function private.set_updated_at();

create index loans_user_idx on public.loans (user_id);
create index loans_contact_idx
  on public.loans (contact_id) where contact_id is not null;
create index loans_account_idx on public.loans (account_id);

-- ---------------------------------------------------------------------------
-- loan_payments: scheduled is an EMI (or a repayment of a monthly-interest
-- loan); extra is a prepayment or the closing payment. The split is stored
-- when the payment is saved and never recalculated.
-- ---------------------------------------------------------------------------
create table public.loan_payments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  loan_id uuid not null,
  account_id uuid not null,
  kind text not null check (kind in ('scheduled', 'extra')),
  paid_at timestamptz not null,
  amount numeric(18, 2) not null check (amount > 0),
  principal_part numeric(18, 2) not null check (principal_part >= 0),
  interest_part numeric(18, 2) not null check (interest_part >= 0),
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, id),
  check (principal_part + interest_part = amount),
  foreign key (user_id, loan_id)
    references public.loans (user_id, id),
  foreign key (user_id, account_id)
    references public.accounts (user_id, id)
);

create trigger set_updated_at
  before insert or update on public.loan_payments
  for each row execute function private.set_updated_at();

create index loan_payments_user_idx on public.loan_payments (user_id);
create index loan_payments_loan_idx on public.loan_payments (user_id, loan_id);
create index loan_payments_account_idx on public.loan_payments (account_id);

-- ---------------------------------------------------------------------------
-- Link columns on the derived rows
-- ---------------------------------------------------------------------------
alter table public.transactions add column loan_id uuid;
alter table public.transactions
  add foreign key (user_id, loan_id)
    references public.loans (user_id, id);
create index transactions_loan_idx
  on public.transactions (loan_id) where loan_id is not null;

alter table public.reminders add column loan_id uuid;
alter table public.reminders
  add foreign key (user_id, loan_id)
    references public.loans (user_id, id);
create index reminders_loan_idx
  on public.reminders (loan_id) where loan_id is not null;

-- 'loan' joins the reminder types. Assumption: Postgres auto-named the inline
-- column check in 20261008090000_reminders_notifications.sql
-- "<table>_<column>_check", i.e. reminders_reminder_type_check; if it was
-- named otherwise, drop it by its real name first or both checks will apply.
alter table public.reminders
  drop constraint if exists reminders_reminder_type_check,
  add constraint reminders_reminder_type_check
    check (reminder_type in (
      'payment', 'receivable', 'payable', 'khata', 'recurring', 'custom',
      'loan'
    ));

-- ---------------------------------------------------------------------------
-- System categories of the derived rows. Ids are fixed so the app's local
-- database seeds identical rows offline; system_key is unique
-- (20261030100000_category_system_keys.sql).
-- ---------------------------------------------------------------------------
insert into public.categories (id, user_id, name, type, icon, is_system, system_key)
values
  ('c0000000-0000-4000-8000-000000000110', null, 'Loan Received', 'income', 'borrowed', true, 'loan_taken'),
  ('c0000000-0000-4000-8000-000000000111', null, 'Loan Repayment Received', 'income', 'repayment_received', true, 'loan_repayment_received'),
  ('c0000000-0000-4000-8000-000000000112', null, 'Loan Interest Received', 'income', 'interest', true, 'loan_interest_received'),
  ('c0000000-0000-4000-8000-000000000221', null, 'Loan Given', 'expense', 'lent', true, 'loan_given'),
  ('c0000000-0000-4000-8000-000000000222', null, 'Loan Repayment', 'expense', 'emi', true, 'loan_repayment_made'),
  ('c0000000-0000-4000-8000-000000000223', null, 'Loan Interest Paid', 'expense', 'emi', true, 'loan_interest_paid')
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- RLS: owner-only, like every user table
-- ---------------------------------------------------------------------------
alter table public.loans enable row level security;
alter table public.loan_payments enable row level security;

revoke all on table public.loans from anon, authenticated;
revoke all on table public.loan_payments from anon, authenticated;

grant select, insert, update, delete on table public.loans to authenticated;
grant select, insert, update, delete on table public.loan_payments
  to authenticated;

create policy "Users can view their own loans"
  on public.loans for select to authenticated
  using (user_id = (select auth.uid()));
create policy "Users can create their own loans"
  on public.loans for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "Users can update their own loans"
  on public.loans for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "Users can delete their own loans"
  on public.loans for delete to authenticated
  using (user_id = (select auth.uid()));

create policy "Users can view their own loan payments"
  on public.loan_payments for select to authenticated
  using (user_id = (select auth.uid()));
create policy "Users can create their own loan payments"
  on public.loan_payments for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "Users can update their own loan payments"
  on public.loan_payments for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "Users can delete their own loan payments"
  on public.loan_payments for delete to authenticated
  using (user_id = (select auth.uid()));
