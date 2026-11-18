-- CF-247 S2 - BOOST (Platform Admin 18 Nov 2026 07:08, decisions 1 and 5), with worker coverage-sweep v1.0.12.
-- What it does:
--   1. Decision 1, the international study load first. Worker v1.0.12 (boost.ts, prompt boost-study-load-v2, selector study-load-windows-v3)
--      reports the study load a page states for international students when it states one (a student visa condition counts) and the course's
--      general study load only when it does not; its page check refuses an answer that passes over such a sentence, and refuses a sentence
--      that only defines full-time or part-time study. The stored pages read under the earlier rule are given back (state released) and read
--      again. What the earlier rule staged stays as it is: shadow or refused, never promoted (promotion only takes rows in state staged).
--   2. Decision 5, no more "a dispatcher tick is running" skips. New setting boost.yield_to_dispatchers (0): the Boost gate looks at the
--      dispatcher locks only when it is 1. Boost extraction and Boost ingestion write only Boost's own tables and Storage, and promotion fills
--      a course's study load only where it is empty, under its own lock; neither needs a dispatcher's lock.
--   3. Throughput of the second reading: a run reads 80 pages (was 40), 4 at a time (new setting reading.boost_extract_parallel).
--   4. A second benchmark run, bench-2, of the three named candidates under the new prompt (setting boost.benchmark_label), 24 pages a run.
--   5. Job boost-extract is switched on again. The platform's idle check (flag-recheck) paused it at 07:30 on 18 Nov 2026 because its last 30
--      runs found nothing to do; this migration gives it work (item 1), and the idle check itself says a paused job resumes when work arrives.
--      (This file was 20261118073000; its post-check required the job to be active and stopped the deploy, so nothing of it was applied.)
-- What it does not do: it qualifies no model for admission and admits nothing. Everything Boost stages stays shadow.
-- G1: no new job. G2: every value is a setting; the job commands hold no number. G3: no consumer API object is changed.
-- Replaces: security.boost_ingest_gate_v1 of migration 20261118000100 (same checks; the dispatcher-lock check now reads setting boost.yield_to_dispatchers)
-- Retires: nothing

set local lock_timeout = '5s';

do $pre$
declare v text;
begin
  v := md5(pg_get_functiondef('security.boost_ingest_gate_v1(boolean,timestamptz)'::regprocedure));
  if v <> 'fdcd9973d9029a80479ac0ec71384755' then raise exception 'security.boost_ingest_gate_v1 is not the definition this migration replaces (md5 %)', v; end if;
  if to_regclass('pipeline.boost_benchmark_items') is null then raise exception 'migration 20261118020000 is not applied'; end if;
end $pre$;

-- 1. Settings
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'boost.yield_to_dispatchers', 'Boost: wait for the dispatcher ticks (1) or not (0)',
  'When 1, Boost extraction and Boost ingestion do not start while a tick of rollup-scheduler, admission-rule-runner or coverage-lane-dispatch holds its lock. When 0 they run beside the ticks. Boost writes only its own tables and fills a study load only where a course has none, so 0 is safe; set 1 only if Boost is seen to slow a dispatcher.',
  'number', to_jsonb(0), 0, 1, 'switch', 956, 'CF-247 Boost, Platform Admin 18 Nov 2026 07:08 (decision 5: no more skips for a running dispatcher tick)', 'Boost',
  'security.boost_ingest_gate_v1 (jobs boost-extract and worker-boost-bulk-ingest)'),
 ('pipeline', 'reading.boost_extract_parallel', 'Boost extraction: pages read at the same time',
  'How many stored pages one run of Boost extraction reads at the same time. Each page is still one call to the one routed model. More is faster; the route''s daily caps still apply.',
  'number', to_jsonb(4), 1, 8, 'pages', 957, 'CF-247 Boost, Platform Admin 18 Nov 2026 07:08 (the stored pages are read again under the international-first rule today)', 'Boost',
  'worker coverage-sweep mode boost_extract (boost.ts boostParallel)')
on conflict (toolset_key, key) do nothing;

update pipeline.platform_toolset_settings s set value = v.value, reason = v.reason, updated_at = now()
  from (values ('batch.boost_extract', to_jsonb(80), 'CF-247 Boost, Platform Admin 18 Nov 2026 07:08: the stored pages are read again under the international-first rule today'),
               ('batch.boost_benchmark', to_jsonb(24), 'CF-247 Boost, Platform Admin 18 Nov 2026 07:08: benchmark run bench-2 under prompt boost-study-load-v2'),
               ('boost.benchmark_label', to_jsonb('bench-2'::text), 'CF-247 Boost, Platform Admin 18 Nov 2026 07:08: benchmark run bench-2 under prompt boost-study-load-v2 (international study load first)')) v(key, value, reason)
 where s.toolset_key = 'pipeline' and s.key = v.key;

