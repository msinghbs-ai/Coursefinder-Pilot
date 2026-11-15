-- CF-247 consolidation PR 1: pipeline.rollup_targets and the job rollup-scheduler, in shadow (Platform Admin 15 Nov 2026 20:38, approving the
-- job governance blueprint; choices 21:1x: each target keeps its current cron schedule, the search projection writers stay dedicated jobs,
-- the Rollups panel ships with the cutover). Scope: project doc claude/rollup-scheduler-pr1-scope.md.
--   1. pipeline.rollup_targets: one row per report or cache refresh (Group A: 26 admin report and screen cache jobs), holding the legacy
--      job's command byte for byte (call_sql, with its md5) and its cron schedule. pipeline.rollup_runs: one row per dispatch.
--   2. security.cron_matches_v1(schedule, at): whether a five-field cron schedule (UTC, as pg_cron here) starts at that minute.
--   3. security.rollup_run_target_v1(code, tick, due, minutes): one dispatch. In shadow it records that the target was due and runs nothing;
--      live it runs call_sql in its own exception block and records the result. It refuses a call_sql whose md5 changed since registration.
--   4. security.rollup_tick_v1() (a procedure; job rollup-scheduler, every minute, command "call security.rollup_tick_v1()"): one tick at a
--      time; a target is due when its schedule matched a minute since its last due minute (missed minutes are caught up once, within
--      rollup.catch_up_minutes); frequent targets first, then the oldest due; no target starts after rollup.tick_budget_seconds, and a live
--      target starts only if its longest recent run still finishes within rollup.tick_finish_by_seconds (the first target of a tick always
--      starts); each dispatch commits on its own. The tick keeps the database's 120 s statement limit (no time limit is raised).
--   5. security.rollup_shadow_report_v1(days): per target, the minutes the scheduler found due against the legacy job's starts, and the
--      largest dispatch lag (acceptance for the cutover: equal within one a day, lag within one tick).
-- Shadow only: every target is registered in mode 'shadow'. The 26 legacy jobs keep running exactly as they are; nothing they do changes.
-- The cutover (targets live, legacy jobs switched off and retiring) is a separate change after the shadow week, with the Platform Admin's
-- approval; a passing shadow switches nothing on by itself.
-- G1: the new job is catalogued before it is scheduled and registered. G2: five settings (inserted; no existing setting changes); the job
-- command has no number. G3: no consumer API object is read or changed; the consumer-facing caches (Group B) are not registered here.
-- Replaces: nothing (shadow: no legacy job changes).
-- Retires: nothing (the cutover change retires the legacy jobs).

set local lock_timeout = '5s';

-- 1. Settings (G2)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'rollup.scheduler_on', 'Rollup scheduler: on',
  'The rollup scheduler checks every minute which report and cache refreshes are due. In shadow it only records what was due; the legacy jobs still run them. 0 stops the scheduler.',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 1820, 'Consolidation PR 1 (Platform Admin 15 Nov 2026 20:38): shadow week', 'Rollup scheduler', 'security.rollup_tick_v1 (job rollup-scheduler)'),
 ('pipeline', 'rollup.tick_budget_seconds', 'Rollup scheduler: start no target after',
  'Seconds into a tick after which no further target starts; the rest stay due for the next tick.',
  'number', to_jsonb(60), 10, 100, 'seconds', 1821, 'Consolidation PR 1 (Platform Admin 15 Nov 2026 20:38)', 'Rollup scheduler', 'security.rollup_tick_v1 (job rollup-scheduler)'),
 ('pipeline', 'rollup.tick_finish_by_seconds', 'Rollup scheduler: a live target starts only if it can finish within',
  'A live target starts only if the tick so far plus its longest recent run fits within this many seconds (the database stops any statement at 120 s). The first target of a tick always starts.',
  'number', to_jsonb(100), 30, 110, 'seconds', 1822, 'Consolidation PR 1 (Platform Admin 15 Nov 2026 20:38)', 'Rollup scheduler', 'security.rollup_tick_v1 (job rollup-scheduler)'),
 ('pipeline', 'rollup.keep_days', 'Rollup scheduler: keep run history for',
  'Days of pipeline.rollup_runs kept; older rows are removed by the scheduler. Also the window for each target''s longest recent run.',
  'number', to_jsonb(14), 3, 60, 'days', 1823, 'Consolidation PR 1 (Platform Admin 15 Nov 2026 20:38)', 'Rollup scheduler', 'security.rollup_tick_v1 (job rollup-scheduler)'),
 ('pipeline', 'rollup.catch_up_minutes', 'Rollup scheduler: look back for missed minutes at most',
  'When the scheduler has not run for a while (a pause, maintenance), a target due in the missed minutes runs once; minutes further back than this are not looked at.',
  'number', to_jsonb(180), 5, 1440, 'minutes', 1824, 'Consolidation PR 1 (Platform Admin 15 Nov 2026 20:38)', 'Rollup scheduler', 'security.rollup_tick_v1 (job rollup-scheduler)')
