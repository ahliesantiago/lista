-- Each item can be linked to multiple categories/tags, but grouping by
-- category or tag should only ever place an item in one bucket. Add an
-- is_primary flag to mark which link is used as the grouping key (app
-- code only enforces "at most one primary per item" - same precedent as
-- the category hierarchy's depth cap).

alter table public.item_categories add column is_primary boolean not null default false;
alter table public.item_tags add column is_primary boolean not null default false;

-- neither join table has a created_at/ordering column, so backfill
-- deterministically by name - categories/tags are unique(space_id, name)
-- and every link points to a category/tag in the same space as the item,
-- so there's never a tie to break
with ranked as (
  select ic.item_id, ic.category_id, row_number() over (partition by ic.item_id order by c.name) as rn
  from public.item_categories ic join public.categories c on c.id = ic.category_id
)
update public.item_categories ic set is_primary = true
from ranked r where r.item_id = ic.item_id and r.category_id = ic.category_id and r.rn = 1;

with ranked as (
  select it.item_id, it.tag_id, row_number() over (partition by it.item_id order by t.name) as rn
  from public.item_tags it join public.tags t on t.id = it.tag_id
)
update public.item_tags it set is_primary = true
from ranked r where r.item_id = it.item_id and r.tag_id = it.tag_id and r.rn = 1;