-- 2. The gate: as migration 20261118000100; the dispatcher-lock check behind setting boost.yield_to_dispatchers
create or replace function security.boost_ingest_gate_v1(p_check_locks boolean default true, p_now timestamptz default now())
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
declare
  v_min  int := (extract(hour from (p_now at time zone 'Australia/Melbourne')) * 60 + extract(minute from (p_now at time zone 'Australia/Melbourne')))::int;
  v_from int := security.pipeline_num_v1('boost.ingest_window_start_minute', 65)::int;
  v_to   int := security.pipeline_num_v1('boost.ingest_window_end_minute', 290)::int;
  v_bs   numeric := security.pipeline_num_v1('boost.ingest_blackout_start_epoch', 1795012200);
  v_be   numeric := security.pipeline_num_v1('boost.ingest_blackout_end_epoch', 1795019400);
  v_hk   int := security.pipeline_num_v1('boost.ingest_after_housekeeping_minutes', 20)::int;
  v_hk_start timestamptz; v_hk_running boolean;
  v_held text[];
  v_settings jsonb := jsonb_build_object('files_per_run', security.pipeline_num_v1('boost.ingest_files_per_run', 4)::int,
                                         'rows_per_call', security.pipeline_num_v1('boost.ingest_rows_per_call', 500)::int);
begin
  if security.pipeline_num_v1('boost.ingest_on', 1) < 1 then return jsonb_build_object('ok', false, 'reason', 'switched off (boost.ingest_on)'); end if;
  if security.maintenance_hold_v1() then return jsonb_build_object('ok', false, 'reason', 'Pipeline Maintenance Mode'); end if;
  -- on demand (setting boost.on_demand_until_epoch, Platform Admin 17 Nov 2026 22:48): until that time the overnight window does not apply; the
  -- squash blackout, Maintenance Mode, housekeeping-daily and the dispatcher locks below still do
  if not (v_min >= v_from and v_min < v_to) and not security.boost_on_demand_v1(p_now) then
    return jsonb_build_object('ok', false, 'reason', 'outside the window', 'melbourne_minute', v_min, 'window', jsonb_build_array(v_from, v_to));
  end if;
  if extract(epoch from p_now) >= v_bs and extract(epoch from p_now) < v_be then
    return jsonb_build_object('ok', false, 'reason', 'blackout (migration squash)');
  end if;
  select max(d.start_time), bool_or(d.status = 'running') into v_hk_start, v_hk_running
    from cron.job_run_details d join cron.job j on j.jobid = d.jobid
   where j.jobname = 'housekeeping-daily' and d.start_time > p_now - interval '1 day';  -- fixed: the look-back for the daily job's last start
  if coalesce(v_hk_running, false) or (v_hk_start is not null and v_hk_start > p_now - make_interval(mins => v_hk)) then
    return jsonb_build_object('ok', false, 'reason', 'housekeeping-daily running or just started', 'housekeeping_started', v_hk_start);
  end if;
  -- Platform Admin 18 Nov 2026 07:08 (decision 5): Boost yields to the dispatcher ticks only when setting boost.yield_to_dispatchers is 1.
  -- It is 0: Boost writes only its own tables and Storage staging-boost, and fills a course's study load only where it is empty, so it does
  -- not need a dispatcher's lock; some ticks hold theirs for longer than Boost can wait (50 extraction and 17 ingestion runs skipped in 5 hours).
  if p_check_locks and security.pipeline_num_v1('boost.yield_to_dispatchers', 0) >= 1 then
    -- the tick locks of PR 1, PR 2 and PR 3 (session advisory locks taken by their ticks)
    select array_agg(k.name) into v_held
      from (values ('rollup-scheduler', 'cf247:rollup_tick'),
                   ('admission-rule-runner', 'cf247:admission_tick:a'), ('admission-rule-runner-b', 'cf247:admission_tick:b'), ('admission-rule-runner-c', 'cf247:admission_tick:c'),
                   ('coverage-lane-dispatch', 'cf247:coverage_lane_tick:a'), ('coverage-lane-dispatch-b', 'cf247:coverage_lane_tick:b'), ('coverage-lane-dispatch-c', 'cf247:coverage_lane_tick:c')) k(name, lock_key)
     where exists (select 1 from pg_catalog.pg_locks l
                    where l.locktype = 'advisory' and l.granted and l.objsubid = 1
                      and ((l.classid::bigint << 32) | l.objid::bigint) = hashtext(k.lock_key)::bigint);
    if v_held is not null then return jsonb_build_object('ok', false, 'reason', 'a dispatcher tick is running', 'held', to_jsonb(v_held), 'settings', v_settings); end if;
  end if;
  return jsonb_build_object('ok', true, 'melbourne_minute', v_min, 'settings', v_settings);