on conflict do nothing;

-- 2. Tables
create table if not exists pipeline.rollup_targets (
  target_code text primary key,
  legacy_job text unique,
  call_sql text not null,
  call_md5 text not null,
  schedule text not null,
  rollup_group text not null check (rollup_group in ('A', 'B')),
  priority int not null default 50,
  enabled boolean not null default true,
  mode text not null default 'shadow' check (mode in ('shadow', 'live')),
  expected_ms int,
  last_due_at timestamptz,
  last_started_at timestamptz,
  last_finished_at timestamptz,
  last_status text,
  last_error text,
  last_ms int,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table pipeline.rollup_targets is 'CF-247 consolidation PR 1 (15 Nov 2026): one row per report or cache refresh run by the job rollup-scheduler. call_sql is the legacy job''s command byte for byte (call_md5 guards it), schedule its cron schedule; mode shadow records what was due and runs nothing, live runs it. A new rollup is a row here, not a new pg_cron job.';
alter table pipeline.rollup_targets enable row level security;
revoke all on pipeline.rollup_targets from anon, authenticated;

create table if not exists pipeline.rollup_runs (
  id bigint generated always as identity primary key,
  tick_at timestamptz not null,
  target_code text not null references pipeline.rollup_targets(target_code),
  mode text not null check (mode in ('shadow', 'live')),
  due_at timestamptz not null,
  due_minutes int not null,
  started_at timestamptz,
  finished_at timestamptz,
  ms int,
  status text not null check (status in ('shadow_due', 'succeeded', 'failed', 'deferred', 'refused')),
  error text
);
comment on table pipeline.rollup_runs is 'CF-247 consolidation PR 1 (15 Nov 2026): one row per rollup-scheduler dispatch (shadow_due, succeeded, failed, deferred to the next tick, or refused because call_sql changed). due_minutes is how many scheduled minutes the dispatch covers (more than 1 after a missed tick). Kept for rollup.keep_days.';
create index if not exists rollup_runs_target_due_idx on pipeline.rollup_runs(target_code, due_at desc);
create index if not exists rollup_runs_tick_idx on pipeline.rollup_runs(tick_at);
alter table pipeline.rollup_runs enable row level security;
revoke all on pipeline.rollup_runs from anon, authenticated;

-- 3. Cron schedule matching (pg_cron here runs in GMT: cron.timezone)
create or replace function security.cron_field_matches_v1(p_field text, p_value int, p_min int, p_max int)
 returns boolean
 language plpgsql
 immutable
 set search_path to ''
as $function$
declare v_part text; v_range text; v_step int; v_a int; v_b int;
begin
  foreach v_part in array string_to_array(p_field, ',') loop
    v_range := split_part(v_part, '/', 1);
    v_step := coalesce(nullif(split_part(v_part, '/', 2), '')::int, 1);
    if v_range = '*' then v_a := p_min; v_b := p_max;
    elsif v_range like '%-%' then v_a := split_part(v_range, '-', 1)::int; v_b := split_part(v_range, '-', 2)::int;
    else v_a := v_range::int; v_b := case when v_part like '%/%' then p_max else v_a end;
    end if;
    if p_value between v_a and v_b and (p_value - v_a) % v_step = 0 then return true; end if;
  end loop;
  return false;
end $function$;

create or replace function security.cron_matches_v1(p_schedule text, p_at timestamptz)
 returns boolean
 language plpgsql
 stable
 set search_path to ''
as $function$
declare v_f text[] := regexp_split_to_array(btrim(p_schedule), '\s+'); v_t timestamp := p_at at time zone 'UTC'; v_dow int; v_dom_ok boolean; v_dow_ok boolean;
begin
  if coalesce(array_length(v_f, 1), 0) <> 5 then return false; end if;  -- an interval schedule ('30 seconds') is not a cron expression
  if not security.cron_field_matches_v1(v_f[1], extract(minute from v_t)::int, 0, 59)
     or not security.cron_field_matches_v1(v_f[2], extract(hour from v_t)::int, 0, 23)
     or not security.cron_field_matches_v1(v_f[4], extract(month from v_t)::int, 1, 12) then
    return false;
  end if;
  v_dow := extract(dow from v_t)::int;
  v_dom_ok := security.cron_field_matches_v1(v_f[3], extract(day from v_t)::int, 1, 31);
  v_dow_ok := security.cron_field_matches_v1(v_f[5], v_dow, 0, 7) or (v_dow = 0 and security.cron_field_matches_v1(v_f[5], 7, 0, 7));
  -- cron: when both day of month and day of week are restricted, either may match
  if v_f[3] <> '*' and v_f[5] <> '*' then return v_dom_ok or v_dow_ok; end if;
  return v_dom_ok and v_dow_ok;
end $function$;

-- 4. One dispatch
create or replace function security.rollup_run_target_v1(p_code text, p_tick timestamptz, p_due timestamptz, p_due_minutes int)
 returns text
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_t pipeline.rollup_targets; v_t0 timestamptz := clock_timestamp(); v_ms int; v_err text;
begin
  select * into v_t from pipeline.rollup_targets where target_code = p_code for update skip locked;
  if not found then return 'locked'; end if;
  if md5(v_t.call_sql) <> v_t.call_md5 then
    insert into pipeline.rollup_runs(tick_at, target_code, mode, due_at, due_minutes, started_at, finished_at, status, error)
    values (p_tick, p_code, v_t.mode, p_due, p_due_minutes, v_t0, clock_timestamp(), 'refused', 'call_sql changed since registration (md5)');
    update pipeline.rollup_targets set last_status = 'refused', last_error = 'call_sql changed since registration (md5)', updated_at = now() where target_code = p_code;
    return 'refused';
  end if;
  if v_t.mode = 'shadow' then
    insert into pipeline.rollup_runs(tick_at, target_code, mode, due_at, due_minutes, started_at, finished_at, ms, status)
    values (p_tick, p_code, 'shadow', p_due, p_due_minutes, v_t0, clock_timestamp(), 0, 'shadow_due');
    update pipeline.rollup_targets set last_due_at = p_due, last_status = 'shadow_due', updated_at = now() where target_code = p_code;
    return 'shadow_due';
  end if;
  begin
    execute v_t.call_sql;
    v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000)::int;
    insert into pipeline.rollup_runs(tick_at, target_code, mode, due_at, due_minutes, started_at, finished_at, ms, status)
    values (p_tick, p_code, 'live', p_due, p_due_minutes, v_t0, clock_timestamp(), v_ms, 'succeeded');
    update pipeline.rollup_targets set last_due_at = p_due, last_started_at = v_t0, last_finished_at = clock_timestamp(), last_status = 'succeeded',
           last_error = null, last_ms = v_ms, updated_at = now() where target_code = p_code;
    return 'succeeded';
  exception when others then
    get stacked diagnostics v_err = message_text;
    v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000)::int;
    insert into pipeline.rollup_runs(tick_at, target_code, mode, due_at, due_minutes, started_at, finished_at, ms, status, error)
    values (p_tick, p_code, 'live', p_due, p_due_minutes, v_t0, clock_timestamp(), v_ms, 'failed', left(v_err, 1000));
    -- a failed run counts as run (as a failed cron run does): the next run is at the next scheduled minute
    update pipeline.rollup_targets set last_due_at = p_due, last_started_at = v_t0, last_finished_at = clock_timestamp(), last_status = 'failed',
           last_error = left(v_err, 1000), last_ms = v_ms, updated_at = now() where target_code = p_code;
    return 'failed';
  end;
