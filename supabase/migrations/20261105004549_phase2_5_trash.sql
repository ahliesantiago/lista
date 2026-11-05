-- Phase 2.5: soft delete + Trash. deleted_at added to the six primary
-- entities (not plain join tables). Existing plain unique constraints on
-- name-like columns become partial unique indexes scoped to live rows,
-- since a trashed row would otherwise permanently block reusing its name.

alter table public.categories add column deleted_at timestamptz;
alter table public.tags add column deleted_at timestamptz;
alter table public.units add column deleted_at timestamptz;
alter table public.items add column deleted_at timestamptz;
alter table public.lists add column deleted_at timestamptz;
alter table public.list_items add column deleted_at timestamptz;

alter table public.categories drop constraint categories_space_id_name_key;
create unique index categories_space_id_name_key on public.categories (space_id, name) where deleted_at is null;

alter table public.tags drop constraint tags_space_id_name_key;
create unique index tags_space_id_name_key on public.tags (space_id, name) where deleted_at is null;

alter table public.units drop constraint units_space_id_name_singular_key;
create unique index units_space_id_name_singular_key on public.units (space_id, name_singular) where deleted_at is null;

alter table public.items drop constraint items_space_id_name_key;
create unique index items_space_id_name_key on public.items (space_id, name) where deleted_at is null;
