-- Изпълни след като ТИ си се регистрирал първи в приложението.
-- Прави първия регистриран акаунт главен треньор; всеки нов акаунт автоматично става негов клиент.
alter table profiles add column if not exists is_coach boolean not null default false;

update profiles set is_coach = true
where id = (select id from auth.users order by created_at limit 1);

create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles(id, display_name, coach_id)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', ''),
          (select id from profiles where is_coach limit 1));
  return new;
end $$;