end $function$;
revoke all on function security.rollup_run_target_v1(text, timestamptz, timestamptz, int) from public, anon, authenticated;

-- 5. The tick (a procedure, so each dispatch commits on its own; not security definer, as a procedure that commits cannot be)
create or replace procedure security.rollup_tick_v1()
 language plpgsql
as $function$
declare v_t0 timestamptz := clock_timestamp(); v_tick timestamptz := date_trunc('minute', now()); v_budget int; v_finish int; v_keep int; v_back int;
        v_r record; v_el numeric; v_n int := 0;
begin
  if security.pipeline_num_v1('rollup.scheduler_on', 0) < 1 then return; end if;
  if not pg_try_advisory_lock(hashtext('cf247:rollup_tick')) then return; end if;  -- fixed: the one tick lock (a tick still running keeps the next one out)
  v_budget := security.pipeline_num_v1('rollup.tick_budget_seconds', 60)::int;
  v_finish := security.pipeline_num_v1('rollup.tick_finish_by_seconds', 100)::int;
  v_keep := security.pipeline_num_v1('rollup.keep_days', 14)::int;
  v_back := security.pipeline_num_v1('rollup.catch_up_minutes', 180)::int;
  for v_r in
    select t.target_code, t.mode, d.due_at, d.n,
           case when t.mode = 'shadow' then 0 else coalesce(e.max_ms, t.expected_ms, 0) end exp_ms
      from pipeline.rollup_targets t
      cross join lateral (
        select max(m) due_at, count(*) n
          from generate_series(greatest(coalesce(t.last_due_at + interval '1 minute', v_tick), v_tick - make_interval(mins => v_back)), v_tick, interval '1 minute') m
         where security.cron_matches_v1(t.schedule, m)) d
      left join lateral (
        select max(x.ms) max_ms from pipeline.rollup_runs x
         where x.target_code = t.target_code and x.status = 'succeeded' and x.started_at > now() - make_interval(days => v_keep)) e on true
     where t.enabled and d.due_at is not null
     order by t.priority, d.due_at, t.target_code
  loop
    v_el := extract(epoch from clock_timestamp() - v_t0);
    if v_n > 0 and (v_el > v_budget or v_el + v_r.exp_ms / 1000.0 > v_finish) then
      if v_r.mode = 'live' then
        insert into pipeline.rollup_runs(tick_at, target_code, mode, due_at, due_minutes, status)
        values (v_tick, v_r.target_code, 'live', v_r.due_at, v_r.n::int, 'deferred');
        commit;
      end if;
      continue;  -- stays due for the next tick
    end if;
    perform security.rollup_run_target_v1(v_r.target_code, v_tick, v_r.due_at, v_r.n::int);
    v_n := v_n + 1;
    commit;
  end loop;
  delete from pipeline.rollup_runs where tick_at < now() - make_interval(days => v_keep);
  commit;
  perform pg_advisory_unlock(hashtext('cf247:rollup_tick'));  -- fixed: the one tick lock
