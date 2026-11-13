-- Phase 5: Recipe <-> List integration. list_item_sources records which
-- recipe(s) contributed to a list_item's quantity, so a consolidated line
-- can show per-recipe provenance underneath it.

create table public.list_item_sources (
  id uuid primary key default gen_random_uuid(),
  list_item_id uuid not null references public.list_items(id) on delete cascade,
  recipe_id uuid references public.recipes(id) on delete set null,
  quantity numeric,
  unit_id uuid references public.units(id) on delete set null,
  created_at timestamptz not null default now()
);

alter table public.list_item_sources enable row level security;

create policy "members manage list_item_sources" on public.list_item_sources
  for all
  using (exists (
    select 1 from public.list_items li
    join public.lists l on l.id = li.list_id
    where li.id = list_item_sources.list_item_id
    and l.space_id in (select public.my_space_ids())
  ))
  with check (exists (
    select 1 from public.list_items li
    join public.lists l on l.id = li.list_id
    where li.id = list_item_sources.list_item_id
    and l.space_id in (select public.my_space_ids())
  ));
