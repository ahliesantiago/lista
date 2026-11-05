-- Phase 3: Inventory / Pantry.
-- storage_locations (room-grouped master list) + pantry_items (location <-> item
-- stock) + appliances (standalone inventory list with maintenance/replace flags).

create table public.storage_locations (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces(id) on delete cascade,
  name text not null,
  room text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create unique index storage_locations_space_id_name_key
  on public.storage_locations (space_id, name)
  where deleted_at is null;

create table public.pantry_items (
  id uuid primary key default gen_random_uuid(),
  storage_location_id uuid not null references public.storage_locations(id) on delete cascade,
  item_id uuid not null references public.items(id) on delete cascade,
  stock_status text check (stock_status in ('in_stock', 'low', 'out')),
  quantity numeric,
  unit_id uuid references public.units(id) on delete set null,
  notes text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.appliances (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces(id) on delete cascade,
  name text not null,
  brand text,
  quantity integer not null default 1,
  needs_maintenance boolean not null default false,
  needs_replacement boolean not null default false,
  notes text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table public.storage_locations enable row level security;
alter table public.pantry_items enable row level security;
alter table public.appliances enable row level security;

create policy "members manage storage_locations" on public.storage_locations
  for all
  using (space_id in (select public.my_space_ids()))
  with check (space_id in (select public.my_space_ids()));

create policy "members manage pantry_items" on public.pantry_items
  for all
  using (exists (
    select 1 from public.storage_locations sl
    where sl.id = pantry_items.storage_location_id
    and sl.space_id in (select public.my_space_ids())
  ))
  with check (exists (
    select 1 from public.storage_locations sl
    where sl.id = pantry_items.storage_location_id
    and sl.space_id in (select public.my_space_ids())
  ));

create policy "members manage appliances" on public.appliances
  for all
  using (space_id in (select public.my_space_ids()))
  with check (space_id in (select public.my_space_ids()));
