-- Phase 4: Recipes. recipes/steps/ingredients/equipment, ingredient
-- alternatives (data model for Phase 7's filter, unused until then),
-- categories/tags/equipment join tables reusing the existing taxonomy.

create table public.recipes (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces(id) on delete cascade,
  name text not null,
  description text,
  image_url text,
  source_url text,
  prep_time_minutes integer,
  cook_time_minutes integer,
  total_time_minutes integer,
  servings text,
  is_favorite boolean not null default false,
  is_interested boolean not null default false,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.equipment (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces(id) on delete cascade,
  name text not null,
  notes text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create unique index equipment_space_id_name_key on public.equipment (space_id, name) where deleted_at is null;

create table public.recipe_steps (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid not null references public.recipes(id) on delete cascade,
  step_number integer not null,
  instruction text not null,
  created_at timestamptz not null default now()
);

create table public.recipe_ingredients (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid not null references public.recipes(id) on delete cascade,
  item_id uuid not null references public.items(id) on delete cascade,
  quantity numeric,
  unit_id uuid references public.units(id) on delete set null,
  note text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table public.recipe_ingredient_alternatives (
  recipe_ingredient_id uuid not null references public.recipe_ingredients(id) on delete cascade,
  item_id uuid not null references public.items(id) on delete cascade,
  primary key (recipe_ingredient_id, item_id)
);

create table public.recipe_categories (
  recipe_id uuid not null references public.recipes(id) on delete cascade,
  category_id uuid not null references public.categories(id) on delete cascade,
  primary key (recipe_id, category_id)
);

create table public.recipe_tags (
  recipe_id uuid not null references public.recipes(id) on delete cascade,
  tag_id uuid not null references public.tags(id) on delete cascade,
  primary key (recipe_id, tag_id)
);

create table public.recipe_equipment (
  recipe_id uuid not null references public.recipes(id) on delete cascade,
  equipment_id uuid not null references public.equipment(id) on delete cascade,
  primary key (recipe_id, equipment_id)
);

alter table public.recipes enable row level security;
alter table public.equipment enable row level security;
alter table public.recipe_steps enable row level security;
alter table public.recipe_ingredients enable row level security;
alter table public.recipe_ingredient_alternatives enable row level security;
alter table public.recipe_categories enable row level security;
alter table public.recipe_tags enable row level security;
alter table public.recipe_equipment enable row level security;

create policy "members manage recipes" on public.recipes
  for all
  using (space_id in (select public.my_space_ids()))
  with check (space_id in (select public.my_space_ids()));

create policy "members manage equipment" on public.equipment
  for all
  using (space_id in (select public.my_space_ids()))
  with check (space_id in (select public.my_space_ids()));

create policy "members manage recipe_steps" on public.recipe_steps
  for all
  using (exists (
    select 1 from public.recipes r
    where r.id = recipe_steps.recipe_id
    and r.space_id in (select public.my_space_ids())
  ))
  with check (exists (
    select 1 from public.recipes r
    where r.id = recipe_steps.recipe_id
    and r.space_id in (select public.my_space_ids())
  ));

create policy "members manage recipe_ingredients" on public.recipe_ingredients
  for all
  using (exists (
    select 1 from public.recipes r
    where r.id = recipe_ingredients.recipe_id
    and r.space_id in (select public.my_space_ids())
  ))
  with check (exists (
    select 1 from public.recipes r
    where r.id = recipe_ingredients.recipe_id
    and r.space_id in (select public.my_space_ids())
  ));

create policy "members manage recipe_ingredient_alternatives" on public.recipe_ingredient_alternatives
  for all
  using (exists (
    select 1 from public.recipe_ingredients ri
    join public.recipes r on r.id = ri.recipe_id
    where ri.id = recipe_ingredient_alternatives.recipe_ingredient_id
    and r.space_id in (select public.my_space_ids())
  ))
  with check (exists (
    select 1 from public.recipe_ingredients ri
    join public.recipes r on r.id = ri.recipe_id
    where ri.id = recipe_ingredient_alternatives.recipe_ingredient_id
    and r.space_id in (select public.my_space_ids())
  ));

create policy "members manage recipe_categories" on public.recipe_categories
  for all
  using (exists (
    select 1 from public.recipes r
    where r.id = recipe_categories.recipe_id
    and r.space_id in (select public.my_space_ids())
  ))
  with check (exists (
    select 1 from public.recipes r
    where r.id = recipe_categories.recipe_id
    and r.space_id in (select public.my_space_ids())
  ));

create policy "members manage recipe_tags" on public.recipe_tags
  for all
  using (exists (
    select 1 from public.recipes r
    where r.id = recipe_tags.recipe_id
    and r.space_id in (select public.my_space_ids())
  ))
  with check (exists (
    select 1 from public.recipes r
    where r.id = recipe_tags.recipe_id
    and r.space_id in (select public.my_space_ids())
  ));

create policy "members manage recipe_equipment" on public.recipe_equipment
  for all
  using (exists (
    select 1 from public.recipes r
    where r.id = recipe_equipment.recipe_id
    and r.space_id in (select public.my_space_ids())
  ))
  with check (exists (
    select 1 from public.recipes r
    where r.id = recipe_equipment.recipe_id
    and r.space_id in (select public.my_space_ids())
  ));
