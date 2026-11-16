-- CF-247 consolidation PR 3: pipeline.field_execution_registry and coverage-lane-dispatch, in shadow (Platform Admin 16 Nov 2026 10:59: pulled
-- forward 24 hours for the 20 Nov delivery; 16:26 and 16:52: the API v3 field lanes; 22:45: proceed while PR 1 is held for its fix).
-- Pattern: Pilot CLAUDE.md "Cron dispatchers" (register each legacy job byte for byte with its own schedule, 24-hour shadow, then cutover), the
-- same design as consolidation PR 2 (20261115220000), whose run, tick and report functions are reused here renamed for coverage lanes.
--   1. pipeline.field_execution_registry: one row per lane.
--      worker_lane: a coverage-sweep worker lane taken over from a legacy pg_cron job (call_sql is the legacy command byte for byte, call_md5
--        guards it; schedule its cron schedule; budget and breaker as PR 2). Mode shadow records what was due and runs nothing; live runs it.
--      field_lane: an API v3 / request-register field lane (field, execution mode, uses_ai, owner, filling function, field dictionary paths,
--        request ids). Field lanes are declared state disabled and are never dispatched here: their fill functions run on demand or, later, as
--        their own switched-on lanes. The three filled on 16 Nov 21:50 (primary campus, campus-null reason, study load stage 1) were run on the
--        Platform Admin's instruction, not by a lane.
--   2. pipeline.coverage_lane_runs: one row per dispatch (telemetry).
--   3. security.coverage_lane_run_v1, procedure security.coverage_lane_tick_v1(lane) (jobs coverage-lane-dispatch, -b, -c, every minute) and
--      security.coverage_lane_shadow_report_v1(hours): as PR 2. Three lanes because the legacy calls take up to 84 s (reextract, contact page)
--      and share minutes.
-- Scope (read live 16 Nov 23:20 AEDT; 17 Nov 06:15 AEDT the Platform Admin left coverage-ai-match out, switched off at 06:00): the 13 Course pages and Enrichment worker lanes of the coverage-sweep worker on minute schedules:
--   course-link-search-worker, coverage-find-site, coverage-reextract, coverage-reidentify, provider-contact-page, provider-facts, companion-read, course-list-read, credential-read, policy-add-tests, programme-discover, programme-read, source-find.
-- Not taken (reported to the Platform Admin): coverage-ai-match (switched off on live 17 Nov 2026 06:00 AEDT; a later change adds it once it
--   runs again); calendar-reread (an intake calendar lane: S2-Intakes owns F-INT); coverage-read and
--   coverage-read-2 (schedule "30 seconds": a minute dispatcher cannot reproduce a sub-minute interval byte for byte); the Scholarships, Layer 2
--   reading, Platform upkeep and Reports worker jobs (other modules or not coverage lanes); platform-health; every job registered by PR 1
--   (pipeline.rollup_targets) or PR 2 (pipeline.admission_rules).
-- Shadow only: the 13 legacy jobs keep running exactly as they are. G1: the three dispatcher jobs are catalogued before they are scheduled.
-- G2: eight settings coverage_lane.* (inserted; no existing setting changes); the job commands have no number. G3: no consumer API object is
-- read or changed. Nothing dropped.
-- Replaces: nothing (shadow: no legacy job changes).
-- Retires: nothing (the cutover change switches the 13 legacy jobs off and retires them).

set local lock_timeout = '5s'; -- fixed: lock wait guard for the catalogue and cron writes below

