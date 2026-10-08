-- Phase 10: profile and settings.
--
-- user_settings gains the account-level preferences that are not yet stored:
-- first day of the week and the default account. The formats get CHECK
-- constraints so the database rejects values the app cannot display.
-- Existing rows are unaffected: every new column is nullable or has a default,
-- and the CHECKs accept NULL.
--
-- Avatars live in a PRIVATE storage bucket. Each user can only reach objects
-- under their own user id folder; the app shows them through short-lived
-- signed links, never public URLs.

-- ---------------------------------------------------------------------------
-- user_settings
-- ---------------------------------------------------------------------------
alter table public.user_settings
  add column first_day_of_week text not null default 'monday'
    check (first_day_of_week in ('monday', 'sunday')),
  add column default_account_id uuid,
  add constraint user_settings_default_account_fkey
    foreign key (user_id, default_account_id)
    references public.accounts (user_id, id),
  add constraint user_settings_date_format_check
    check (date_format is null or date_format in (
      'd MMM y', 'dd/MM/yyyy', 'MM/dd/yyyy', 'yyyy-MM-dd'
    )),
  add constraint user_settings_number_format_check
    check (number_format is null or number_format in ('indian', 'international')),
  add constraint user_settings_language_code_check
    check (language_code in ('en'));

-- Every foreign key has an index led by its columns (docs/03_DATABASE_SCHEMA.md).
create index user_settings_default_account_idx
  on public.user_settings (user_id, default_account_id)
  where default_account_id is not null;

-- ---------------------------------------------------------------------------
-- avatars bucket: private, images only, 2 MiB per file.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'avatars', 'avatars', false, 2097152,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Object names are "<user id>/<file>", so the first folder is the owner.
create policy "Users can read their own avatars"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "Users can upload their own avatars"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "Users can update their own avatars"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "Users can delete their own avatars"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
