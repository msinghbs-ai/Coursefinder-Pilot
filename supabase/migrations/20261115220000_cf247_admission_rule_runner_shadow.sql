-- CF-247 consolidation PR 2: pipeline.admission_rules and the admission-rule-runner, in shadow (Platform Admin 15 Nov 2026 20:38, approving the
-- job governance blueprint; 22:36: deterministic cron dispatchers take a 24-hour shadow cycle, then the legacy jobs are switched off;
-- cron.unschedule paste files keep the 14-day retention window).
--   1. pipeline.admission_rules: one row per field-specific admission rule job (20 jobs), holding the legacy job's command byte for byte
--      (call_sql, with its md5) and its cron schedule, a per-rule time budget (budget_ms, from the legacy job's longest run in 7 days) and a
--      circuit breaker (consecutive_failures, open_until, last_result). pipeline.admission_rule_runs: one row per dispatch (telemetry).
--   2. security.admission_rule_run_v1(code, lane, tick, due, minutes): one dispatch. It claims the rule (skip locked) and checks again that
--      it is still due, so lanes never run a rule twice. In shadow it records that the rule was due and runs nothing. Live it runs call_sql in
--      its own exception block, keeps the rule's answer (last_result), marks a run longer than budget_ms as over budget, and after
--      admission_runner.breaker_after_failures failures in a row opens the breaker: the rule is skipped (recorded) until open_until, which
--      doubles from admission_runner.breaker_backoff_minutes up to admission_runner.breaker_backoff_max_minutes, and a Platform health issue
--      is raised (admission_rule_breaker:<rule>); the next good run closes the breaker and resolves the issue.
--   3. security.admission_rule_tick_v1(lane) (a procedure; three lane jobs admission-rule-runner, -b and -c, every minute): each lane takes
--      the due rules in order (missed minutes caught up once within admission_runner.catch_up_minutes), skips a rule another lane holds, starts
--      none after admission_runner.tick_budget_seconds, starts a live rule only if its longest recent run (or its budget) still finishes within
--      admission_runner.tick_finish_by_seconds (the first rule of a lane's tick always starts), and commits each dispatch on its own. Three
--      lanes because several rules take up to two minutes and share start minutes (:03, :05 and :09 of each ten).
--   4. security.admission_rule_shadow_report_v1(hours): per rule, the scheduler's dispatches against the legacy job's starts, the largest
--      lag, and the projected load: for each minute, the summed budgets of the rules due, against the lanes' capacity.
-- Shadow only: every rule is registered in mode 'shadow'. The 20 legacy jobs keep running exactly as they are; nothing they do changes.
-- Not registered: aer-machine-admission (kept separate, Platform Admin 15 Nov 2026), layer4-drain (its own stage; the telemetry drain log reads
-- its runs), calendar-reread (a worker lane, consolidation PR 3) and the retiring jobs.
-- G1: the three lane jobs are catalogued before they are scheduled and registered. G2: eight settings (inserted; no existing setting changes);
-- the job commands have no number. G3: no consumer API object is read or changed.
-- Replaces: nothing (shadow: no legacy job changes).
-- Retires: nothing (the cutover change switches the legacy jobs off and retires them).

set local lock_timeout = '5s';

-- 1. Settings (G2)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'admission_runner.on', 'Admission rule runner: on',
  'The admission rule runner checks every minute which admission rules are due on their own schedules. In shadow it only records what was due; the legacy jobs still run the rules. 0 stops the runner.',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 1830, 'Consolidation PR 2 (Platform Admin 15 Nov 2026 22:36): 24-hour shadow cycle', 'Admission rule runner', 'security.admission_rule_tick_v1 (jobs admission-rule-runner, -b, -c)'),
 ('pipeline', 'admission_runner.tick_budget_seconds', 'Admission rule runner: start no rule after',
  'Seconds into a lane''s tick after which it starts no further rule; the rest stay due for the next tick or another lane.',
  'number', to_jsonb(60), 10, 100, 'seconds', 1831, 'Consolidation PR 2 (Platform Admin 15 Nov 2026 22:36)', 'Admission rule runner', 'security.admission_rule_tick_v1 (jobs admission-rule-runner, -b, -c)'),
 ('pipeline', 'admission_runner.tick_finish_by_seconds', 'Admission rule runner: a live rule starts only if it can finish within',
  'A live rule starts only if the lane''s tick so far plus the rule''s longest recent run (or its budget) fits within this many seconds (the database stops any statement at 120 s). The first rule of a lane''s tick always starts.',
  'number', to_jsonb(100), 30, 110, 'seconds', 1832, 'Consolidation PR 2 (Platform Admin 15 Nov 2026 22:36)', 'Admission rule runner', 'security.admission_rule_tick_v1 (jobs admission-rule-runner, -b, -c)'),
 ('pipeline', 'admission_runner.keep_days', 'Admission rule runner: keep run history for',
  'Days of pipeline.admission_rule_runs kept; older rows are removed by the runner. Also the window for each rule''s longest recent run.',
  'number', to_jsonb(14), 3, 60, 'days', 1833, 'Consolidation PR 2 (Platform Admin 15 Nov 2026 22:36)', 'Admission rule runner', 'security.admission_rule_tick_v1 (jobs admission-rule-runner, -b, -c)'),
 ('pipeline', 'admission_runner.catch_up_minutes', 'Admission rule runner: look back for missed minutes at most',
  'When the runner has not run for a while (a pause, maintenance), a rule due in the missed minutes runs once; minutes further back than this are not looked at.',
  'number', to_jsonb(180), 5, 1440, 'minutes', 1834, 'Consolidation PR 2 (Platform Admin 15 Nov 2026 22:36)', 'Admission rule runner', 'security.admission_rule_tick_v1 (jobs admission-rule-runner, -b, -c)'),
 ('pipeline', 'admission_runner.breaker_after_failures', 'Admission rule runner: open a rule''s breaker after failures in a row',
  'A live rule that fails this many times in a row is skipped for a back-off period and a Platform health issue is raised; its next good run closes the breaker.',
  'number', to_jsonb(3), 1, 20, 'failures', 1835, 'Consolidation PR 2 (Platform Admin 15 Nov 2026 22:36)', 'Admission rule runner', 'security.admission_rule_run_v1'),
 ('pipeline', 'admission_runner.breaker_backoff_minutes', 'Admission rule runner: first back-off when a breaker opens',
  'How long a rule is skipped when its breaker first opens; each further failure doubles it, up to the longest back-off.',
  'number', to_jsonb(15), 1, 240, 'minutes', 1836, 'Consolidation PR 2 (Platform Admin 15 Nov 2026 22:36)', 'Admission rule runner', 'security.admission_rule_run_v1'),
 ('pipeline', 'admission_runner.breaker_backoff_max_minutes', 'Admission rule runner: longest back-off',
  'The longest a rule is skipped after repeated failures before it is tried again.',
  'number', to_jsonb(240), 15, 1440, 'minutes', 1837, 'Consolidation PR 2 (Platform Admin 15 Nov 2026 22:36)', 'Admission rule runner', 'security.admission_rule_run_v1')
on conflict do nothing;

-- 2. Tables
create table if not exists pipeline.admission_rules (
  rule_code text primary key,
  legacy_job text unique,
  call_sql text not null,
  call_md5 text not null,
  schedule text not null,
  priority int not null default 50,
  enabled boolean not null default true,
  mode text not null default 'shadow' check (mode in ('shadow', 'live')),
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
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table pipeline.admission_rules is 'CF-247 consolidation PR 2 (15 Nov 2026): one row per field-specific admission rule run by the admission-rule-runner lanes. call_sql is the legacy job''s command byte for byte (call_md5 guards it), schedule its cron schedule, budget_ms its time budget; consecutive_failures and open_until are its circuit breaker; mode shadow records what was due and runs nothing, live runs it. A new admission rule is a row here, not a new pg_cron job.';
alter table pipeline.admission_rules enable row level security;
revoke all on pipeline.admission_rules from anon, authenticated;

create table if not exists pipeline.admission_rule_runs (
  id bigint generated always as identity primary key,
  tick_at timestamptz not null,
  lane text not null,
  rule_code text not null references pipeline.admission_rules(rule_code),
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
comment on table pipeline.admission_rule_runs is 'CF-247 consolidation PR 2 (15 Nov 2026): telemetry, one row per admission-rule-runner dispatch (shadow_due, succeeded, failed, deferred to a later tick, refused because call_sql changed, or skipped while the rule''s breaker is open), with the lane, the time taken, whether it ran over the rule''s budget and the rule''s answer. Kept for admission_runner.keep_days.';
create index if not exists admission_rule_runs_rule_due_idx on pipeline.admission_rule_runs(rule_code, due_at desc);
create index if not exists admission_rule_runs_tick_idx on pipeline.admission_rule_runs(tick_at);
alter table pipeline.admission_rule_runs enable row level security;
revoke all on pipeline.admission_rule_runs from anon, authenticated;

-- 3. One dispatch
create or replace function security.admission_rule_run_v1(p_code text, p_lane text, p_tick timestamptz, p_due timestamptz, p_due_minutes int)
 returns text
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_r pipeline.admission_rules; v_t0 timestamptz := clock_timestamp(); v_ms int; v_err text; v_out text; v_sql text; v_after int; v_back int; v_max int; v_until timestamptz;
begin
  select * into v_r from pipeline.admission_rules where rule_code = p_code for update skip locked;
  if not found then return 'locked'; end if;  -- another lane holds it
  if v_r.last_due_at is not null and v_r.last_due_at >= p_due then return 'already'; end if;  -- another lane ran it since this lane looked
  if md5(v_r.call_sql) <> v_r.call_md5 then
    insert into pipeline.admission_rule_runs(tick_at, lane, rule_code, mode, due_at, due_minutes, started_at, finished_at, status, error)
    values (p_tick, p_lane, p_code, v_r.mode, p_due, p_due_minutes, v_t0, clock_timestamp(), 'refused', 'call_sql changed since registration (md5)');
    update pipeline.admission_rules set last_status = 'refused', last_error = 'call_sql changed since registration (md5)', updated_at = now() where rule_code = p_code;
    return 'refused';
  end if;
  if v_r.mode = 'shadow' then
    insert into pipeline.admission_rule_runs(tick_at, lane, rule_code, mode, due_at, due_minutes, started_at, finished_at, ms, status)
    values (p_tick, p_lane, p_code, 'shadow', p_due, p_due_minutes, v_t0, clock_timestamp(), 0, 'shadow_due');
    update pipeline.admission_rules set last_due_at = p_due, last_status = 'shadow_due', updated_at = now() where rule_code = p_code;
    return 'shadow_due';
  end if;
  if v_r.open_until is not null and v_r.open_until > now() then
    insert into pipeline.admission_rule_runs(tick_at, lane, rule_code, mode, due_at, due_minutes, started_at, finished_at, ms, status, error)
    values (p_tick, p_lane, p_code, 'live', p_due, p_due_minutes, v_t0, clock_timestamp(), 0, 'skipped_open', 'breaker open until ' || v_r.open_until);
    update pipeline.admission_rules set last_due_at = p_due, last_status = 'skipped_open', updated_at = now() where rule_code = p_code;
    return 'skipped_open';
  end if;
  -- a single statement keeps its answer as telemetry; a command of several statements runs as one
  v_sql := rtrim(v_r.call_sql, E'; \n\t');
  begin
    if position(';' in v_sql) = 0 then execute v_sql into v_out; else execute v_r.call_sql; end if;
    v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000)::int;
    insert into pipeline.admission_rule_runs(tick_at, lane, rule_code, mode, due_at, due_minutes, started_at, finished_at, ms, status, over_budget, result)
    values (p_tick, p_lane, p_code, 'live', p_due, p_due_minutes, v_t0, clock_timestamp(), v_ms, 'succeeded', v_ms > coalesce(v_r.budget_ms, v_ms), left(v_out, 2000));
    update pipeline.admission_rules set last_due_at = p_due, last_started_at = v_t0, last_finished_at = clock_timestamp(), last_status = 'succeeded',
           last_result = left(v_out, 2000), last_error = null, last_ms = v_ms, consecutive_failures = 0, open_until = null, updated_at = now()
     where rule_code = p_code;
    if v_r.consecutive_failures > 0 then
      update pipeline.platform_issues set resolved_at = now(), last_seen = now()
       where check_key = 'admission_rule_breaker:' || p_code and resolved_at is null;
    end if;
    return 'succeeded';
  exception when others then
    get stacked diagnostics v_err = message_text;
    v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000)::int;
    v_after := security.pipeline_num_v1('admission_runner.breaker_after_failures', 3)::int;
    v_back := security.pipeline_num_v1('admission_runner.breaker_backoff_minutes', 15)::int;
    v_max := security.pipeline_num_v1('admission_runner.breaker_backoff_max_minutes', 240)::int;
    if v_r.consecutive_failures + 1 >= v_after then
      v_until := now() + make_interval(mins => least(v_max, v_back * power(2, greatest(0, v_r.consecutive_failures + 1 - v_after)))::int);
    end if;
    insert into pipeline.admission_rule_runs(tick_at, lane, rule_code, mode, due_at, due_minutes, started_at, finished_at, ms, status, over_budget, error)
    values (p_tick, p_lane, p_code, 'live', p_due, p_due_minutes, v_t0, clock_timestamp(), v_ms, 'failed', v_ms > coalesce(v_r.budget_ms, v_ms), left(v_err, 1000));
    -- a failed run counts as run (as a failed cron run does): the next run is at the next scheduled minute, or after the back-off
    update pipeline.admission_rules set last_due_at = p_due, last_started_at = v_t0, last_finished_at = clock_timestamp(), last_status = 'failed',
           last_error = left(v_err, 1000), last_ms = v_ms, consecutive_failures = consecutive_failures + 1, open_until = coalesce(v_until, open_until), updated_at = now()
     where rule_code = p_code;
    if v_until is not null then
      if exists (select 1 from pipeline.platform_issues where check_key = 'admission_rule_breaker:' || p_code and resolved_at is null) then
        update pipeline.platform_issues set last_seen = now(), occurrences = occurrences + 1,
               detail = jsonb_build_object('rule', p_code, 'failures_in_a_row', v_r.consecutive_failures + 1, 'skipped_until', v_until, 'last_error', left(v_err, 300))
         where check_key = 'admission_rule_breaker:' || p_code and resolved_at is null;
      else
        insert into pipeline.platform_issues(check_key, severity, area, title, detail)
        values ('admission_rule_breaker:' || p_code, 'warning', 'admission',  -- an area platform_issues allows (platform_issues_area_check)
                'Admission rule ' || p_code || ' failed ' || (v_r.consecutive_failures + 1) || ' times in a row: skipped until ' || to_char(v_until at time zone 'UTC', 'HH24:MI') || ' UTC',
                jsonb_build_object('rule', p_code, 'failures_in_a_row', v_r.consecutive_failures + 1, 'skipped_until', v_until, 'last_error', left(v_err, 300)));
      end if;
    end if;
    return 'failed';
  end;
end $function$;
revoke all on function security.admission_rule_run_v1(text, text, timestamptz, timestamptz, int) from public, anon, authenticated;

-- 4. One lane's tick (a procedure, so each dispatch commits on its own; not security definer, as a procedure that commits cannot be)
create or replace procedure security.admission_rule_tick_v1(p_lane text)
 language plpgsql
as $function$
declare v_t0 timestamptz := clock_timestamp(); v_tick timestamptz := date_trunc('minute', now()); v_budget int; v_finish int; v_keep int; v_back int;
        v_r record; v_el numeric; v_n int := 0; v_res text;
begin
  if security.pipeline_num_v1('admission_runner.on', 0) < 1 then return; end if;
  if not pg_try_advisory_lock(hashtext('cf247:admission_tick:' || p_lane)) then return; end if;  -- fixed: one tick per lane at a time
  v_budget := security.pipeline_num_v1('admission_runner.tick_budget_seconds', 60)::int;
  v_finish := security.pipeline_num_v1('admission_runner.tick_finish_by_seconds', 100)::int;
  v_keep := security.pipeline_num_v1('admission_runner.keep_days', 14)::int;
  v_back := security.pipeline_num_v1('admission_runner.catch_up_minutes', 180)::int;
  for v_r in
    select r.rule_code, r.mode, d.due_at, d.n,
           case when r.mode = 'shadow' then 0 else coalesce(e.max_ms, r.budget_ms, r.expected_ms, 0) end exp_ms
      from pipeline.admission_rules r
      cross join lateral (
        select max(m) due_at, count(*) n
          from generate_series(greatest(coalesce(r.last_due_at + interval '1 minute', v_tick), v_tick - make_interval(mins => v_back)), v_tick, interval '1 minute') m
         where security.cron_matches_v1(r.schedule, m)) d
      left join lateral (
        select max(x.ms) max_ms from pipeline.admission_rule_runs x
         where x.rule_code = r.rule_code and x.status = 'succeeded' and x.started_at > now() - make_interval(days => v_keep)) e on true
     where r.enabled and d.due_at is not null
     order by d.due_at, r.priority, r.rule_code
  loop
    v_el := extract(epoch from clock_timestamp() - v_t0);
    if v_n > 0 and (v_el > v_budget or v_el + v_r.exp_ms / 1000.0 > v_finish) then
      continue;  -- stays due for another lane or the next tick
    end if;
    v_res := security.admission_rule_run_v1(v_r.rule_code, p_lane, v_tick, v_r.due_at, v_r.n::int);
    if v_res not in ('locked', 'already') then v_n := v_n + 1; end if;
    commit;
  end loop;
  delete from pipeline.admission_rule_runs where tick_at < now() - make_interval(days => v_keep);
  commit;
  perform pg_advisory_unlock(hashtext('cf247:admission_tick:' || p_lane));  -- fixed: one tick per lane at a time
end $function$;
revoke all on procedure security.admission_rule_tick_v1(text) from public, anon, authenticated;

-- 5. The shadow report (acceptance for the cutover, 24-hour cycle)
create or replace function security.admission_rule_shadow_report_v1(p_hours int default 24)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
declare v_from timestamptz; v_rows jsonb; v_lanes int; v_finish int; v_load jsonb;
begin
  select greatest(now() - make_interval(hours => p_hours), min(created_at)) into v_from from pipeline.admission_rules;
  select count(*) into v_lanes from cron.job where jobname like 'admission-rule-runner%' and active;
  v_finish := security.pipeline_num_v1('admission_runner.tick_finish_by_seconds', 100)::int;
  select coalesce(jsonb_agg(x order by x->>'rule'), '[]'::jsonb) into v_rows from (
    select jsonb_build_object(
      'rule', r.rule_code, 'schedule', r.schedule, 'mode', r.mode, 'budget_ms', r.budget_ms,
      -- dispatches, not minutes: after a pause the runner catches the missed minutes up once, the legacy job not at all
      'runner_dispatches', coalesce(s.dispatches, 0),
      'legacy_starts', coalesce(l.starts, 0),
      'difference', coalesce(s.dispatches, 0) - coalesce(l.starts, 0),
      'max_lag_seconds', round(coalesce(s.lag, 0)::numeric, 1),
      'collapsed_dispatches', coalesce(s.collapsed, 0),
      'lanes_used', coalesce(s.lanes, 0),
      'legacy_failed', coalesce(l.failed, 0),
      'matches', abs(coalesce(s.dispatches, 0) - coalesce(l.starts, 0)) <= 1) x
      from pipeline.admission_rules r
      left join lateral (select count(*) dispatches, max(extract(epoch from x.started_at - x.due_at)) lag, count(*) filter (where x.due_minutes > 1) collapsed,
                                count(distinct x.lane) lanes
                           from pipeline.admission_rule_runs x where x.rule_code = r.rule_code and x.due_at >= v_from
                            and x.status in ('shadow_due', 'succeeded', 'failed', 'skipped_open')) s on true
      left join lateral (select count(*) starts, count(*) filter (where d.status = 'failed') failed from cron.job j join cron.job_run_details d on d.jobid = j.jobid
                          where j.jobname = r.legacy_job and d.start_time >= v_from) l on true) z(x);
  -- projected load: for each minute, the summed budgets of the rules due then, against the lanes' capacity
  select jsonb_build_object('lanes', v_lanes, 'capacity_seconds_per_minute', v_lanes * v_finish,
           'max_projected_seconds_in_a_minute', coalesce(round(max(t.s)::numeric, 1), 0),
           'minutes_over_capacity', count(*) filter (where t.s > v_lanes * v_finish))
    into v_load
    from (select x.due_at, sum(coalesce(r.budget_ms, 0)) / 1000.0 s from pipeline.admission_rule_runs x join pipeline.admission_rules r on r.rule_code = x.rule_code
           where x.due_at >= v_from and x.status in ('shadow_due', 'succeeded', 'failed') group by x.due_at) t;
  return jsonb_build_object('from', v_from, 'to', now(), 'rules', jsonb_array_length(v_rows),
    'all_match', not exists (select 1 from jsonb_array_elements(v_rows) e where not (e->>'matches')::boolean), 'load', v_load, 'rows', v_rows);
end $function$;
revoke all on function security.admission_rule_shadow_report_v1(int) from public, anon, authenticated;

-- 6. The 20 rules, copied from the live legacy jobs (command and schedule byte for byte); budget = the legacy job's longest run in 7 days
insert into pipeline.admission_rules(rule_code, legacy_job, call_sql, call_md5, schedule, priority, mode, budget_ms, expected_ms, note)
select j.jobname, j.jobname, j.command, md5(j.command), j.schedule, 50, 'shadow',
       (select round(max(extract(epoch from d.end_time - d.start_time)) * 1000)::int
          from cron.job_run_details d where d.jobid = j.jobid and d.status = 'succeeded' and d.start_time > now() - make_interval(days => 7)),
       (select round(percentile_cont(0.95) within group (order by (extract(epoch from d.end_time - d.start_time) * 1000)::float8))::int
          from cron.job_run_details d where d.jobid = j.jobid and d.status = 'succeeded' and d.start_time > now() - make_interval(days => 7)),
       'registered in shadow by 20261115220000; the legacy job still runs'
  from cron.job j
 where j.active and j.jobname in ('adapter-overwrite', 'coverage-admit', 'coverage-admit-intakes', 'exit-awards-apply', 'fee-period-settle', 'fee-wording-rules',
   'host-pages-apply', 'intake-dates-apply', 'l4-rule-fee-year-align', 'l4-rule-unofficial-source', 'policy-auto-approve', 'process-results',
   'provider-basis-rule-admit', 'provider-english-defaults', 'provider-fee-profiles-apply', 'provider-rule-admit',
   'aer-v2-identity-settle', 'layer4-auto-admit', 'intake-rule-b-qualify', 'scholarship-discovery-settle')
on conflict (rule_code) do nothing;

-- 7. The three lane jobs: catalogued (G1), registered, then scheduled
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('admission-rule-runner', 'Admission', 1, 'Admission rule runner, lane a (24-hour shadow)',
  'Every minute: works out which admission rules in pipeline.admission_rules are due on their own schedules and dispatches them, with a time budget and a circuit breaker per rule, within Settings > Pipeline settings > Admission rule runner. Three lanes (a, b, c) share the rules; a rule runs on one lane only. In shadow (now) it only records what was due; the legacy jobs still run the rules until the cutover.',
  6, false, null),
 ('admission-rule-runner-b', 'Admission', 2, 'Admission rule runner, lane b (24-hour shadow)',
  'Second lane of the admission rule runner: the same rules, so two rules due in the same minute run side by side. In shadow it only records what was due.',
  6, false, null),
 ('admission-rule-runner-c', 'Admission', 3, 'Admission rule runner, lane c (24-hour shadow)',
  'Third lane of the admission rule runner. In shadow it only records what was due.',
  6, false, null)
on conflict (jobname) do nothing;

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('job', 'admission-rule-runner', 'Platform', 'Admission', 'CF-247 consolidation PR 2: admission rule runner, lane a (24-hour shadow; legacy jobs still run the rules)', 'active', '{}', '20261115220000'),
 ('job', 'admission-rule-runner-b', 'Platform', 'Admission', 'CF-247 consolidation PR 2: admission rule runner, lane b', 'active', '{}', '20261115220000'),
 ('job', 'admission-rule-runner-c', 'Platform', 'Admission', 'CF-247 consolidation PR 2: admission rule runner, lane c', 'active', '{}', '20261115220000'),
 ('table', 'pipeline.admission_rules', 'Platform', 'Admission', 'The admission rules the admission rule runner runs, with budgets and breakers', 'active', '{}', '20261115220000'),
 ('table', 'pipeline.admission_rule_runs', 'Platform', 'Admission', 'Telemetry: one row per admission rule runner dispatch', 'active', '{}', '20261115220000'),
 ('function', 'security.admission_rule_tick_v1', 'Platform', 'Admission', 'One lane tick of the admission rule runner (procedure)', 'active', '{}', '20261115220000'),
 ('function', 'security.admission_rule_run_v1', 'Platform', 'Admission', 'One admission rule dispatch (shadow records; live runs with budget and breaker)', 'active', '{}', '20261115220000'),
 ('function', 'security.admission_rule_shadow_report_v1', 'Platform', 'Admission', '24-hour shadow acceptance report for the admission rule runner', 'active', '{}', '20261115220000')
on conflict do nothing;

do $c$ begin
  if to_regnamespace('cron') is null then return; end if;
  if not exists (select 1 from cron.job where jobname = 'admission-rule-runner') then
    perform cron.schedule('admission-rule-runner', '* * * * *', $j$call security.admission_rule_tick_v1('a')$j$);
  end if;
  if not exists (select 1 from cron.job where jobname = 'admission-rule-runner-b') then
    perform cron.schedule('admission-rule-runner-b', '* * * * *', $j$call security.admission_rule_tick_v1('b')$j$);
  end if;
  if not exists (select 1 from cron.job where jobname = 'admission-rule-runner-c') then
    perform cron.schedule('admission-rule-runner-c', '* * * * *', $j$call security.admission_rule_tick_v1('c')$j$);
  end if;
end $c$;

-- 8. Post-checks
do $$
declare v_n int;
begin
  if to_regnamespace('cron') is not null then
    select count(*) into v_n from pipeline.admission_rules r join cron.job j on j.jobname = r.legacy_job
     where r.mode = 'shadow' and r.call_sql = j.command and r.call_md5 = md5(j.command) and r.schedule = j.schedule and j.active;
    if v_n <> 20 then raise exception 'post-check: % of 20 admission rules match their live legacy job', v_n; end if;
    if (select count(*) from cron.job where jobname in ('admission-rule-runner', 'admission-rule-runner-b', 'admission-rule-runner-c') and schedule = '* * * * *' and active
          and command in ($j$call security.admission_rule_tick_v1('a')$j$, $j$call security.admission_rule_tick_v1('b')$j$, $j$call security.admission_rule_tick_v1('c')$j$)) <> 3 then
      raise exception 'post-check: the three admission-rule-runner lane jobs';
    end if;
    if exists (select 1 from pipeline.admission_rules where legacy_job in ('aer-machine-admission', 'layer4-drain', 'calendar-reread')) then
      raise exception 'post-check: a job kept separate was registered';
    end if;
  end if;
  if exists (select 1 from pipeline.admission_rules where mode <> 'shadow') then raise exception 'post-check: a rule is live (this change is shadow only)'; end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key like 'admission_runner.%') <> 8 then raise exception 'post-check: settings'; end if;
end $$;