end $function$;

update pipeline.automation_catalogue set description = replace(description, ', and only when no PR 1, PR 2 or PR 3 tick holds its lock', ' (it waits for the dispatcher ticks only when setting boost.yield_to_dispatchers is 1)')
 where jobname = 'worker-boost-bulk-ingest';

-- 3. The route's prompt version (the route runs the same one model; admission still needs pipeline.boost_model_qualifications)
update pipeline.ai_route_qualifications set prompt_version = 'boost-study-load-v2',
       note = coalesce(note, '') || ' | 18 Nov 2026: prompt boost-study-load-v2 (Platform Admin 07:08, the international study load first)'
 where service_code in ('boost_extract', 'boost_extract_benchmark') and prompt_version = 'boost-study-load-v1';

-- 4. The stored pages read under the earlier rule are read again
update pipeline.boost_extract_items set state = 'released', note = 'read again under boost-study-load-v2 (worker v1.0.12, international study load first)', done_at = now()
 where state in ('verified', 'rejected', 'failed');

-- 5. Work has arrived for job boost-extract: on again if the idle check paused it
select cron.alter_job((select jobid from cron.job where jobname = 'boost-extract'), active := true)
 where exists (select 1 from cron.job where jobname = 'boost-extract' and not active);

-- 6. Post-checks
do $c$
begin
  if security.pipeline_num_v1('boost.yield_to_dispatchers', 1) <> 0 or security.pipeline_num_v1('reading.boost_extract_parallel', 0) <> 4 then raise exception 'post-check: the new settings are not as set'; end if;
  if security.boost_ingest_gate_v1(true, '2026-11-18 12:00+11')->>'reason' = 'a dispatcher tick is running' then raise exception 'post-check: the gate still yields to a dispatcher tick'; end if;
  if (security.boost_ingest_gate_v1(true, '2026-11-19 01:20+11')->>'ok')::boolean or (security.boost_extract_gate_v1(true, '2026-11-19 03:29+11')->>'ok')::boolean then
    raise exception 'post-check: a Boost gate is open inside the squash lock (Thu 01:15 to 03:30)';
  end if;
  if security.boost_ingest_gate_v1(true, '2026-11-19 01:20+11')->>'reason' <> 'blackout (migration squash)' then raise exception 'post-check: the squash blackout is not what closes the gate on Thursday 01:20'; end if;
  if exists (select 1 from pipeline.boost_extract_items where state in ('verified', 'rejected', 'failed')) then raise exception 'post-check: a page read under the earlier rule was not given back'; end if;
  if exists (select 1 from pipeline.boost_model_qualifications) then raise exception 'post-check: a model is qualified for admission; this migration qualifies none'; end if;
  if exists (select 1 from pipeline.boost_inbound_staging where promotion_state = 'admitted') then raise exception 'post-check: a Boost row is admitted; this migration admits none'; end if;
  if not (select active from cron.job where jobname = 'boost-extract') then raise exception 'post-check: job boost-extract is not on'; end if;
  -- the other two Boost jobs may be paused by the platform's idle check at any time; that is not this migration's business
  if exists (select 1 from cron.job where jobname in ('boost-extract', 'worker-boost-bulk-ingest', 'boost-benchmark') and (command ~ '''limit'', [0-9]')) then
    raise exception 'post-check: a Boost job command holds a number';
  end if;
  if (select count(*) from pipeline.ai_route_qualifications where service_code in ('boost_extract', 'boost_extract_benchmark') and prompt_version = 'boost-study-load-v2') <> 4 then
    raise exception 'post-check: the route qualifications do not name prompt boost-study-load-v2';
  end if;
  if (security.toolset_setting('pipeline', 'boost.benchmark_label') #>> '{}') <> 'bench-2' then raise exception 'post-check: the benchmark label is not bench-2'; end if;
end $c$;