-- 1. Settings (G2)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'coverage_lane.on', 'Coverage lane dispatch: on',
  'The coverage lane dispatcher checks every minute which coverage worker lanes are due on their own schedules. In shadow it only records what was due; the legacy jobs still run the lanes. 0 stops the dispatcher.',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 1840, 'Consolidation PR 3 (Platform Admin 16 Nov 2026 10:59): 24-hour shadow cycle', 'Coverage lane dispatch', 'security.coverage_lane_tick_v1 (jobs coverage-lane-dispatch, -b, -c)'),
 ('pipeline', 'coverage_lane.tick_budget_seconds', 'Coverage lane dispatch: start no lane after',
  'Seconds into a lane''s tick after which it starts no further lane; the rest stay due for the next tick or another lane.',
  'number', to_jsonb(60), 10, 100, 'seconds', 1841, 'Consolidation PR 3 (Platform Admin 16 Nov 2026 10:59)', 'Coverage lane dispatch', 'security.coverage_lane_tick_v1 (jobs coverage-lane-dispatch, -b, -c)'),
 ('pipeline', 'coverage_lane.tick_finish_by_seconds', 'Coverage lane dispatch: a live lane starts only if it can finish within',
  'A live lane starts only if the lane''s tick so far plus the lane''s longest recent run (or its budget) fits within this many seconds (the database stops any statement at 120 s). The first lane of a lane''s tick always starts.',
  'number', to_jsonb(100), 30, 110, 'seconds', 1842, 'Consolidation PR 3 (Platform Admin 16 Nov 2026 10:59)', 'Coverage lane dispatch', 'security.coverage_lane_tick_v1 (jobs coverage-lane-dispatch, -b, -c)'),
 ('pipeline', 'coverage_lane.keep_days', 'Coverage lane dispatch: keep run history for',
  'Days of pipeline.coverage_lane_runs kept; older rows are removed by the dispatcher. Also the window for each lane''s longest recent run.',
  'number', to_jsonb(14), 3, 60, 'days', 1843, 'Consolidation PR 3 (Platform Admin 16 Nov 2026 10:59)', 'Coverage lane dispatch', 'security.coverage_lane_tick_v1 (jobs coverage-lane-dispatch, -b, -c)'),
 ('pipeline', 'coverage_lane.catch_up_minutes', 'Coverage lane dispatch: look back for missed minutes at most',
  'When the dispatcher has not run for a while (a pause, maintenance), a lane due in the missed minutes runs once; minutes further back than this are not looked at.',
  'number', to_jsonb(180), 5, 1440, 'minutes', 1844, 'Consolidation PR 3 (Platform Admin 16 Nov 2026 10:59)', 'Coverage lane dispatch', 'security.coverage_lane_tick_v1 (jobs coverage-lane-dispatch, -b, -c)'),
 ('pipeline', 'coverage_lane.breaker_after_failures', 'Coverage lane dispatch: open a lane''s breaker after failures in a row',
  'A live lane that fails this many times in a row is skipped for a back-off period and a Platform health issue is raised; its next good run closes the breaker.',
  'number', to_jsonb(3), 1, 20, 'failures', 1845, 'Consolidation PR 3 (Platform Admin 16 Nov 2026 10:59)', 'Coverage lane dispatch', 'security.coverage_lane_run_v1'),
 ('pipeline', 'coverage_lane.breaker_backoff_minutes', 'Coverage lane dispatch: first back-off when a breaker opens',
  'How long a lane is skipped when its breaker first opens; each further failure doubles it, up to the longest back-off.',
  'number', to_jsonb(15), 1, 240, 'minutes', 1846, 'Consolidation PR 3 (Platform Admin 16 Nov 2026 10:59)', 'Coverage lane dispatch', 'security.coverage_lane_run_v1'),
 ('pipeline', 'coverage_lane.breaker_backoff_max_minutes', 'Coverage lane dispatch: longest back-off',
  'The longest a lane is skipped after repeated failures before it is tried again.',
  'number', to_jsonb(240), 15, 1440, 'minutes', 1847, 'Consolidation PR 3 (Platform Admin 16 Nov 2026 10:59)', 'Coverage lane dispatch', 'security.coverage_lane_run_v1')
on conflict do nothing;

-- 2. Tables
create table if not exists pipeline.field_execution_registry (
  lane_code text primary key,
  kind text not null check (kind in ('worker_lane', 'field_lane')),
  -- worker lanes
  legacy_job text unique,
  call_sql text,
  call_md5 text,
  schedule text,
  priority int not null default 50,
  enabled boolean not null default true,
  mode text not null default 'shadow' check (mode in ('shadow', 'live', 'disabled')),
  budget_ms int,
  expected_ms int,
  consecutive_failures int not null default 0,
  open_until timestamptz,
  last_due_at timestamptz,
  last_started_at timestamptz,
  last_finished_at timestamptz,
  last_status text,
  last_result text,
  last_error text,
  last_ms int,
  -- field lanes
  field text,
  execution_mode text check (execution_mode is null or execution_mode in ('deterministic_sql', 'staged_derivation', 'reference_seed', 'reference_sync', 'targeted_extraction')),
  uses_ai boolean,
  owner text,
  fill_function text,
  dictionary_paths text[] not null default '{}',
  req_ids text[] not null default '{}',
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint field_execution_registry_kind_shape check (
    (kind = 'worker_lane' and legacy_job is not null and call_sql is not null and call_md5 is not null and schedule is not null and mode in ('shadow', 'live'))
    or (kind = 'field_lane' and field is not null and execution_mode is not null and uses_ai is not null and owner is not null and call_sql is null and mode = 'disabled'))
);
comment on table pipeline.field_execution_registry is 'CF-247 consolidation PR 3 (16 Nov 2026): one row per lane. worker_lane: a coverage-sweep worker lane run by coverage-lane-dispatch (call_sql is the legacy job''s command byte for byte, call_md5 guards it, schedule its cron schedule, budget and breaker as the admission rule runner; mode shadow records what was due and runs nothing, live runs it). field_lane: an API v3 / request-register field (execution mode, uses_ai, owner, filling function, field dictionary paths, request ids), declared disabled and never dispatched here. A new coverage lane is a row here, not a new pg_cron job.';
alter table pipeline.field_execution_registry enable row level security;
revoke all on pipeline.field_execution_registry from anon, authenticated;

