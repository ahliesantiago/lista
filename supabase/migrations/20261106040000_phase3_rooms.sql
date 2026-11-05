-- Promote storage_locations.room from freeform text to a managed `rooms`
-- table (same shape as tags/units): editable in one place, and a real list
-- to suggest from instead of re-deriving distinct text values.

create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces(id) on delete cascade,
  name text not null,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create unique index rooms_space_id_name_key on public.rooms (space_id, name) where deleted_at is null;

alter table public.rooms enable row level security;

create policy "members manage rooms" on public.rooms
  for all
  using (space_id in (select public.my_space_ids()))
  with check (space_id in (select public.my_space_ids()));

-- backfill rooms from existing freeform text, then point storage_locations at them
insert into public.rooms (space_id, name)
select distinct space_id, room from public.storage_locations where room is not null;

alter table public.storage_locations add column room_id uuid references public.rooms(id) on delete set null;

update public.storage_locations sl
set room_id = r.id
from public.rooms r
where r.space_id = sl.space_id and r.name = sl.room;

drop index public.storage_locations_space_id_name_room_key;
create unique index storage_locations_space_id_name_room_id_key
  on public.storage_locations (space_id, name, room_id)
  where deleted_at is null;

alter table public.storage_locations drop column room;
