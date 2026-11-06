-- Recipe polish round:
-- 1) Recipes get their own dedicated, hierarchical categories/tags, fully
--    separate from items' shared categories/tags (same reasoning as
--    equipment vs. appliances). The old recipe_categories/recipe_tags join
--    tables (which pointed at the shared taxonomy) are dropped and replaced
--    by new join tables with different names, since the *new* names
--    recipe_categories/recipe_tags are now taken by the new master lists.
-- 2) Equipment and inventory_items (pantry/home-inventory) each get up to 2
--    Locations and up to 2 Rooms via independent join tables; the old single
--    inventory_items.storage_location_id column is superseded and dropped.

drop table public.recipe_categories;
drop table public.recipe_tags;

create table public.recipe_categories (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces(id) on delete cascade,
  name text not null,
  parent_id uuid references public.recipe_categories(id) on delete cascade,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create unique index recipe_categories_space_id_name_key
  on public.recipe_categories (space_id, name)
  where deleted_at is null;

create table public.recipe_tags (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces(id) on delete cascade,
  name text not null,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create unique index recipe_tags_space_id_name_key
  on public.recipe_tags (space_id, name)
  where deleted_at is null;

create table public.recipe_category_links (
  recipe_id uuid not null references public.recipes(id) on delete cascade,
  category_id uuid not null references public.recipe_categories(id) on delete cascade,
  primary key (recipe_id, category_id)
);

create table public.recipe_tag_links (
  recipe_id uuid not null references public.recipes(id) on delete cascade,
  tag_id uuid not null references public.recipe_tags(id) on delete cascade,
  primary key (recipe_id, tag_id)
);

create table public.equipment_locations (
  equipment_id uuid not null references public.equipment(id) on delete cascade,
  storage_location_id uuid not null references public.storage_locations(id) on delete cascade,
  primary key (equipment_id, storage_location_id)
);

create table public.equipment_rooms (
  equipment_id uuid not null references public.equipment(id) on delete cascade,
  room_id uuid not null references public.rooms(id) on delete cascade,
  primary key (equipment_id, room_id)
);

create table public.inventory_item_locations (
  inventory_item_id uuid not null references public.inventory_items(id) on delete cascade,
  storage_location_id uuid not null references public.storage_locations(id) on delete cascade,
  primary key (inventory_item_id, storage_location_id)
);

create table public.inventory_item_rooms (
  inventory_item_id uuid not null references public.inventory_items(id) on delete cascade,
  room_id uuid not null references public.rooms(id) on delete cascade,
  primary key (inventory_item_id, room_id)
);

-- backfill the join table from the column it supersedes, then drop it
insert into public.inventory_item_locations (inventory_item_id, storage_location_id)
select id, storage_location_id from public.inventory_items where storage_location_id is not null;

alter table public.inventory_items drop column storage_location_id;

alter table public.recipe_categories enable row level security;
alter table public.recipe_tags enable row level security;
alter table public.recipe_category_links enable row level security;
alter table public.recipe_tag_links enable row level security;
alter table public.equipment_locations enable row level security;
alter table public.equipment_rooms enable row level security;
alter table public.inventory_item_locations enable row level security;
alter table public.inventory_item_rooms enable row level security;

create policy "members manage recipe_categories" on public.recipe_categories
  for all
  using (space_id in (select public.my_space_ids()))
  with check (space_id in (select public.my_space_ids()));

create policy "members manage recipe_tags" on public.recipe_tags
  for all
  using (space_id in (select public.my_space_ids()))
  with check (space_id in (select public.my_space_ids()));

create policy "members manage recipe_category_links" on public.recipe_category_links
  for all
  using (exists (
    select 1 from public.recipes r
    where r.id = recipe_category_links.recipe_id
    and r.space_id in (select public.my_space_ids())
  ))
  with check (exists (
    select 1 from public.recipes r
    where r.id = recipe_category_links.recipe_id
    and r.space_id in (select public.my_space_ids())
  ));

create policy "members manage recipe_tag_links" on public.recipe_tag_links
  for all
  using (exists (
    select 1 from public.recipes r
    where r.id = recipe_tag_links.recipe_id
    and r.space_id in (select public.my_space_ids())
  ))
  with check (exists (
    select 1 from public.recipes r
    where r.id = recipe_tag_links.recipe_id
    and r.space_id in (select public.my_space_ids())
  ));

create policy "members manage equipment_locations" on public.equipment_locations
  for all
  using (exists (
    select 1 from public.equipment e
    where e.id = equipment_locations.equipment_id
    and e.space_id in (select public.my_space_ids())
  ))
  with check (exists (
    select 1 from public.equipment e
    where e.id = equipment_locations.equipment_id
    and e.space_id in (select public.my_space_ids())
  ));

create policy "members manage equipment_rooms" on public.equipment_rooms
  for all
  using (exists (
    select 1 from public.equipment e
    where e.id = equipment_rooms.equipment_id
    and e.space_id in (select public.my_space_ids())
  ))
  with check (exists (
    select 1 from public.equipment e
    where e.id = equipment_rooms.equipment_id
    and e.space_id in (select public.my_space_ids())
  ));

create policy "members manage inventory_item_locations" on public.inventory_item_locations
  for all
  using (exists (
    select 1 from public.inventory_items ii
    where ii.id = inventory_item_locations.inventory_item_id
    and ii.space_id in (select public.my_space_ids())
  ))
  with check (exists (
    select 1 from public.inventory_items ii
    where ii.id = inventory_item_locations.inventory_item_id
    and ii.space_id in (select public.my_space_ids())
  ));

create policy "members manage inventory_item_rooms" on public.inventory_item_rooms
  for all
  using (exists (
    select 1 from public.inventory_items ii
    where ii.id = inventory_item_rooms.inventory_item_id
    and ii.space_id in (select public.my_space_ids())
  ))
  with check (exists (
    select 1 from public.inventory_items ii
    where ii.id = inventory_item_rooms.inventory_item_id
    and ii.space_id in (select public.my_space_ids())
  ));