create table if not exists pipeline.coverage_lane_runs (
  id bigint generated always as identity primary key,
  tick_at timestamptz not null,
  lane text not null,
  lane_code text not null references pipeline.field_execution_registry(lane_code),
  mode text not null check (mode in ('shadow', 'live')),
  due_at timestamptz not null,
  due_minutes int not null,
  started_at timestamptz,
  finished_at timestamptz,
  ms int,
  status text not null check (status in ('shadow_due', 'succeeded', 'failed', 'deferred', 'refused', 'skipped_open')),
  over_budget boolean not null default false,
  result text,
  error text
);
comment on table pipeline.coverage_lane_runs is 'CF-247 consolidation PR 3 (16 Nov 2026): telemetry, one row per coverage-lane-dispatch dispatch (shadow_due, succeeded, failed, deferred, refused because call_sql changed, or skipped while the lane''s breaker is open), with the dispatcher lane, the time taken, whether it ran over budget and the answer. Kept for coverage_lane.keep_days.';
create index if not exists coverage_lane_runs_code_due_idx on pipeline.coverage_lane_runs(lane_code, due_at desc);
create index if not exists coverage_lane_runs_tick_idx on pipeline.coverage_lane_runs(tick_at);
alter table pipeline.coverage_lane_runs enable row level security;
revoke all on pipeline.coverage_lane_runs from anon, authenticated;

