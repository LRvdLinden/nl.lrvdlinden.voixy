-- Build 20: Apple Watch alert notifications and 2-minute audio lifetime.
-- Each Watch registers its APNs token with the environment it was built for
-- (sandbox for Xcode debug builds, production for TestFlight/App Store).
alter table public.voxie_users
  add column if not exists apns_environment text not null default 'production'
  check (apns_environment in ('sandbox', 'production'));

-- Unplayed speech stays available for 120 seconds so a tapped notification
-- still plays the full message. Requires pg_cron (Dashboard → Extensions).
do $outer$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute $schedule$
      select cron.schedule('voxie-audio-expire', '* * * * *',
        $job$delete from public.voxie_audio_frames
             where created_at < now() - interval '120 seconds'$job$)
    $schedule$;
  end if;
end
$outer$;
