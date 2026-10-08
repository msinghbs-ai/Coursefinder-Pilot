-- CF-247 Phase 2, 8 Oct 2026: drives the side-by-side replay one slice a minute (about 42 slices for the three archives) and stops itself
-- when no replay run is left. Schedule register-replay; listed under Layer 1.
create or replace function security.register_replay_tick_v1()
returns jsonb language plpgsql security definer set search_path = '' as $f$
begin
  if not exists (select 1 from pipeline.register_replay_runs where done_at is null and error is null) then
    perform cron.unschedule('register-replay');
    return jsonb_build_object('finished', true);
  end if;
  perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'register_replay'));
  return jsonb_build_object('sent', true);
end $f$;
revoke all on function security.register_replay_tick_v1() from public, anon, authenticated;
select cron.schedule('register-replay', '* * * * *', 'select security.register_replay_tick_v1()');
insert into pipeline.platform_job_layers(jobname, layer, updated_at) values ('register-replay', 1, now()) on conflict (jobname) do nothing;
