-- Phase 2: generic lists + list items. Reuses the space_id RLS pattern from
-- Phase 1 for `lists`, and the exists-through-parent pattern (like
-- item_tags/item_units) for `list_items`/`list_tags`.

create table public.lists (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces(id) on delete cascade,
  name text not null,
  category_id uuid references public.categories(id) on delete set null,
  status text not null default 'active' check (status in ('active', 'archived')),
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.list_items (
  id uuid primary key default gen_random_uuid(),
  list_id uuid not null references public.lists(id) on delete cascade,
  item_id uuid references public.items(id) on delete set null,
  name text not null,
  amount numeric,
  unit_id uuid references public.units(id) on delete set null,
  size text,
  is_done boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.list_tags (
  list_id uuid not null references public.lists(id) on delete cascade,
  tag_id uuid not null references public.tags(id) on delete cascade,
  primary key (list_id, tag_id)
);

alter table public.lists enable row level security;
alter table public.list_items enable row level security;
alter table public.list_tags enable row level security;

create policy "members manage lists" on public.lists
  for all
  using (space_id in (select public.my_space_ids()))
  with check (space_id in (select public.my_space_ids()));

create policy "members manage list_items" on public.list_items
  for all
  using (exists (
    select 1 from public.lists l
    where l.id = list_items.list_id
    and l.space_id in (select public.my_space_ids())
  ))
  with check (exists (
    select 1 from public.lists l
    where l.id = list_items.list_id
    and l.space_id in (select public.my_space_ids())
  ));

create policy "members manage list_tags" on public.list_tags
  for all
  using (exists (
    select 1 from public.lists l
    where l.id = list_tags.list_id
    and l.space_id in (select public.my_space_ids())
  ))
  with check (exists (
    select 1 from public.lists l
    where l.id = list_tags.list_id
    and l.space_id in (select public.my_space_ids())
  ));