-- 3 to 5. Dispatch, tick and shadow report (consolidation PR 2's functions, renamed for coverage lanes)
-- 3. One dispatch
create or replace function security.coverage_lane_run_v1(p_code text, p_lane text, p_tick timestamptz, p_due timestamptz, p_due_minutes int)
 returns text
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_r pipeline.field_execution_registry; v_t0 timestamptz := clock_timestamp(); v_ms int; v_err text; v_out text; v_sql text; v_after int; v_back int; v_max int; v_until timestamptz;
begin
  select * into v_r from pipeline.field_execution_registry where lane_code = p_code for update skip locked;
  if not found then return 'locked'; end if;  -- another lane holds it
  if v_r.last_due_at is not null and v_r.last_due_at >= p_due then return 'already'; end if;  -- another lane ran it since this lane looked
  if v_r.kind <> 'worker_lane' then return 'not_a_worker_lane'; end if;  -- field lanes are run by their own fill functions, never dispatched here
  if md5(v_r.call_sql) <> v_r.call_md5 then
    insert into pipeline.coverage_lane_runs(tick_at, lane, lane_code, mode, due_at, due_minutes, started_at, finished_at, status, error)
    values (p_tick, p_lane, p_code, v_r.mode, p_due, p_due_minutes, v_t0, clock_timestamp(), 'refused', 'call_sql changed since registration (md5)');
    update pipeline.field_execution_registry set last_status = 'refused', last_error = 'call_sql changed since registration (md5)', updated_at = now() where lane_code = p_code;
    return 'refused';
  end if;
  if v_r.mode = 'shadow' then
    insert into pipeline.coverage_lane_runs(tick_at, lane, lane_code, mode, due_at, due_minutes, started_at, finished_at, ms, status)
    values (p_tick, p_lane, p_code, 'shadow', p_due, p_due_minutes, v_t0, clock_timestamp(), 0, 'shadow_due');
    update pipeline.field_execution_registry set last_due_at = p_due, last_status = 'shadow_due', updated_at = now() where lane_code = p_code;
    return 'shadow_due';
  end if;
  if v_r.open_until is not null and v_r.open_until > now() then
    insert into pipeline.coverage_lane_runs(tick_at, lane, lane_code, mode, due_at, due_minutes, started_at, finished_at, ms, status, error)
    values (p_tick, p_lane, p_code, 'live', p_due, p_due_minutes, v_t0, clock_timestamp(), 0, 'skipped_open', 'breaker open until ' || v_r.open_until);
    update pipeline.field_execution_registry set last_due_at = p_due, last_status = 'skipped_open', updated_at = now() where lane_code = p_code;
    return 'skipped_open';
  end if;
  -- a single statement keeps its answer as telemetry; a command of several statements runs as one
  v_sql := rtrim(v_r.call_sql, E'; \n\t');
  begin
    if position(';' in v_sql) = 0 then execute v_sql into v_out; else execute v_r.call_sql; end if;
    v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000)::int;
    insert into pipeline.coverage_lane_runs(tick_at, lane, lane_code, mode, due_at, due_minutes, started_at, finished_at, ms, status, over_budget, result)
    values (p_tick, p_lane, p_code, 'live', p_due, p_due_minutes, v_t0, clock_timestamp(), v_ms, 'succeeded', v_ms > coalesce(v_r.budget_ms, v_ms), left(v_out, 2000));
    update pipeline.field_execution_registry set last_due_at = p_due, last_started_at = v_t0, last_finished_at = clock_timestamp(), last_status = 'succeeded',
           last_result = left(v_out, 2000), last_error = null, last_ms = v_ms, consecutive_failures = 0, open_until = null, updated_at = now()
     where lane_code = p_code;
    if v_r.consecutive_failures > 0 then
      update pipeline.platform_issues set resolved_at = now(), last_seen = now()
       where check_key = 'coverage_lane_breaker:' || p_code and resolved_at is null;
    end if;
    return 'succeeded';
  exception when others then
    get stacked diagnostics v_err = message_text;
    v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000)::int;
    v_after := security.pipeline_num_v1('coverage_lane.breaker_after_failures', 3)::int;
    v_back := security.pipeline_num_v1('coverage_lane.breaker_backoff_minutes', 15)::int;
    v_max := security.pipeline_num_v1('coverage_lane.breaker_backoff_max_minutes', 240)::int;
    if v_r.consecutive_failures + 1 >= v_after then
      v_until := now() + make_interval(mins => least(v_max, v_back * power(2, greatest(0, v_r.consecutive_failures + 1 - v_after)))::int);
    end if;
    insert into pipeline.coverage_lane_runs(tick_at, lane, lane_code, mode, due_at, due_minutes, started_at, finished_at, ms, status, over_budget, error)
    values (p_tick, p_lane, p_code, 'live', p_due, p_due_minutes, v_t0, clock_timestamp(), v_ms, 'failed', v_ms > coalesce(v_r.budget_ms, v_ms), left(v_err, 1000));
    -- a failed run counts as run (as a failed cron run does): the next run is at the next scheduled minute, or after the back-off
    update pipeline.field_execution_registry set last_due_at = p_due, last_started_at = v_t0, last_finished_at = clock_timestamp(), last_status = 'failed',
           last_error = left(v_err, 1000), last_ms = v_ms, consecutive_failures = consecutive_failures + 1, open_until = coalesce(v_until, open_until), updated_at = now()
     where lane_code = p_code;
    if v_until is not null then
      if exists (select 1 from pipeline.platform_issues where check_key = 'coverage_lane_breaker:' || p_code and resolved_at is null) then
        update pipeline.platform_issues set last_seen = now(), occurrences = occurrences + 1,
               detail = jsonb_build_object('rule', p_code, 'failures_in_a_row', v_r.consecutive_failures + 1, 'skipped_until', v_until, 'last_error', left(v_err, 300))
         where check_key = 'coverage_lane_breaker:' || p_code and resolved_at is null;
      else
        insert into pipeline.platform_issues(check_key, severity, area, title, detail)
        values ('coverage_lane_breaker:' || p_code, 'warning', 'coverage sweep',  -- an area platform_issues allows (platform_issues_area_check)
                'Coverage lane ' || p_code || ' failed ' || (v_r.consecutive_failures + 1) || ' times in a row: skipped until ' || to_char(v_until at time zone 'UTC', 'HH24:MI') || ' UTC',
                jsonb_build_object('rule', p_code, 'failures_in_a_row', v_r.consecutive_failures + 1, 'skipped_until', v_until, 'last_error', left(v_err, 300)));
      end if;
    end if;
    return 'failed';
  end;
