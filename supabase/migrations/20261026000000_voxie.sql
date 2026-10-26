-- Voxie watch-only messaging: accessible exclusively through the Edge Function.
-- No public table policies are granted. The function uses a server-side secret key.
create extension if not exists pgcrypto;

create table if not exists public.voxie_users (
  id uuid primary key default gen_random_uuid(),
  token_hash text not null unique,
  invite_code text not null unique,
  display_name text not null check (char_length(display_name) between 1 and 36),
  available boolean not null default true,
  last_poll timestamptz,
  apns_token text,
  created_at timestamptz not null default now()
);

create table if not exists public.voxie_invitations (
  id bigint generated always as identity primary key,
  sender uuid not null references public.voxie_users(id) on delete cascade,
  recipient uuid not null references public.voxie_users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','declined')),
  created_at timestamptz not null default now(),
  constraint different_users check (sender <> recipient),
  constraint unique_invitation unique (sender, recipient)
);

create table if not exists public.voxie_friends (
  user_a uuid not null references public.voxie_users(id) on delete cascade,
  user_b uuid not null references public.voxie_users(id) on delete cascade,
  primary key (user_a, user_b),
  constraint sorted_friend_pair check (user_a < user_b)
);

create table if not exists public.voxie_audio_frames (
  id bigint generated always as identity primary key,
  sender uuid not null references public.voxie_users(id) on delete cascade,
  recipient uuid not null references public.voxie_users(id) on delete cascade,
  pcm_base64 text not null,
  created_at timestamptz not null default now()
);
create index if not exists voxie_audio_recipient_cursor on public.voxie_audio_frames (recipient, id);
create index if not exists voxie_audio_created on public.voxie_audio_frames (created_at);

alter table public.voxie_users enable row level security;
alter table public.voxie_invitations enable row level security;
alter table public.voxie_friends enable row level security;
alter table public.voxie_audio_frames enable row level security;

revoke all on public.voxie_users, public.voxie_invitations,
  public.voxie_friends, public.voxie_audio_frames from anon, authenticated;

-- Optional scheduled cleanup in Supabase pg_cron (once enabled):
-- select cron.schedule('voxie-frame-cleanup', '* * * * *',
--   $$delete from public.voxie_audio_frames where created_at < now() - interval '15 seconds'$$);
