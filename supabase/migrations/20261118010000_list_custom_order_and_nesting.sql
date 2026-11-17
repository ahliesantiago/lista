-- Custom manual ordering for lists and list items, plus one level of
-- nesting (parent/child) within a list's own items. Max depth (parent +
-- child, no grandchildren) is enforced in the UI only, same precedent as
-- categories/recipe_categories' own parent_id self-reference.

alter table public.lists add column sort_order integer not null default 0;
alter table public.list_items add column sort_order integer not null default 0;
alter table public.list_items add column parent_id uuid references public.list_items(id) on delete cascade;

-- backfill existing rows to their current chronological order, so switching
-- to "Custom order" doesn't scramble everything to a tied sort_order = 0
with ordered as (
  select id, row_number() over (partition by space_id order by created_at) - 1 as rn
  from public.lists
)
update public.lists l set sort_order = o.rn from ordered o where o.id = l.id;

with ordered as (
  select id, row_number() over (partition by list_id order by created_at) - 1 as rn
  from public.list_items
)
update public.list_items li set sort_order = o.rn from ordered o where o.id = li.id;
