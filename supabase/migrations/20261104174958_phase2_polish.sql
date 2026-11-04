-- Phase 2 polish: description/notes fields surfaced on the list detail page.
alter table public.lists add column description text, add column notes text;
alter table public.list_items add column notes text;
