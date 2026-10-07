-- Planning and alerts: budgets, recurring transactions, reminders and the
-- notification center. Same conventions as 20261006120100_finance_core.sql.

-- ---------------------------------------------------------------------------
-- budgets
-- ---------------------------------------------------------------------------
create table public.budgets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  -- Null means an overall budget across all expense categories.
  category_id uuid references public.categories (id),
  amount numeric(18, 2) not null check (amount > 0),
  period_type text not null check (period_type in ('monthly', 'custom')),
  start_date date not null,
  end_date date,
  alert_75 boolean not null default true,
  alert_90 boolean not null default true,
  alert_100 boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint budgets_date_range_check
    check (end_date is null or end_date >= start_date),
  constraint budgets_custom_end_date_check
    check (period_type <> 'custom' or end_date is not null)
);

create index budgets_user_category_idx
  on public.budgets (user_id, category_id);
create index budgets_category_idx
  on public.budgets (category_id)
  where category_id is not null;

create trigger set_updated_at
  before insert or update on public.budgets
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- recurring_transactions: templates that generate income/expense entries.
-- ---------------------------------------------------------------------------
create table public.recurring_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  account_id uuid not null,
  category_id uuid references public.categories (id),
  type text not null check (type in ('income', 'expense')),
  amount numeric(18, 2) not null check (amount > 0),
  frequency text not null
    check (frequency in ('daily', 'weekly', 'monthly', 'yearly')),
  start_date date not null,
  end_date date,
  next_run_at timestamptz not null,
  active boolean not null default true,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  foreign key (user_id, account_id) references public.accounts (user_id, id),
  constraint recurring_transactions_date_range_check
    check (end_date is null or end_date >= start_date)
);

create index recurring_transactions_user_account_idx
  on public.recurring_transactions (user_id, account_id);
create index recurring_transactions_category_idx
  on public.recurring_transactions (category_id)
  where category_id is not null;

create trigger set_updated_at
  before insert or update on public.recurring_transactions
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- reminders
-- ---------------------------------------------------------------------------
create table public.reminders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  contact_id uuid,
  account_id uuid,
  title text not null check (btrim(title) <> ''),
  description text,
  amount numeric(18, 2) check (amount > 0),
  remind_at timestamptz not null,
  repeat_rule text,
  is_completed boolean not null default false,
  notification_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  foreign key (user_id, contact_id) references public.contacts (user_id, id),
  foreign key (user_id, account_id) references public.accounts (user_id, id)
);

create index reminders_user_remind_at_idx
  on public.reminders (user_id, remind_at);
create index reminders_user_contact_idx
  on public.reminders (user_id, contact_id)
  where contact_id is not null;
create index reminders_user_account_idx
  on public.reminders (user_id, account_id)
  where account_id is not null;

create trigger set_updated_at
  before insert or update on public.reminders
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- notifications: persisted notification center entries. Not synced offline,
-- so no updated_at/deleted_at.
-- ---------------------------------------------------------------------------
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  title text not null check (btrim(title) <> ''),
  body text,
  type text not null,
  -- Id of the related reminder/contact/transaction/budget for deep links.
  reference_id uuid,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index notifications_user_created_idx
  on public.notifications (user_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------
alter table public.budgets enable row level security;
alter table public.recurring_transactions enable row level security;
alter table public.reminders enable row level security;
alter table public.notifications enable row level security;

revoke all on table
  public.budgets, public.recurring_transactions,
  public.reminders, public.notifications
from anon, authenticated;
grant select, insert, update, delete on table
  public.budgets, public.recurring_transactions,
  public.reminders, public.notifications
to authenticated;

-- budgets
create policy "Users can view their own budgets"
  on public.budgets for select to authenticated
  using (user_id = (select auth.uid()));
create policy "Users can create their own budgets"
  on public.budgets for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and private.can_use_category(category_id)
  );
create policy "Users can update their own budgets"
  on public.budgets for update to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and private.can_use_category(category_id)
  );
create policy "Users can delete their own budgets"
  on public.budgets for delete to authenticated
  using (user_id = (select auth.uid()));

-- recurring_transactions
create policy "Users can view their own recurring transactions"
  on public.recurring_transactions for select to authenticated
  using (user_id = (select auth.uid()));
create policy "Users can create their own recurring transactions"
  on public.recurring_transactions for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and private.can_use_category(category_id)
  );
create policy "Users can update their own recurring transactions"
  on public.recurring_transactions for update to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and private.can_use_category(category_id)
  );
create policy "Users can delete their own recurring transactions"
  on public.recurring_transactions for delete to authenticated
  using (user_id = (select auth.uid()));

-- reminders
create policy "Users can view their own reminders"
  on public.reminders for select to authenticated
  using (user_id = (select auth.uid()));
create policy "Users can create their own reminders"
  on public.reminders for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "Users can update their own reminders"
  on public.reminders for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "Users can delete their own reminders"
  on public.reminders for delete to authenticated
  using (user_id = (select auth.uid()));

-- notifications
create policy "Users can view their own notifications"
  on public.notifications for select to authenticated
  using (user_id = (select auth.uid()));
create policy "Users can create their own notifications"
  on public.notifications for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "Users can update their own notifications"
  on public.notifications for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "Users can delete their own notifications"
  on public.notifications for delete to authenticated
  using (user_id = (select auth.uid()));
