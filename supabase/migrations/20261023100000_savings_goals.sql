-- Savings goals: money the user is putting aside for something (a phone, a
-- trip, an emergency fund). saved_amount is updated by hand; a goal never
-- moves money or changes an account balance (docs/05_FINANCIAL_LOGIC.md).
-- Same conventions as 20261006120200_planning.sql.
--
-- Apply this before shipping the app version with savings goals, or their
-- sync fails on the unknown table.

create table public.savings_goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  name text not null check (btrim(name) <> ''),
  target_amount numeric(18, 2) not null check (target_amount > 0),
  saved_amount numeric(18, 2) not null default 0 check (saved_amount >= 0),
  -- Optional calendar day the user wants to reach the target by.
  target_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index savings_goals_user_idx on public.savings_goals (user_id);

create trigger set_updated_at
  before insert or update on public.savings_goals
  for each row execute function private.set_updated_at();

alter table public.savings_goals enable row level security;

revoke all on table public.savings_goals from anon, authenticated;
grant select, insert, update, delete on table public.savings_goals
  to authenticated;

create policy "Users can view their own savings goals"
  on public.savings_goals for select to authenticated
  using (user_id = (select auth.uid()));
create policy "Users can create their own savings goals"
  on public.savings_goals for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "Users can update their own savings goals"
  on public.savings_goals for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "Users can delete their own savings goals"
  on public.savings_goals for delete to authenticated
  using (user_id = (select auth.uid()));
