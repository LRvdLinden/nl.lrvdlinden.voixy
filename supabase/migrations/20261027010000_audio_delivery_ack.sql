-- A frame is removed when each selected playback device confirms playback.
alter table public.voxie_audio_frames
  add column if not exists played_phone boolean not null default false,
  add column if not exists played_watch boolean not null default false;

-- Automatic expiry for abandoned/undelivered frames. Requires pg_cron enabled
-- in Supabase Dashboard. Schedule immediately when the extension is available.
do $outer$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute $schedule$
      select cron.schedule('voxie-audio-expire', '* * * * *',
        $job$delete from public.voxie_audio_frames
             where created_at < now() - interval '15 seconds'$job$)
    $schedule$;
  end if;
end
$outer$;
