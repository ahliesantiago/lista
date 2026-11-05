-- Phase 1 addendum: multi-category + hierarchical subcategories.
-- Replaces the single items.category_id / lists.category_id scalar FK with
-- join tables (same shape as item_tags/list_tags), and adds a self-ref on
-- categories so a row can optionally be a subcategory of another.

alter table public.categories add column parent_id uuid references public.categories(id) on delete cascade;

create table public.item_categories (
  item_id uuid not null references public.items(id) on delete cascade,
  category_id uuid not null references public.categories(id) on delete cascade,
  primary key (item_id, category_id)
);

create table public.list_categories (
  list_id uuid not null references public.lists(id) on delete cascade,
  category_id uuid not null references public.categories(id) on delete cascade,
  primary key (list_id, category_id)
);

alter table public.item_categories enable row level security;
alter table public.list_categories enable row level security;

create policy "members manage item_categories" on public.item_categories
  for all
  using (exists (
    select 1 from public.items i
    where i.id = item_categories.item_id
    and i.space_id in (select public.my_space_ids())
  ))
  with check (exists (
    select 1 from public.items i
    where i.id = item_categories.item_id
    and i.space_id in (select public.my_space_ids())
  ));

create policy "members manage list_categories" on public.list_categories
  for all
  using (exists (
    select 1 from public.lists l
    where l.id = list_categories.list_id
    and l.space_id in (select public.my_space_ids())
  ))
  with check (exists (
    select 1 from public.lists l
    where l.id = list_categories.list_id
    and l.space_id in (select public.my_space_ids())
  ));

-- preserve existing single-category links before dropping the columns
insert into public.item_categories (item_id, category_id)
select id, category_id from public.items where category_id is not null;

insert into public.list_categories (list_id, category_id)
select id, category_id from public.lists where category_id is not null;

alter table public.items drop column category_id;
alter table public.lists drop column category_id;
