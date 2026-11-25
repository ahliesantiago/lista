/**
 * Lets the theme color selection persist across browsers and devices
 * per account by storing it in the users table.
 */
alter table public.users add column primary_color text;
