-- Per-list display preference: whether crossed-off (is_done) items should
-- visually sink to the bottom of their own group/parent. This is a
-- view-only ordering concern (applied client-side, see [id].vue's
-- useGroupedItemTree) - it never rewrites sort_order, so it needs no
-- backfill.
alter table public.lists add column move_done_to_bottom boolean not null default false;
