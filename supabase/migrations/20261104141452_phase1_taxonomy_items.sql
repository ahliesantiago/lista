-- Phase 1: shared household taxonomy (categories, tags, units + conversions)
-- and items, all space-scoped. First tables with real user-driven CRUD, so
-- this establishes the space_id RLS write-policy pattern every later phase
-- reuses: one `for all` policy per table keyed off my_space_ids().

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces(id) on delete cascade,
  name text not null,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  unique (space_id, name)
);

create table public.tags (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces(id) on delete cascade,
  name text not null,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  unique (space_id, name)
);

create table public.units (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces(id) on delete cascade,
  name_singular text not null,
  name_plural text not null,
  abbrev_singular text,
  abbrev_plural text,
  unit_type text not null default 'other' check (unit_type in ('count', 'volume', 'weight', 'other')),
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  unique (space_id, name_singular)
);

create table public.unit_conversions (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces(id) on delete cascade,
  from_unit_id uuid not null references public.units(id) on delete cascade,
  to_unit_id uuid not null references public.units(id) on delete cascade,
  factor numeric not null,
  created_at timestamptz not null default now(),
  unique (space_id, from_unit_id, to_unit_id),
  check (from_unit_id <> to_unit_id)
);

create table public.items (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces(id) on delete cascade,
  name text not null,
  plural_name text,
  category_id uuid references public.categories(id) on delete set null,
  default_unit_id uuid references public.units(id) on delete set null,
  price numeric,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (space_id, name)
);

create table public.item_tags (
  item_id uuid not null references public.items(id) on delete cascade,
  tag_id uuid not null references public.tags(id) on delete cascade,
  primary key (item_id, tag_id)
);

create table public.item_units (
  item_id uuid not null references public.items(id) on delete cascade,
  unit_id uuid not null references public.units(id) on delete cascade,
  primary key (item_id, unit_id)
);

alter table public.categories enable row level security;
alter table public.tags enable row level security;
alter table public.units enable row level security;
alter table public.unit_conversions enable row level security;
alter table public.items enable row level security;
alter table public.item_tags enable row level security;
alter table public.item_units enable row level security;

create policy "members manage categories" on public.categories
  for all
  using (space_id in (select public.my_space_ids()))
  with check (space_id in (select public.my_space_ids()));

create policy "members manage tags" on public.tags
  for all
  using (space_id in (select public.my_space_ids()))
  with check (space_id in (select public.my_space_ids()));

create policy "members manage units" on public.units
  for all
  using (space_id in (select public.my_space_ids()))
  with check (space_id in (select public.my_space_ids()));

create policy "members manage unit_conversions" on public.unit_conversions
  for all
  using (space_id in (select public.my_space_ids()))
  with check (space_id in (select public.my_space_ids()));

create policy "members manage items" on public.items
  for all
  using (space_id in (select public.my_space_ids()))
  with check (space_id in (select public.my_space_ids()));

create policy "members manage item_tags" on public.item_tags
  for all
  using (exists (
    select 1 from public.items i
    where i.id = item_tags.item_id
    and i.space_id in (select public.my_space_ids())
  ))
  with check (exists (
    select 1 from public.items i
    where i.id = item_tags.item_id
    and i.space_id in (select public.my_space_ids())
  ));

create policy "members manage item_units" on public.item_units
  for all
  using (exists (
    select 1 from public.items i
    where i.id = item_units.item_id
    and i.space_id in (select public.my_space_ids())
  ))
  with check (exists (
    select 1 from public.items i
    where i.id = item_units.item_id
    and i.space_id in (select public.my_space_ids())
  ));
