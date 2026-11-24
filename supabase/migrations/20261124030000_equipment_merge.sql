-- Equipment doesn't need its own table - the only reason it existed
-- separately was recipes needing something to point "equipment" links at.
-- Cooking equipment is now just items/appliances/furniture flagged
-- is_equipment; recipe_equipment points at whichever of the three a given
-- piece of equipment actually is, via three nullable FKs (exactly one set)
-- instead of a single equipment_id.

alter table public.items add column is_equipment boolean not null default false;
alter table public.appliances add column is_equipment boolean not null default false;
alter table public.furniture add column is_equipment boolean not null default false;

alter table public.recipe_equipment add column item_id uuid references public.items(id) on delete cascade;
alter table public.recipe_equipment add column appliance_id uuid references public.appliances(id) on delete cascade;
alter table public.recipe_equipment add column furniture_id uuid references public.furniture(id) on delete cascade;

-- existing equipment rows become appliances by default (closest existing
-- shape: notes + up to 2 locations/rooms already match) - reusing the same
-- id means every reference to it (locations, rooms, recipe links) carries
-- over by simple id equality, no mapping table needed. Any that don't
-- really belong as an appliance can be moved to Items/Furniture by hand
-- afterward, same as any other appliance.
insert into public.appliances (id, space_id, name, notes, is_equipment, created_by, created_at, deleted_at)
select e.id, e.space_id, e.name, e.notes, true, e.created_by, e.created_at, e.deleted_at
from public.equipment e;

insert into public.appliance_locations (appliance_id, storage_location_id)
select equipment_id, storage_location_id from public.equipment_locations;

insert into public.appliance_rooms (appliance_id, room_id)
select equipment_id, room_id from public.equipment_rooms;

update public.recipe_equipment set appliance_id = equipment_id;

alter table public.recipe_equipment drop constraint recipe_equipment_pkey;
alter table public.recipe_equipment add column id uuid primary key default gen_random_uuid();
alter table public.recipe_equipment drop column equipment_id;

alter table public.recipe_equipment add constraint recipe_equipment_one_source check (
  (item_id is not null)::int + (appliance_id is not null)::int + (furniture_id is not null)::int = 1
);

create unique index recipe_equipment_recipe_item_key on public.recipe_equipment (recipe_id, item_id) where item_id is not null;
create unique index recipe_equipment_recipe_appliance_key on public.recipe_equipment (recipe_id, appliance_id) where appliance_id is not null;
create unique index recipe_equipment_recipe_furniture_key on public.recipe_equipment (recipe_id, furniture_id) where furniture_id is not null;

drop table public.equipment_locations;
drop table public.equipment_rooms;
drop table public.equipment;
