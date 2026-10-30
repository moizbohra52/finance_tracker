-- A stable key on the system categories the app uses for a purpose, so the
-- app asks for "the khata_lent category" instead of carrying category ids
-- (docs/03_DATABASE_SCHEMA.md). Today: the four categories of the account
-- rows of khata entries, seeded by 20261030090000_photos_and_khata_categories.
--
-- Only system rows carry a key (a user's own category cannot take one), and
-- a key names one row. Apply after 20261030090000. Until then the app finds
-- no key and saves those rows without a category; nothing else changes.

alter table public.categories add column if not exists system_key text;

alter table public.categories
  add constraint categories_system_key_check
  check (system_key is null or is_system);

create unique index if not exists categories_system_key_idx
  on public.categories (system_key)
  where system_key is not null;

update public.categories set system_key = 'khata_lent'
  where id = 'c0000000-0000-4000-8000-000000000219';
update public.categories set system_key = 'khata_repayment_made'
  where id = 'c0000000-0000-4000-8000-000000000220';
update public.categories set system_key = 'khata_borrowed'
  where id = 'c0000000-0000-4000-8000-000000000108';
update public.categories set system_key = 'khata_repayment_received'
  where id = 'c0000000-0000-4000-8000-000000000109';
