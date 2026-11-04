-- Phase 0: spaces (households/teams) and membership, with auto-provisioning on signup.

create table if not exists public.spaces (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.space_members (
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
-- named distinctly from the existing handle_new_user()/on_auth_user_created
-- (the profiles-row-creation trigger already set up) so both triggers run
-- independently on auth.users insert without colliding.
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
  values ('My Space', new.id)
  returning id into new_space_id;

  insert into public.space_members (space_id, user_id, role)
  values (new_space_id, new.id, 'owner');

  return new;
end;
$$;

create trigger on_auth_user_created_space
  after insert on auth.users
  for each row execute function public.handle_new_user_space();