end $function$;
revoke all on function security.coverage_lane_run_v1(text, text, timestamptz, timestamptz, int) from public, anon, authenticated;

-- 4. One lane's tick (a procedure, so each dispatch commits on its own; not security definer, as a procedure that commits cannot be)
create or replace procedure security.coverage_lane_tick_v1(p_lane text)
 language plpgsql
as $function$
declare v_t0 timestamptz := clock_timestamp(); v_tick timestamptz := date_trunc('minute', now()); v_budget int; v_finish int; v_keep int; v_back int;
        v_r record; v_el numeric; v_n int := 0; v_res text;
begin
  if security.pipeline_num_v1('coverage_lane.on', 0) < 1 then return; end if;
  if not pg_try_advisory_lock(hashtext('cf247:coverage_lane_tick:' || p_lane)) then return; end if;  -- fixed: one tick per lane at a time
  v_budget := security.pipeline_num_v1('coverage_lane.tick_budget_seconds', 60)::int;
  v_finish := security.pipeline_num_v1('coverage_lane.tick_finish_by_seconds', 100)::int;
  v_keep := security.pipeline_num_v1('coverage_lane.keep_days', 14)::int;
  v_back := security.pipeline_num_v1('coverage_lane.catch_up_minutes', 180)::int;
  for v_r in
    select r.lane_code, r.mode, d.due_at, d.n,
           case when r.mode = 'shadow' then 0 else coalesce(e.max_ms, r.budget_ms, r.expected_ms, 0) end exp_ms
      from (select * from pipeline.field_execution_registry where kind = 'worker_lane') r
      cross join lateral (
        select max(m) due_at, count(*) n
          from generate_series(greatest(coalesce(r.last_due_at + interval '1 minute', v_tick), v_tick - make_interval(mins => v_back)), v_tick, interval '1 minute') m
         where security.cron_matches_v1(r.schedule, m)) d
      left join lateral (
        select max(x.ms) max_ms from pipeline.coverage_lane_runs x
         where x.lane_code = r.lane_code and x.status = 'succeeded' and x.started_at > now() - make_interval(days => v_keep)) e on true
     where r.enabled and d.due_at is not null
     order by d.due_at, r.priority, r.lane_code
  loop
    v_el := extract(epoch from clock_timestamp() - v_t0);
    if v_n > 0 and (v_el > v_budget or v_el + v_r.exp_ms / 1000.0 > v_finish) then
      continue;  -- stays due for another lane or the next tick
    end if;
    v_res := security.coverage_lane_run_v1(v_r.lane_code, p_lane, v_tick, v_r.due_at, v_r.n::int);
    if v_res not in ('locked', 'already') then v_n := v_n + 1; end if;
    commit;
  end loop;
  delete from pipeline.coverage_lane_runs where tick_at < now() - make_interval(days => v_keep);
  commit;
  perform pg_advisory_unlock(hashtext('cf247:coverage_lane_tick:' || p_lane));  -- fixed: one tick per lane at a time
end $function$;
revoke all on procedure security.coverage_lane_tick_v1(text) from public, anon, authenticated;

