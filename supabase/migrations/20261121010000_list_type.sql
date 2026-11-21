-- List type is chosen once at creation and never changed by any UI
-- afterward (no DB trigger needed - the only two write paths only ever
-- insert it). list_items needs no schema change: a bullet/numbered item
-- is identical in shape to today's "list-only" checklist item (item_id
-- is already nullable).
alter table public.lists
  add column list_type text not null default 'checklist'
  check (list_type in ('checklist', 'bullet', 'numbered', 'note'));
