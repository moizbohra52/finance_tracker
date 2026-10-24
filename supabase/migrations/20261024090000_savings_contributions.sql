-- Savings contributions: the part of one income transaction that the user put
-- towards a savings goal. A contribution records the split only; it never
-- moves money or changes the income amount or an account balance
-- (docs/05_FINANCIAL_LOGIC.md). Same conventions as
-- 20261006120100_finance_core.sql: composite foreign keys on (user_id, <ref>),
-- default NO ACTION delete, soft deletes through deleted_at.
--
-- Apply this before shipping the app version that syncs it, or its sync
-- fails on the unknown table.
--
-- Not enforced here, only by the app: the contributions of one transaction add
-- up to at most its amount, and the transaction is an income. Offline edits
-- upload row by row, so a check would reject a valid sync.

-- The composite foreign key below needs this key on the goals table
-- (transactions already has one, from 20261008090000).
alter table public.savings_goals
  add constraint savings_goals_user_id_id_key unique (user_id, id);

create table public.savings_contributions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  transaction_id uuid not null,
  goal_id uuid not null,
  amount numeric(18, 2) not null check (amount > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  foreign key (user_id, transaction_id)
    references public.transactions (user_id, id),
  foreign key (user_id, goal_id) references public.savings_goals (user_id, id)
);

-- One index per foreign key.
create index savings_contributions_user_tx_idx
  on public.savings_contributions (user_id, transaction_id);
create index savings_contributions_user_goal_idx
  on public.savings_contributions (user_id, goal_id);

-- A goal appears once per transaction; removed rows are tombstones and do
-- not count.
create unique index savings_contributions_live_key
  on public.savings_contributions (transaction_id, goal_id)
  where deleted_at is null;

create trigger set_updated_at
  before insert or update on public.savings_contributions
  for each row execute function private.set_updated_at();

alter table public.savings_contributions enable row level security;

revoke all on table public.savings_contributions from anon, authenticated;
grant select, insert, update, delete on table public.savings_contributions
  to authenticated;

create policy "Users can view their own savings contributions"
  on public.savings_contributions for select to authenticated
  using (user_id = (select auth.uid()));
create policy "Users can create their own savings contributions"
  on public.savings_contributions for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "Users can update their own savings contributions"
  on public.savings_contributions for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "Users can delete their own savings contributions"
  on public.savings_contributions for delete to authenticated
  using (user_id = (select auth.uid()));
