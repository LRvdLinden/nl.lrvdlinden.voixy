-- Apple-authenticated, cross-device accounts and unique public handles.
create extension if not exists citext;

alter table public.voxie_users
  add column if not exists apple_subject text unique,
  add column if not exists username citext unique,
  add column if not exists avatar_base64 text;

alter table public.voxie_users
  add constraint voxie_username_format check (
    username is null or username::text ~ '^[a-z0-9_]{3,20}$'
  ),
  add constraint voxie_avatar_limit check (
    avatar_base64 is null or char_length(avatar_base64) <= 110000
  );

create table if not exists public.voxie_sessions (
  token_hash text primary key,
  user_id uuid not null references public.voxie_users(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '90 days'
);
create index if not exists voxie_sessions_user on public.voxie_sessions (user_id);

create table if not exists public.voxie_login_challenges (
  nonce_hash text primary key,
  expires_at timestamptz not null default now() + interval '5 minutes'
);

alter table public.voxie_sessions enable row level security;
alter table public.voxie_login_challenges enable row level security;
revoke all on public.voxie_sessions, public.voxie_login_challenges from anon, authenticated;

-- Periodically remove old sessions and challenges with pg_cron when enabled.
