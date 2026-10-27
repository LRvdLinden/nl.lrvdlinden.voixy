-- Track transfer to each device separately from completed audio playback.
alter table public.voxie_audio_frames
  add column if not exists received_phone boolean not null default false,
  add column if not exists received_watch boolean not null default false;
