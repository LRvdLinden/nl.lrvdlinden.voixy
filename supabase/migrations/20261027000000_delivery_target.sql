-- Account-wide preference for which foreground app receives audio frames.
alter table public.voxie_users
  add column if not exists delivery_target text not null default 'both'
  check (delivery_target in ('watch', 'phone', 'both'));
