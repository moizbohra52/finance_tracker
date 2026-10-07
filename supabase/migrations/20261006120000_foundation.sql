-- Foundation: private helper schema, profiles, user settings, and the signup
-- trigger that creates both for every new auth user.
-- See docs/03_DATABASE_SCHEMA.md and docs/04_SECURITY_RLS.md.

-- Helpers live outside the API-exposed schemas so PostgREST never serves them.
create schema if not exists private;
grant usage on schema private to authenticated;

-- updated_at is always server time, on insert as well as update. Offline
-- devices can have skewed clocks; a server-assigned value keeps updated_at
-- usable as an incremental sync cursor (docs/07_OFFLINE_SYNC.md).
create function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- profiles: one row per auth user, keyed by the auth user id.
-- ---------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text,
  mobile text,
  avatar_url text,
  currency_code text not null default 'INR'
    check (currency_code ~ '^[A-Z]{3}$'),
  timezone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger set_updated_at
  before insert or update on public.profiles
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- user_settings: one row per auth user.
-- ---------------------------------------------------------------------------
create table public.user_settings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users (id) on delete cascade,
  theme_mode text not null default 'system'
    check (theme_mode in ('light', 'dark', 'system')),
  accent_color text,
  language_code text not null default 'en',
  date_format text,
  number_format text,
  notifications_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger set_updated_at
  before insert or update on public.user_settings
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- Row level security. Rows are created by the signup trigger and removed by
-- the auth.users cascade, so clients may only read and update their own row.
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.user_settings enable row level security;

revoke all on table public.profiles, public.user_settings from anon, authenticated;
grant select, update on table public.profiles, public.user_settings to authenticated;

create policy "Users can view their own profile"
  on public.profiles for select to authenticated
  using (id = (select auth.uid()));

create policy "Users can update their own profile"
  on public.profiles for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

create policy "Users can view their own settings"
  on public.user_settings for select to authenticated
  using (user_id = (select auth.uid()));

create policy "Users can update their own settings"
  on public.user_settings for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- Signup trigger. Security definer because the inserting role (Supabase Auth)
-- has no rights on public tables. full_name comes from the signup metadata
-- (`data: {'full_name': ...}` in supabase.auth.signUp).
-- ---------------------------------------------------------------------------
create function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''));

  insert into public.user_settings (user_id)
  values (new.id);

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- Users who signed up before this migration (none on a fresh project).
insert into public.profiles (id)
select id from auth.users
on conflict (id) do nothing;

insert into public.user_settings (user_id)
select id from auth.users
on conflict (user_id) do nothing;
