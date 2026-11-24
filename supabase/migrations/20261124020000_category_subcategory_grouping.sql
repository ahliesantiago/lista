-- "Category" grouping was supposed to mean "main category" only, but
-- is_primary was a single flag shared across an item's main-category AND
-- subcategory links (whichever ranked #1 alphabetically across both),
-- so clicking a subcategory badge could silently switch grouping to it.
-- Split the subcategory half out into its own flag, so an item can have
-- (up to) one primary main category AND one primary subcategory at the
-- same time - is_primary now applies strictly to main-category rows
-- (parent_id is null) going forward, is_primary_subcategory to the rest.
-- This also backs the new "Category & Subcategory" grouping mode.
alter table public.item_categories add column is_primary_subcategory boolean not null default false;

-- move any existing primary that's actually a subcategory into the new
-- column, then clear the stale is_primary on those same rows
update public.item_categories ic
set is_primary_subcategory = true
from public.categories c
where c.id = ic.category_id and c.parent_id is not null and ic.is_primary = true;

update public.item_categories ic
set is_primary = false
from public.categories c
where c.id = ic.category_id and c.parent_id is not null and ic.is_primary = true;

-- backfill a subcategory primary (first by name) for any item that has
-- subcategory links but, after the moves above, none marked primary
with sub_ranked as (
  select ic.item_id, ic.category_id,
         row_number() over (partition by ic.item_id order by c.name) as rn
  from public.item_categories ic
  join public.categories c on c.id = ic.category_id
  where c.parent_id is not null
),
needs_primary as (
  select ic.item_id
  from public.item_categories ic
  join public.categories c on c.id = ic.category_id
  where c.parent_id is not null
  group by ic.item_id
  having bool_or(ic.is_primary_subcategory) = false
)
update public.item_categories ic
set is_primary_subcategory = true
from sub_ranked r
join needs_primary np on np.item_id = r.item_id
where ic.item_id = r.item_id and ic.category_id = r.category_id and r.rn = 1;

-- backfill a main-category primary (first by name) for any item that has
-- main-category links but none marked primary (true for every item whose
-- sole old primary was a subcategory, just cleared above)
with main_ranked as (
  select ic.item_id, ic.category_id,
         row_number() over (partition by ic.item_id order by c.name) as rn
  from public.item_categories ic
  join public.categories c on c.id = ic.category_id
  where c.parent_id is null
),
needs_primary as (
  select ic.item_id
  from public.item_categories ic
  join public.categories c on c.id = ic.category_id
  where c.parent_id is null
  group by ic.item_id
  having bool_or(ic.is_primary) = false
)
update public.item_categories ic
set is_primary = true
from main_ranked r
join needs_primary np on np.item_id = r.item_id
where ic.item_id = r.item_id and ic.category_id = r.category_id and r.rn = 1;
