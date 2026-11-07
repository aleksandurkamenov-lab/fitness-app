-- Изпълни веднъж в Supabase → SQL Editor → New query → Run (нужно за v109: „Изтрий акаунта“).
-- Изтрива текущия потребител; profiles и snapshots се трият каскадно,
-- а клиентите на изтрит треньор остават без треньор (coach_id = null).
create or replace function delete_my_account() returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  delete from auth.users where id = auth.uid();
end $$;
revoke all on function delete_my_account() from public, anon;
grant execute on function delete_my_account() to authenticated;