end $function$;
revoke all on procedure security.rollup_tick_v1() from public, anon, authenticated;

-- 6. The shadow report (acceptance for the cutover)
create or replace function security.rollup_shadow_report_v1(p_days int default 7)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
declare v_from timestamptz; v_rows jsonb;
begin
  select greatest(now() - make_interval(days => p_days), min(created_at)) into v_from from pipeline.rollup_targets where rollup_group = 'A';
  select coalesce(jsonb_agg(x order by x->>'target'), '[]'::jsonb) into v_rows from (
    select jsonb_build_object(
      'target', t.target_code, 'legacy_job', t.legacy_job, 'schedule', t.schedule, 'mode', t.mode,
      -- dispatches, not minutes: after a pause (maintenance) the scheduler catches the missed minutes up once, the legacy job not at all
      'scheduler_dispatches', coalesce(s.dispatches, 0),
      'scheduler_due_minutes', coalesce(s.due, 0),
      'legacy_starts', coalesce(l.starts, 0),
      'difference', coalesce(s.dispatches, 0) - coalesce(l.starts, 0),
      'max_lag_seconds', round(coalesce(s.lag, 0)::numeric, 1),
      'collapsed_dispatches', coalesce(s.collapsed, 0),
      'matches', abs(coalesce(s.dispatches, 0) - coalesce(l.starts, 0)) <= greatest(1, ceil(extract(epoch from now() - v_from) / 86400))) x
      from pipeline.rollup_targets t
      left join lateral (select count(*) dispatches, sum(r.due_minutes) due, max(extract(epoch from r.started_at - r.due_at)) lag, count(*) filter (where r.due_minutes > 1) collapsed
                           from pipeline.rollup_runs r where r.target_code = t.target_code and r.due_at >= v_from and r.status in ('shadow_due', 'succeeded', 'failed')) s on true
      left join lateral (select count(*) starts from cron.job j join cron.job_run_details d on d.jobid = j.jobid
                          where j.jobname = t.legacy_job and d.start_time >= v_from) l on true
     where t.rollup_group = 'A') z(x);
  return jsonb_build_object('from', v_from, 'to', now(), 'targets', jsonb_array_length(v_rows),
    'all_match', not exists (select 1 from jsonb_array_elements(v_rows) e where not (e->>'matches')::boolean), 'rows', v_rows);
