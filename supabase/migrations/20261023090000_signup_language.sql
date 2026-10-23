-- A new account starts in the language chosen on the signed-out screens.
--
-- The app sends it as `language_code` in the signup metadata, next to
-- full_name. Only the codes user_settings accepts are taken
-- (20261021110000_language_codes.sql); anything else, or none, keeps 'en'.
-- The rest of the function is unchanged from 20261006120000_foundation.sql.
--
-- Until this runs, new accounts start in English and the user picks their
-- language again in Settings. Apply after 20261021110000_language_codes.sql.

create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  requested text := new.raw_user_meta_data ->> 'language_code';
begin
  insert into public.profiles (id, full_name)
  values (new.id, nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''));

  insert into public.user_settings (user_id, language_code)
  values (
    new.id,
    case when requested in ('en', 'hi', 'hi-Latn') then requested else 'en' end
  );

  return new;
end;
$$;
