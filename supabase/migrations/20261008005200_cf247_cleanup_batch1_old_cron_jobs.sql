-- CF-247 clean-up batch 1 (Platform Admin, 9 Oct 2026: "make sure we are doing the cleanup from old system as we go along").
-- Removes eight cron jobs of the old Layer 2 pipeline and the old Layer 3 tuition enqueue. All eight were switched off on
-- 2 Oct 2026 (20261002181800, 20261002182200) and replaced by coverage-sweep (discover, read, tuition_handoff) and the
-- adapter read cycle. Each job is removed only if it is still switched off; the database functions they called and all
-- history are kept. To restore one, re-run cron.schedule with the definition recorded below.
--
--   coursefinder-layer2-fanout-scheduler        27,57 * * * *     select security.layer2_fanout_scheduler_tick_impl(now(),10,true);
--   coursefinder-layer2-qualification-finalizer 2-59/15 * * * *   select security.layer2_qualification_finalizer_tick_impl();
--   coursefinder-layer2-qualification-scheduler 32 * * * *        select security.layer2_qualification_scheduler_tick_impl(2);
--   coursefinder-layer2-refresh-dispatcher      18 * * * *        select security.layer2_refresh_scheduler_tick_impl(now(),10,true);
--   coursefinder-layer2-wave-scheduler          40 * * * *        select public.svc_layer2_wave_scheduler();
--   layer2-auto-discovery                       13-59/15 * * * *  select security.layer2_auto_discovery_tick_v1();
--   layer2-stale-wave-closer                    17 3 * * *        select security.layer2_wave_request_close_stale_v1(true);
--   layer3-tuition-enqueue                      22 * * * *        select public.layer3_enqueue_eligible_layer2_service(250)

do $cleanup$
declare j text; n int := 0;
begin
  foreach j in array array['coursefinder-layer2-fanout-scheduler','coursefinder-layer2-qualification-finalizer',
      'coursefinder-layer2-qualification-scheduler','coursefinder-layer2-refresh-dispatcher','coursefinder-layer2-wave-scheduler',
      'layer2-auto-discovery','layer2-stale-wave-closer','layer3-tuition-enqueue'] loop
    if exists (select 1 from cron.job where jobname = j and active) then
      raise exception 'cron job % is switched on; clean-up refused', j;
    end if;
    if exists (select 1 from cron.job where jobname = j) then
      perform cron.unschedule(j);
      n := n + 1;
    end if;
  end loop;
  raise notice 'removed % switched-off cron jobs', n;
end $cleanup$;