-- 5. The shadow report (acceptance for the cutover, 24-hour cycle)
create or replace function security.coverage_lane_shadow_report_v1(p_hours int default 24)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
declare v_from timestamptz; v_rows jsonb; v_lanes int; v_finish int; v_load jsonb;
begin
  select greatest(now() - make_interval(hours => p_hours), min(created_at)) into v_from from pipeline.field_execution_registry where kind = 'worker_lane';
  select count(*) into v_lanes from cron.job where jobname like 'coverage-lane-dispatch%' and active;
  v_finish := security.pipeline_num_v1('coverage_lane.tick_finish_by_seconds', 100)::int;
  select coalesce(jsonb_agg(x order by x->>'lane'), '[]'::jsonb) into v_rows from (
    select jsonb_build_object(
      'lane', r.lane_code, 'schedule', r.schedule, 'mode', r.mode, 'budget_ms', r.budget_ms,
      -- dispatches, not minutes: after a pause the runner catches the missed minutes up once, the legacy job not at all
      'runner_dispatches', coalesce(s.dispatches, 0),
      'legacy_starts', coalesce(l.starts, 0),
      'difference', coalesce(s.dispatches, 0) - coalesce(l.starts, 0),
      'max_lag_seconds', round(coalesce(s.lag, 0)::numeric, 1),
      'collapsed_dispatches', coalesce(s.collapsed, 0),
      'lanes_used', coalesce(s.lanes, 0),
      'legacy_failed', coalesce(l.failed, 0),
      'matches', abs(coalesce(s.dispatches, 0) - coalesce(l.starts, 0)) <= 1) x
      from pipeline.field_execution_registry r
      left join lateral (select count(*) dispatches, max(extract(epoch from x.started_at - x.due_at)) lag, count(*) filter (where x.due_minutes > 1) collapsed,
                                count(distinct x.lane) lanes
                           from pipeline.coverage_lane_runs x where x.lane_code = r.lane_code and x.due_at >= v_from
                            and x.status in ('shadow_due', 'succeeded', 'failed', 'skipped_open')) s on true
      left join lateral (select count(*) starts, count(*) filter (where d.status = 'failed') failed from cron.job j join cron.job_run_details d on d.jobid = j.jobid
                          where j.jobname = r.legacy_job and d.start_time >= v_from) l on true
     where r.kind = 'worker_lane') z(x);
  -- projected load: for each minute, the summed budgets of the rules due then, against the lanes' capacity
  select jsonb_build_object('lanes', v_lanes, 'capacity_seconds_per_minute', v_lanes * v_finish,
           'max_projected_seconds_in_a_minute', coalesce(round(max(t.s)::numeric, 1), 0),
           'minutes_over_capacity', count(*) filter (where t.s > v_lanes * v_finish))
    into v_load
    from (select x.due_at, sum(coalesce(r.budget_ms, 0)) / 1000.0 s from pipeline.coverage_lane_runs x join pipeline.field_execution_registry r on r.lane_code = x.lane_code
           where x.due_at >= v_from and x.status in ('shadow_due', 'succeeded', 'failed') group by x.due_at) t;
  return jsonb_build_object('from', v_from, 'to', now(), 'targets', jsonb_array_length(v_rows),
    'all_match', not exists (select 1 from jsonb_array_elements(v_rows) e where not (e->>'matches')::boolean), 'load', v_load, 'rows', v_rows);
end $function$;
revoke all on function security.coverage_lane_shadow_report_v1(int) from public, anon, authenticated;

-- 6. The 13 worker lanes, copied from the live legacy jobs (command and schedule byte for byte); budget = the legacy job's longest run in 7 days
insert into pipeline.field_execution_registry(lane_code, kind, legacy_job, call_sql, call_md5, schedule, priority, mode, budget_ms, expected_ms, owner, note)
select j.jobname, 'worker_lane', j.jobname, j.command, md5(j.command), j.schedule, 50, 'shadow',
       (select round(max(extract(epoch from d.end_time - d.start_time)) * 1000)::int
          from cron.job_run_details d where d.jobid = j.jobid and d.status = 'succeeded' and d.start_time > now() - make_interval(days => 7)),
       (select round(percentile_cont(0.95) within group (order by (extract(epoch from d.end_time - d.start_time) * 1000)::float8))::int
          from cron.job_run_details d where d.jobid = j.jobid and d.status = 'succeeded' and d.start_time > now() - make_interval(days => 7)),
       'S2 - SS Build (Course Module)', 'registered in shadow by 20261116220000; the legacy job still runs'
  from cron.job j
 where j.active and j.jobname in ('course-link-search-worker', 'coverage-find-site', 'coverage-reextract', 'coverage-reidentify', 'provider-contact-page', 'provider-facts', 'companion-read', 'course-list-read', 'credential-read', 'policy-add-tests', 'programme-discover', 'programme-read', 'source-find')
   and not exists (select 1 from pipeline.rollup_targets t where t.legacy_job = j.jobname)
   and not exists (select 1 from pipeline.admission_rules a where a.legacy_job = j.jobname)
on conflict (lane_code) do nothing;

