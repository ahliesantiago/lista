-- Phase 0 baseline: the complete schema as it exists today,
-- written as a single reproducible migration so the migration
-- history replays cleanly from an empty database going forward.

-- ===== identity: public.users, 1:1 with auth.users =====

create table public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique check (char_length(username) >= 3),
  preferred_name text,
  avatar_url text,
  website text,
  updated_at timestamptz
);

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

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

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

-- ===== multi-tenancy: spaces (households/teams) and membership =====

create table public.spaces (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.space_members (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'owner' check (role in ('owner', 'member')),
  created_at timestamptz not null default now(),
  unique (space_id, user_id)
);

alter table public.spaces enable row level security;
alter table public.space_members enable row level security;

-- security definer helper: avoids RLS self-recursion when policies need
-- "which spaces can the current user see" without querying space_members
-- from inside its own policy.
create or replace function public.my_space_ids()
returns setof uuid
language sql
security definer
set search_path = public
stable
as $$
  select space_id from public.space_members where user_id = auth.uid();
$$;

create policy "members can read their spaces"
  on public.spaces for select
  using (id in (select public.my_space_ids()));

create policy "members can read their memberships"
  on public.space_members for select
  using (space_id in (select public.my_space_ids()));

-- auto-provision a default space + owner membership for every new user.
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
  values (coalesce(new.raw_user_meta_data->>'space_name', 'Your Space'), new.id)
  returning id into new_space_id;

  insert into public.space_members (space_id, user_id, role)
  values (new_space_id, new.id, 'owner');

  return new;
end;
$$;

create trigger on_auth_user_created_space
  after insert on auth.users
  for each row execute function public.handle_new_user_space();