end $function$;
revoke all on function security.rollup_shadow_report_v1(int) from public, anon, authenticated;

-- 7. Group A targets, copied from the live legacy jobs (command and schedule byte for byte)
insert into pipeline.rollup_targets(target_code, legacy_job, call_sql, call_md5, schedule, rollup_group, priority, mode, expected_ms, note)
select j.jobname, j.jobname, j.command, md5(j.command), j.schedule, 'A',
       -- frequent (4 or more starts an hour, e.g. every 15 minutes or more often) first
       case when (select count(*) from generate_series(0, 59) m where security.cron_matches_v1(j.schedule, date_trunc('day', now()) + make_interval(mins => m))) >= 4 then 10 else 50 end,
       'shadow',
       (select round(percentile_cont(0.95) within group (order by (extract(epoch from d.end_time - d.start_time) * 1000)::float8))::int
          from cron.job_run_details d where d.jobid = j.jobid and d.status = 'succeeded' and d.start_time > now() - make_interval(days => 7)),
       'registered in shadow by 20261115210000; the legacy job still runs'
  from cron.job j
 where j.active and j.jobname in ('admin-read-snapshots', 'data-delivery', 'lane-funnel', 'aer-outcome-register', 'course-coverage-snapshot', 'firecrawl-panel-figures',
   'admin-summary-snapshots-refresh', 'stats-15m', 'course-completeness-build', 'course-coverage-build', 'course-field-source-build',
   'coursefinder-cf245-enrichment-coverage-snapshot', 'coursefinder-cf245-enrichment-hourly-admin-cache', 'enrich-coverage-snapshot', 'progress-snapshot',
   'provider-fee-ranges-refresh', 'adapter-build-readiness', 'evidence-filter-options-refresh', 'layer2-onboarding-snapshot',
   'coursefinder-data-quality-overview-refresh', 'ops-scorecard', 'provider-field-daily', 'toolset-use-daily', 'storage-size-daily', 'api-usage-rollup',
   'provider-priority-refresh')
on conflict (target_code) do nothing;

