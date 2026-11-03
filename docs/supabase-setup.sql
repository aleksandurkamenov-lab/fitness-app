-- Изпълни веднъж в Supabase → SQL Editor → New query → Run.
create table if not exists profiles (
  id uuid primary key references auth.users on delete cascade,
  display_name text not null default '',
  code text unique not null default upper(substr(md5(random()::text), 1, 6)),
  coach_id uuid references profiles(id) on delete set null
);
create table if not exists snapshots (
  user_id uuid primary key references profiles(id) on delete cascade,
  updated_at timestamptz not null default now(),
  data jsonb not null
);

create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles(id, display_name) values (new.id, coalesce(new.raw_user_meta_data->>'name', ''));
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

alter table profiles enable row level security;
alter table snapshots enable row level security;

create policy "profiles_read" on profiles for select
  using (id = auth.uid() or coach_id = auth.uid());
create policy "profiles_update_own" on profiles for update
  using (id = auth.uid()) with check (id = auth.uid());
-- Клиентът може да сменя само името; връзката с треньор става през функциите долу.
revoke update on profiles from authenticated;
grant update (display_name) on profiles to authenticated;

create policy "snapshots_read" on snapshots for select using (
  user_id = auth.uid()
  or exists (select 1 from profiles p where p.id = snapshots.user_id and p.coach_id = auth.uid())
);
create policy "snapshots_insert_own" on snapshots for insert with check (user_id = auth.uid());
create policy "snapshots_update_own" on snapshots for update
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create or replace function link_coach(c text) returns boolean
language plpgsql security definer set search_path = public as $$
declare cid uuid;
begin
  select id into cid from profiles where code = upper(trim(c)) and id <> auth.uid();
  if cid is null then return false; end if;
  update profiles set coach_id = cid where id = auth.uid();
  return true;
end $$;

create or replace function unlink_coach() returns void
language sql security definer set search_path = public as $$
  update profiles set coach_id = null where id = auth.uid();
$$;
