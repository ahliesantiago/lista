-- Optional freeform notes, same pattern already used by appliances/
-- furniture/equipment/pantry_items, extended to the other flat master-list
-- tables that were still missing it.
alter table public.items add column notes text;
alter table public.storage_locations add column notes text;
alter table public.rooms add column notes text;