-- 8. The job: catalogued (G1), registered, then scheduled
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('rollup-scheduler', 'Reports', 5, 'Rollup scheduler (shadow week)',
  'Every minute: works out which report and cache refreshes in pipeline.rollup_targets are due on their own schedules and dispatches them one after another, frequent ones first, within Settings > Pipeline settings > Rollup scheduler. In shadow (now) it only records what was due; the legacy jobs still run the refreshes until the cutover.',
  6, false, null)
on conflict (jobname) do nothing;

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('job', 'rollup-scheduler', 'Platform', 'Reports', 'CF-247 consolidation PR 1: one scheduler for the report and cache refreshes (shadow week; legacy jobs still run them)', 'active', '{}', '20261115210000'),
 ('table', 'pipeline.rollup_targets', 'Platform', 'Reports', 'The report and cache refreshes the rollup scheduler runs', 'active', '{}', '20261115210000'),
 ('table', 'pipeline.rollup_runs', 'Platform', 'Reports', 'One row per rollup scheduler dispatch', 'active', '{}', '20261115210000'),
 ('function', 'security.rollup_tick_v1', 'Platform', 'Reports', 'One tick of the job rollup-scheduler (procedure)', 'active', '{}', '20261115210000'),
 ('function', 'security.rollup_run_target_v1', 'Platform', 'Reports', 'One rollup dispatch (shadow records, live runs)', 'active', '{}', '20261115210000'),
 ('function', 'security.rollup_shadow_report_v1', 'Platform', 'Reports', 'Shadow week acceptance report for the rollup scheduler', 'active', '{}', '20261115210000'),
 ('function', 'security.cron_matches_v1', 'Platform', 'Reports', 'Whether a cron schedule starts at a minute (UTC)', 'active', '{}', '20261115210000'),
 ('function', 'security.cron_field_matches_v1', 'Platform', 'Reports', 'One cron field against one value', 'active', '{}', '20261115210000')
on conflict do nothing;

do $c$ begin
  if to_regnamespace('cron') is not null and not exists (select 1 from cron.job where jobname = 'rollup-scheduler') then
    perform cron.schedule('rollup-scheduler', '* * * * *', $j$call security.rollup_tick_v1()$j$);
  end if;
end $c$;

-- 9. Post-checks
do $$
declare v_n int;
begin
  -- the matcher against the schedules in use
  if not security.cron_matches_v1('1-59/15 * * * *', '2026-11-15 10:16:00+00') or security.cron_matches_v1('1-59/15 * * * *', '2026-11-15 10:15:00+00')
     or not security.cron_matches_v1('53 */2 * * *', '2026-11-15 10:53:00+00') or security.cron_matches_v1('53 */2 * * *', '2026-11-15 11:53:00+00')
     or not security.cron_matches_v1('17 16 * * *', '2026-11-15 16:17:00+00') or security.cron_matches_v1('17 16 * * *', '2026-11-15 16:18:00+00')
     or not security.cron_matches_v1('* * * * *', '2026-11-15 10:07:00+00') or not security.cron_matches_v1('2-59/5 * * * *', '2026-11-15 10:57:00+00')
     or security.cron_matches_v1('30 seconds', '2026-11-15 10:07:00+00') then
    raise exception 'post-check: the cron matcher';
  end if;
  if to_regnamespace('cron') is not null then
    select count(*) into v_n from pipeline.rollup_targets t join cron.job j on j.jobname = t.legacy_job
     where t.rollup_group = 'A' and t.mode = 'shadow' and t.call_sql = j.command and t.call_md5 = md5(j.command) and t.schedule = j.schedule and j.active;
    if v_n <> 26 then raise exception 'post-check: % of 26 Group A targets match their live legacy job', v_n; end if;
    if not exists (select 1 from cron.job where jobname = 'rollup-scheduler' and schedule = '* * * * *' and command = 'call security.rollup_tick_v1()' and active) then
      raise exception 'post-check: the rollup-scheduler job';
    end if;
  end if;
  if exists (select 1 from pipeline.rollup_targets where mode <> 'shadow') then raise exception 'post-check: a target is live (this change is shadow only)'; end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key like 'rollup.%') <> 5 then raise exception 'post-check: settings'; end if;
end $$;