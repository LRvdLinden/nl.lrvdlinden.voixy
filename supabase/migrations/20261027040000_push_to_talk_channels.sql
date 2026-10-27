-- Ephemeral Apple Push to Talk channel tokens are not public profile data.
create table if not exists public.voxie_ptt_channels (
  user_id uuid primary key references public.voxie_users(id) on delete cascade,
  token text not null,
  channel_uuid uuid not null,
  updated_at timestamptz not null default now()
);
alter table public.voxie_ptt_channels enable row level security;
revoke all on public.voxie_ptt_channels from anon, authenticated;
create index if not exists voxie_ptt_channels_updated_at_idx
  on public.voxie_ptt_channels(updated_at);
