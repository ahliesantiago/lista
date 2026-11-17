-- Appliances and furniture get the same up-to-2-Locations and up-to-2-Rooms
-- support that equipment and inventory_items already have, via independent
-- join tables (same pattern/reasoning as 20261106100000). Furniture's old
-- single freeform `room` text column is superseded by the new furniture_rooms
-- join table (pointing at the real public.rooms table) and dropped.

create table public.appliance_locations (
  appliance_id uuid not null references public.appliances(id) on delete cascade,
  storage_location_id uuid not null references public.storage_locations(id) on delete cascade,
  primary key (appliance_id, storage_location_id)
);

create table public.appliance_rooms (
  appliance_id uuid not null references public.appliances(id) on delete cascade,
  room_id uuid not null references public.rooms(id) on delete cascade,
  primary key (appliance_id, room_id)
);

create table public.furniture_locations (
  furniture_id uuid not null references public.furniture(id) on delete cascade,
  storage_location_id uuid not null references public.storage_locations(id) on delete cascade,
  primary key (furniture_id, storage_location_id)
);

create table public.furniture_rooms (
  furniture_id uuid not null references public.furniture(id) on delete cascade,
  room_id uuid not null references public.rooms(id) on delete cascade,
  primary key (furniture_id, room_id)
);

-- backfill: ensure a `rooms` row exists for every distinct non-null
-- `furniture.room` text value (per space), then link it via the new
-- furniture_rooms join table, before dropping the old freeform column
insert into public.rooms (space_id, name)
select distinct f.space_id, f.room
from public.furniture f
where f.room is not null
  and not exists (
    select 1 from public.rooms r
    where r.space_id = f.space_id and r.name = f.room and r.deleted_at is null
  );

insert into public.furniture_rooms (furniture_id, room_id)
select f.id, r.id
from public.furniture f
join public.rooms r on r.space_id = f.space_id and r.name = f.room and r.deleted_at is null
where f.room is not null;

alter table public.furniture drop column room;

alter table public.appliance_locations enable row level security;
alter table public.appliance_rooms enable row level security;
alter table public.furniture_locations enable row level security;
alter table public.furniture_rooms enable row level security;

create policy "members manage appliance_locations" on public.appliance_locations
  for all
  using (exists (
    select 1 from public.appliances a
    where a.id = appliance_locations.appliance_id
    and a.space_id in (select public.my_space_ids())
  ))
  with check (exists (
    select 1 from public.appliances a
    where a.id = appliance_locations.appliance_id
    and a.space_id in (select public.my_space_ids())
  ));

create policy "members manage appliance_rooms" on public.appliance_rooms
  for all
  using (exists (
    select 1 from public.appliances a
    where a.id = appliance_rooms.appliance_id
    and a.space_id in (select public.my_space_ids())
  ))
  with check (exists (
    select 1 from public.appliances a
    where a.id = appliance_rooms.appliance_id
    and a.space_id in (select public.my_space_ids())
  ));

create policy "members manage furniture_locations" on public.furniture_locations
  for all
  using (exists (
    select 1 from public.furniture f
    where f.id = furniture_locations.furniture_id
    and f.space_id in (select public.my_space_ids())
  ))
  with check (exists (
    select 1 from public.furniture f
    where f.id = furniture_locations.furniture_id
    and f.space_id in (select public.my_space_ids())
  ));

create policy "members manage furniture_rooms" on public.furniture_rooms
  for all
  using (exists (
    select 1 from public.furniture f
    where f.id = furniture_rooms.furniture_id
    and f.space_id in (select public.my_space_ids())
  ))
  with check (exists (
    select 1 from public.furniture f
    where f.id = furniture_rooms.furniture_id
    and f.space_id in (select public.my_space_ids())
  ));
