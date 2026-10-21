-- Receipt photos of transactions.
--
-- A PRIVATE storage bucket. Object names are "<user id>/<transaction id>",
-- so the first folder is the owner, exactly like the avatars bucket. The app
-- shows a receipt through a short-lived signed link, never a public URL.
-- transactions.attachment_url (already in 20261006120100_finance_core.sql)
-- stores the object name. No table change.
--
-- Apply before shipping the app version with receipts. Without the bucket,
-- uploads fail and photos stay queued on the phone; nothing is lost.

-- ---------------------------------------------------------------------------
-- receipts bucket: private, images only, 2 MiB per file.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'receipts', 'receipts', false, 2097152,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

create policy "Users can read their own receipts"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'receipts'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "Users can upload their own receipts"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'receipts'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "Users can update their own receipts"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'receipts'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'receipts'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "Users can delete their own receipts"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'receipts'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
