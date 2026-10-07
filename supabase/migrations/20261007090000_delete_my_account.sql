-- Self-service account deletion (docs/04_SECURITY_RLS.md, Account deletion).
--
-- Deletes the caller's auth user; every user-owned table cascades from
-- auth.users, so all of the user's data goes with it. Security definer because
-- clients have no rights on auth.users; it can only ever delete auth.uid().
--
-- Requires a password sign-in within the last 5 minutes (the JWT `amr`
-- claim), so a stolen session or refresh token alone cannot delete the
-- account. The app re-authenticates with the password right before calling.
create function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
begin
  if caller_id is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from jsonb_array_elements(coalesce(auth.jwt() -> 'amr', '[]'::jsonb)) as method
    where method ->> 'method' = 'password'
      and (method ->> 'timestamp')::bigint
        >= extract(epoch from now() - interval '5 minutes')
  ) then
    raise exception 'Recent password sign-in required'
      using errcode = '42501', hint = 'reauthentication_required';
  end if;

  delete from auth.users where id = caller_id;
end;
$$;

revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
