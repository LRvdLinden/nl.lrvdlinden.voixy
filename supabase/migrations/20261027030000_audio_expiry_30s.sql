-- Change expiry of abandoned frames to 30 seconds (one-minute cron sweep).
do $outer$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute $schedule$
      select cron.schedule('voxie-audio-expire', '* * * * *',
        $job$delete from public.voxie_audio_frames
             where created_at < now() - interval '30 seconds'$job$)
    $schedule$;
  end if;
end
$outer$;
