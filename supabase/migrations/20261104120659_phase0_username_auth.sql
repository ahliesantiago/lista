-- Phase 0 addendum: username-based signup/login support.
-- Requires the pre-existing test user (no username) to be deleted first,
-- since username becomes NOT NULL below.

alter table public.profiles rename column full_name to preferred_name;
alter table public.profiles alter column username set not null;

-- Consolidate the old, auth-disconnected public.users (bigint, no link to
-- auth.users) into public.profiles, then rename profiles -> users. Confirmed
-- empty/no-real-data tables, so created_by/owner are dropped and recreated
-- as uuid rather than data-migrated (no mapping from old bigint ids to real
-- auth identities exists anyway).
alter table public.items drop column created_by;
alter table public.item_categories drop column created_by;
alter table public.list_types drop column created_by;
alter table public.units drop column created_by;
alter table public.lists drop column owner;

drop table public.users;

alter table public.profiles rename to users;

alter table public.items add column created_by uuid references public.users(id) on delete set null;
alter table public.item_categories add column created_by uuid references public.users(id) on delete set null;
alter table public.list_types add column created_by uuid references public.users(id) on delete set null;
alter table public.units add column created_by uuid references public.users(id) on delete set null;
alter table public.lists add column owner uuid not null references public.users(id) on delete cascade;

create or replace function public.handle_new_user()
returns trigger
set search_path = ''
language plpgsql
security definer
as $$
begin
  insert into public.users (id, username, preferred_name, avatar_url)
  values (
    new.id,
    new.raw_user_meta_data->>'username',
    new.raw_user_meta_data->>'preferred_name',
    new.raw_user_meta_data->>'avatar_url'
  );
  return new;
end;
$$;

create or replace function public.handle_new_user_space()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  new_space_id uuid;
begin
  insert into public.spaces (name, created_by)
  values (coalesce(new.raw_user_meta_data->>'space_name', 'My Space'), new.id)
  returning id into new_space_id;

  insert into public.space_members (space_id, user_id, role)
  values (new_space_id, new.id, 'owner');

  return new;
end;
$$;

-- resolves a login identifier that might be a username (no "@") to the
-- account's real auth email, so the client can always call
-- signInWithPassword with an actual email regardless of what the user typed.
create or replace function public.resolve_login_email(identifier text)
returns text
language sql
security definer
stable
set search_path = public
as $$
  select au.email
  from public.users pu
  join auth.users au on au.id = pu.id
  where pu.username = identifier
  limit 1;
$$;

grant execute on function public.resolve_login_email(text) to anon, authenticated;
