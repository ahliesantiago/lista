-- recipe_ingredients becomes ad-hoc-capable, matching list_items exactly:
-- its own `name` snapshot (always set) plus a nullable item_id, instead of
-- a mandatory item link with no independent identity. This is what lets an
-- ingredient be edited, re-pointed at a different item, or kept off the
-- master list entirely - none of which were possible before.

alter table public.recipe_ingredients add column name text;

update public.recipe_ingredients ri
set name = i.name
from public.items i
where i.id = ri.item_id;

alter table public.recipe_ingredients alter column name set not null;

alter table public.recipe_ingredients drop constraint recipe_ingredients_item_id_fkey;
alter table public.recipe_ingredients alter column item_id drop not null;
alter table public.recipe_ingredients
  add constraint recipe_ingredients_item_id_fkey
  foreign key (item_id) references public.items(id) on delete set null;
