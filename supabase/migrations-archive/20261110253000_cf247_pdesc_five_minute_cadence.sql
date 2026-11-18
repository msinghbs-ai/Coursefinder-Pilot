-- CF-247 F-PDESC follow-up to 20261110250000/20261110252000 (live, 10 Nov 2026 23:26 AEDT): three worker calls a fire do not fit. The lease
-- (svc_provider_description_next) does several seconds of work under its capacity lock, so with the lease waiting its turn one call reached
-- the API statement time-out (8 s) and the other two gave up after 5 s: that fire leased nothing (all rolled back, nothing changed).
-- Speed now comes from cadence instead of parallel calls, keeping the one-call lease that has run all day:
--   1 the lease's try-lock is restored exactly (inverse of 20261110252000);
--   2 pdesc.dispatch_max 3 -> 1 (one call a fire, as before 20261110250000);
--   3 job provider-description-read every 5 minutes (1,6,...,56) instead of every 10, and pdesc.every_minutes 10 -> 5 (its lower bound
--     10 -> 5, a release change); the fire's own guards (one open call, 4-minute fire guard, spend ceiling, capacity) are unchanged;
--   4 job provider-description-self-heal moves to 3,13,...,53 so it never shares a minute with the reader's lease.
-- About 120 page reads an hour instead of 60. No consumer object (G3). Forward recovery: schedules 6,16,...,56 and 1,11,...,51, every_minutes 10
-- (bound 10).
-- Replaces: 20261110252000 (its lock change) and the dispatch_max 3 of 20261110250000.
-- Retires: nothing.

do $f$
declare d text := pg_get_functiondef('public.svc_provider_description_next(integer)'::regprocedure);
        o text := $o$  -- 20261110252000: the calls of one fire take turns on the capacity lock (at most 5 s, fixed: a lease takes milliseconds) instead of giving up at once
  declare v_lt text := current_setting('lock_timeout');
  begin
    perform set_config('lock_timeout', '5s', true);
    perform pg_advisory_xact_lock(hashtext('cf247 provider description capacity'));
    perform set_config('lock_timeout', v_lt, true);
  exception when lock_not_available then
    perform set_config('lock_timeout', v_lt, true);
    return jsonb_build_object('idle',true,'reason','capacity_in_flight','items','[]'::jsonb);
  end;$o$;
        n text := $n$  if not pg_try_advisory_xact_lock(hashtext('cf247 provider description capacity')) then return jsonb_build_object('idle',true,'reason','capacity_in_flight','items','[]'::jsonb); end if;$n$;
begin
  if (length(d) - length(replace(d, o, ''))) / length(o) <> 1 then raise exception 'next: the 20261110252000 block is not found exactly once'; end if;
  execute replace(d, o, n);
  if md5(pg_get_functiondef('public.svc_provider_description_next(integer)'::regprocedure)) <> '82bfe2daae5c95059ada6aa6305e0dde' then
    raise exception 'next is not the 20261110250000 body after the restore (%)', md5(pg_get_functiondef('public.svc_provider_description_next(integer)'::regprocedure));
  end if;
end $f$;

update pipeline.platform_toolset_settings set value = '1'::jsonb, updated_at = now(),
       reason = 'CF-247 F-PDESC 20261110253000: three calls a fire timed out on the lease; one call a fire, every 5 minutes instead'
 where toolset_key = 'pipeline' and key = 'pdesc.dispatch_max';
update pipeline.platform_toolset_settings set min_value = 5, value = '5'::jsonb, updated_at = now(),
       help = 'The job wakes every 5 minutes (at :01, :06, :11 ... :56) and sends the worker only when this long has passed since its last call.',
       reason = 'Platform Admin direction 10 Nov 2026 23:02 AEDT: fasten up; one worker call every 5 minutes (20261110253000)'
 where toolset_key = 'pipeline' and key = 'pdesc.every_minutes';

do $sched$
begin
  if to_regnamespace('cron') is not null then
    perform cron.alter_job((select jobid from cron.job where jobname = 'provider-description-read'), schedule := '1,6,11,16,21,26,31,36,41,46,51,56 * * * *');
    perform cron.alter_job((select jobid from cron.job where jobname = 'provider-description-self-heal'), schedule := '3,13,23,33,43,53 * * * *');
  end if;
end $sched$;

do $post$
begin
  if to_regnamespace('cron') is not null then
    if (select schedule from cron.job where jobname = 'provider-description-read') <> '1,6,11,16,21,26,31,36,41,46,51,56 * * * *' then raise exception 'post-check: reader schedule'; end if;
    if (select schedule from cron.job where jobname = 'provider-description-self-heal') <> '3,13,23,33,43,53 * * * *' then raise exception 'post-check: self-heal schedule'; end if;
  end if;
  if (select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'pdesc.every_minutes') <> '5'::jsonb then raise exception 'post-check: every_minutes'; end if;
end $post$;