-- 6b. The API v3 / request-register field lanes, declared disabled (Platform Admin 16 Nov 2026 16:26; owners and decisions 16:52)
insert into pipeline.field_execution_registry(lane_code, kind, mode, enabled, field, execution_mode, uses_ai, owner, fill_function, dictionary_paths, req_ids, note) values
 ('campus_is_primary', 'field_lane', 'disabled', false, 'catalogue.campuses.is_primary', 'deterministic_sql', false, 'S2 - SS Build', 'security.campus_primary_apply_v1',
  array['website:course:item.campuses[].is_primary', 'website:search:items[].campuses[].is_primary', 'zoho:course:item.campuses[].is_primary', 'zoho:courses:items[].campuses[].is_primary', 'zoho:search:items[].campuses[].is_primary'],
  array['REQ-75'], 'D-4 confirmed 16 Nov 16:52: exact CRICOS registered-address match to one active campus, or manual; run once on demand 16 Nov 21:50 (356)'),
 ('course_empty_reason', 'field_lane', 'disabled', false, 'catalogue.courses.empty_reason_code', 'deterministic_sql', false, 'S2 - SS Build', 'security.course_empty_reason_apply_v1',
  array['website:course:item.empty_reason_code (PR D)', 'zoho:course:item.empty_reason_code (PR D)'], array['REQ-53'], 'from stored evidence only; run once on demand 16 Nov 21:50 (5,639)'),
 ('course_study_load', 'field_lane', 'disabled', false, 'catalogue.courses.study_load', 'staged_derivation', true, 'S2 - SS Build', 'security.course_study_load_stage1_v1',
  array['website:course:item.study_load (PR D)', 'zoho:course:item.study_load (PR D)'], array['REQ-52'], 'stage 1 from stated page evidence, no AI (run once 16 Nov 21:50: 2,521); stage 2 an AI question on the existing reader, off'),
 ('provider_accreditations', 'field_lane', 'disabled', false, 'catalogue.provider_accreditations', 'targeted_extraction', false, 'S2 - SS Build', 'security.provider_accreditation_apply_v1',
  array['website:provider:item.accreditations[] (PR D)', 'zoho:provider:item.accreditations[] (PR D)'], array['REQ-57'], 'D-3: AACSB, EQUIS, AMBA official lists, exact name or domain match; PR C Wed 18 Nov'),
 ('grade_scale_conversions', 'field_lane', 'disabled', false, 'ref.grade_scale_conversions / catalogue.entry_grade_normalisations', 'deterministic_sql', false, 'S2 - SS Build', 'security.entry_grade_normalise_v1',
  array['website:provider:item.entry_matrix[].min_grade_normalised (PR D)', 'zoho:provider:item.entry_matrix[].min_grade_normalised (PR D)'], array['REQ-19'], 'decided 16 Nov 16:52: position on the qualification''s own official scale; approved scales only; PR E Tue 17 Nov'),
 ('destination_editions', 'field_lane', 'disabled', false, 'destination.editions and its rows', 'reference_seed', false, 'S2 - SS Build', 'security.destination_import_v1',
  array['website:reference:destination.* (PR D)'], array['REQ-65', 'REQ-67', 'REQ-68'], 'drafts unpublished until Study Square approves terms (REQ-68); PR E Tue 17 Nov'),
 ('api_field_dictionary', 'field_lane', 'disabled', false, 'ref.api_field_dictionary', 'reference_sync', false, 'S2 - SS Build', 'security.api_field_dictionary_sync_v1',
  array['(the dictionary itself)'], array['REQ-76'], 'Pilot #1162, migration 20261116110000: 1,923 fields; re-synced with PR D')
on conflict (lane_code) do nothing;

-- 7. The three dispatcher jobs: catalogued (G1), registered, then scheduled
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('coverage-lane-dispatch', 'Course pages', 1, 'Coverage lane dispatch, lane a (24-hour shadow)',
  'Every minute: works out which coverage worker lanes in pipeline.field_execution_registry are due on their own schedules and dispatches them, with a time budget and a circuit breaker per lane, within Settings > Pipeline settings > Coverage lane dispatch. Three lanes (a, b, c) share the work; a coverage lane runs on one lane only. In shadow (now) it only records what was due; the legacy jobs still run the lanes until the cutover.',
  6, false, null),
 ('coverage-lane-dispatch-b', 'Course pages', 2, 'Coverage lane dispatch, lane b (24-hour shadow)',
  'Second lane of the coverage lane dispatcher: the same coverage lanes, so two lanes due in the same minute run side by side. In shadow it only records what was due.',
  6, false, null),
 ('coverage-lane-dispatch-c', 'Course pages', 3, 'Coverage lane dispatch, lane c (24-hour shadow)',
  'Third lane of the coverage lane dispatcher. In shadow it only records what was due.',
  6, false, null)
