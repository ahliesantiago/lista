-- Phase 3 polish: per-room location uniqueness, optional pantry location
-- (requires giving the renamed inventory_items its own space_id for RLS),
-- pantry/household split via a `kind` column, and a new flat `furniture`
-- table. Also renames pantry_items -> inventory_items now that the table
-- covers both pantry and household (non-food) stock.

-- #1: uniqueness becomes per-room instead of space-wide
drop index public.storage_locations_space_id_name_key;
create unique index storage_locations_space_id_name_room_key
  on public.storage_locations (space_id, name, room)
  where deleted_at is null;

-- rename pantry_items -> inventory_items (policy carries over, renamed for clarity)
alter table public.pantry_items rename to inventory_items;
alter policy "members manage pantry_items" on public.inventory_items rename to "members manage inventory_items";

-- #2: inventory_items gets its own space_id so storage_location_id can
-- become optional (the old RLS policy went through storage_locations via an
-- exists() join, which would silently deny access to any row with no
-- location once that column is nullable)
alter table public.inventory_items add column space_id uuid references public.spaces(id) on delete cascade;

update public.inventory_items ii
set space_id = sl.space_id
from public.storage_locations sl
where sl.id = ii.storage_location_id;

alter table public.inventory_items alter column space_id set not null;
alter table public.inventory_items alter column storage_location_id drop not null;

drop policy "members manage inventory_items" on public.inventory_items;
create policy "members manage inventory_items" on public.inventory_items
  for all
  using (space_id in (select public.my_space_ids()))
  with check (space_id in (select public.my_space_ids()));

-- #3: pantry vs. household-inventory split (same table, filtered by kind)
alter table public.inventory_items add column kind text not null default 'pantry'
  check (kind in ('pantry', 'household'));

-- #3: furniture - flat list like appliances, plus a free-text room label
create table public.furniture (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces(id) on delete cascade,
  name text not null,
  brand text,
  room text,
  quantity integer not null default 1,
  needs_maintenance boolean not null default false,
  needs_replacement boolean not null default false,
  notes text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table public.furniture enable row level security;

create policy "members manage furniture" on public.furniture
  for all
  using (space_id in (select public.my_space_ids()))
  with check (space_id in (select public.my_space_ids()));