on conflict (jobname) do nothing;

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('job', 'coverage-lane-dispatch', 'Platform', 'Course pages', 'CF-247 consolidation PR 3: coverage lane dispatcher, lane a (24-hour shadow; legacy jobs still run the lanes)', 'active', '{}', '20261116220000'),
 ('job', 'coverage-lane-dispatch-b', 'Platform', 'Course pages', 'CF-247 consolidation PR 3: coverage lane dispatcher, lane b', 'active', '{}', '20261116220000'),
 ('job', 'coverage-lane-dispatch-c', 'Platform', 'Course pages', 'CF-247 consolidation PR 3: coverage lane dispatcher, lane c', 'active', '{}', '20261116220000'),
 ('table', 'pipeline.field_execution_registry', 'Platform', 'Course pages', 'Coverage worker lanes (dispatched) and API v3 field lanes (declared)', 'active', '{}', '20261116220000'),
 ('table', 'pipeline.coverage_lane_runs', 'Platform', 'Course pages', 'Telemetry: one row per coverage lane dispatch', 'active', '{}', '20261116220000'),
 ('function', 'security.coverage_lane_tick_v1', 'Platform', 'Course pages', 'One lane tick of the coverage lane dispatcher (procedure)', 'active', '{}', '20261116220000'),
 ('function', 'security.coverage_lane_run_v1', 'Platform', 'Course pages', 'One coverage lane dispatch (shadow records; live runs with budget and breaker)', 'active', '{}', '20261116220000'),
 ('function', 'security.coverage_lane_shadow_report_v1', 'Platform', 'Course pages', '24-hour shadow acceptance report for the coverage lane dispatcher', 'active', '{}', '20261116220000')
on conflict do nothing;

do $c$ begin
  if to_regnamespace('cron') is null then return; end if;
  if not exists (select 1 from cron.job where jobname = 'coverage-lane-dispatch') then
    perform cron.schedule('coverage-lane-dispatch', '* * * * *', $j$call security.coverage_lane_tick_v1('a')$j$);
  end if;
  if not exists (select 1 from cron.job where jobname = 'coverage-lane-dispatch-b') then
    perform cron.schedule('coverage-lane-dispatch-b', '* * * * *', $j$call security.coverage_lane_tick_v1('b')$j$);
  end if;
  if not exists (select 1 from cron.job where jobname = 'coverage-lane-dispatch-c') then
    perform cron.schedule('coverage-lane-dispatch-c', '* * * * *', $j$call security.coverage_lane_tick_v1('c')$j$);
  end if;
end $c$;

-- 8. Post-checks
do $$
declare v_n int;
begin
  if to_regnamespace('cron') is not null then
    select count(*) into v_n from pipeline.field_execution_registry r join cron.job j on j.jobname = r.legacy_job
     where r.kind = 'worker_lane' and r.mode = 'shadow' and r.call_sql = j.command and r.call_md5 = md5(j.command) and r.schedule = j.schedule and j.active;
    if v_n <> 13 then raise exception 'post-check: % of 13 coverage lanes match their live legacy job', v_n; end if;
    if (select count(*) from cron.job where jobname in ('coverage-lane-dispatch', 'coverage-lane-dispatch-b', 'coverage-lane-dispatch-c') and schedule = '* * * * *' and active
          and command in ($j$call security.coverage_lane_tick_v1('a')$j$, $j$call security.coverage_lane_tick_v1('b')$j$, $j$call security.coverage_lane_tick_v1('c')$j$)) <> 3 then
      raise exception 'post-check: the three coverage-lane-dispatch jobs';
    end if;
    if exists (select 1 from pipeline.field_execution_registry r where r.legacy_job in ('calendar-reread', 'coverage-read', 'coverage-read-2', 'coverage-ai-match', 'platform-health')
                 or exists (select 1 from pipeline.rollup_targets t where t.legacy_job = r.legacy_job)
                 or exists (select 1 from pipeline.admission_rules a where a.legacy_job = r.legacy_job)) then
      raise exception 'post-check: a job kept separate or held by another dispatcher was registered';
    end if;
  end if;
  if exists (select 1 from pipeline.field_execution_registry where kind = 'worker_lane' and mode <> 'shadow') then raise exception 'post-check: a lane is live (this change is shadow only)'; end if;
  if (select count(*) from pipeline.field_execution_registry where kind = 'field_lane' and mode = 'disabled' and not enabled) <> 7 then raise exception 'post-check: the seven field lanes are declared disabled'; end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key like 'coverage_lane.%') <> 8 then raise exception 'post-check: settings'; end if;
end $$;
