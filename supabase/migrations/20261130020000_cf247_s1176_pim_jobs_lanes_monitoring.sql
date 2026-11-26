-- CF-247 s1176 (S1-RM-Design; DR-16 takeover, SS-Programme-Control assignment 26 Nov 2026 21:34 AEDT: "Correct the existing pim_operations_v1
-- monitoring contract ... identify cron jobs by jobid, not job name ... include every registered effective worker, dispatcher lane, admission rule
-- and rollup target ... distinguish active, idle, held, degraded, retired and shadow ... actual heartbeat, last run, next run, failure reason and
-- effective processing state ... reuse existing Data Delivery helper snapshots ... preserve the existing pim.operations contract").
--
-- What it adds (read-only; no table, job, worker, queue, planner or schedule change; nothing is retired or switched):
--   security.pim_outcome_class_v1(status, result)  one execution's outcome from the run's own recorded status and result:
--     failed | deferred | productive (an admission, publication or hand-off counter above 0) | held (only protective counters above 0: Layer 4,
--     held, refused, left for a person) | empty (a structured result with every counter at 0) | unmeasured (no structured result).
--   security.data_delivery_jobs_v1()  the jobs read, counted only in the background: security.pim_operations_v1 calls it, and that is counted by
--     security.data_delivery_refresh_v1 into the existing PIM snapshot (pipeline.data_delivery_job_runs.pim, the s1167 and s1174 snapshot path);
--     the screen read (security.data_delivery_v1) only reads the snapshot and never counts it. One row per component:
--       every cron.job row, keyed by jobid (history from cron.job_run_details by jobid, so a reused job name is never mixed);
--       every pipeline.field_execution_registry lane, pipeline.rollup_targets target and pipeline.admission_rules rule, with its runs from
--       pipeline.coverage_lane_runs / rollup_runs / admission_rule_runs.
--     Each row: state (active, idle, held, degraded, retired, shadow) and its reason, the effective processing state of a job moved onto a
--     dispatcher (the register row it moved to), heartbeat (last start), last end and status, last success, last failure reason, next run
--     (security.cron_next_run_v1), purpose and owner from the existing registers, and 24-hour and seven-day executions by outcome class with
--     their duration. A window the retained history does not cover is reported as partial with the time the history starts; an outcome the run
--     does not record is "unmeasured", never 0. Findings (failing, circuit open, stalled, mostly empty, repeated protective outcome, deferred,
--     outcome unmeasured, switched off in the last day) are evidence for the owner; nothing is changed by them.
--     Toolset use: AI attempts, failures and billed cost by service (pipeline.ai_invocations) and Firecrawl calls and credits by use case
--     (pipeline.firecrawl_calls), 24 hours and seven days. They are not attributed to a component: no register links a job to a service.
--   security.pim_operations_v1()  compatible additions only: workers is every active cron job (jobid added; the data-delivery counter is not a
--     worker), with the s1175 fields unchanged and state, heartbeat, next run, failure reason and effective state added; stalled now uses the
--     job's own schedule (pim.jobs_stall_periods periods, never less than plans.auto_stall_hours). New keys: components, states, holds, toolset,
--     jobs_snapshot (its as_at, windows and retained history). consumer, freshness_by_country, expired_leases, requests and meaning are unchanged.
-- G1: no job. G2: five settings (pim.jobs_stall_periods, pim.jobs_min_runs, pim.jobs_empty_share, pim.jobs_failure_share, pim.jobs_deferred_share)
-- and the existing data_delivery.net_short_hours, data_delivery.net_long_hours, plans.auto_stall_hours. G3: no consumer object; 75/48 asserted
-- before and after. Manual locks and cron count asserted unchanged. AI and spend untouched ($0). Nothing dropped.
-- Replaces: security.pim_operations_v1 (s1175).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the function replaces
set local statement_timeout = '120s';  -- fixed: the read-only checks

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'guard: consumer API not at baseline: %', v; end if;
  if md5(pg_get_functiondef('security.pim_operations_v1()'::regprocedure)) <> 'e0a1ab379a7817102eabd424282bfd64' then raise exception 'guard: security.pim_operations_v1 is not the s1175 definition'; end if;
end $g$;
create temp table s1176_before on commit drop as
  select (select count(*) from pipeline.manual_locks) locks, (select count(*) from cron.job where active) jobs, (select count(*) from cron.job) jobs_all;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'pim.jobs_stall_periods', 'PIM monitoring: a job is stalled after missing this many of its own runs',
  'A scheduled job, lane, rule or target is shown as stalled when it has not succeeded for this many of its own schedule periods (never less than plans.auto_stall_hours). A weekly job is not stalled after two hours.',
  'number', '3'::jsonb, 2, 20, 'periods', 1605, 'PIM', 'security.data_delivery_jobs_v1 (s1176)', 'CF-247 s1176 PIM monitoring by jobid'),
 ('pipeline', 'pim.jobs_min_runs', 'PIM monitoring: executions needed before a scheduling finding',
  'A schedule finding (mostly empty, repeated protective outcome, often deferred) is only made from at least this many measured executions in seven days.',
  'number', '20'::jsonb, 5, 1000, 'executions', 1606, 'PIM', 'security.data_delivery_jobs_v1 (s1176)', 'CF-247 s1176 PIM monitoring by jobid'),
 ('pipeline', 'pim.jobs_empty_share', 'PIM monitoring: share of empty runs that flags a slower schedule',
  'When at least this share of a component''s measured seven-day executions found nothing to do, it is flagged as a candidate for a slower schedule. The owner decides; nothing changes automatically.',
  'number', '0.95'::jsonb, 0.5, 1, 'share (0 to 1)', 1607, 'PIM', 'security.data_delivery_jobs_v1 (s1176)', 'CF-247 s1176 PIM monitoring by jobid'),
 ('pipeline', 'pim.jobs_failure_share', 'PIM monitoring: share of failed runs that marks a component degraded',
  'A component whose failed executions in the last 24 hours reach this share, or whose last execution failed, is shown as degraded with its last failure reason.',
  'number', '0.2'::jsonb, 0.01, 1, 'share (0 to 1)', 1608, 'PIM', 'security.data_delivery_jobs_v1 (s1176)', 'CF-247 s1176 PIM monitoring by jobid'),
 ('pipeline', 'pim.jobs_deferred_share', 'PIM monitoring: share of deferred runs that flags dispatcher contention',
  'A dispatcher target deferred (not started for lack of time in its tick) in at least this share of its seven-day executions is flagged as contended.',
  'number', '0.3'::jsonb, 0.05, 1, 'share (0 to 1)', 1609, 'PIM', 'security.data_delivery_jobs_v1 (s1176)', 'CF-247 s1176 PIM monitoring by jobid');

create or replace function security.pim_outcome_class_v1(p_status text, p_result text)
returns text
language sql
immutable
set search_path = ''
as $f$
  select case
    when p_status = 'failed' then 'failed'
    when p_status in ('deferred', 'skipped') then 'deferred'
    when p_status in ('running', 'starting') then 'running'
    when p_result is null or btrim(p_result) !~ '^[\[{]' then 'unmeasured'
    when p_result ~ '"(written|applied|approved|settled|restored|delivery|replaced|admitted|auto_admitted|items_admitted|rows_admitted|course_items_admitted|course_rows_admitted|proof_items_admitted|proof_rows_admitted|confirmed|confirmed_by_wording|confirmed_short_course|stamped|fees_aligned|items_closed|rule_b_rows|decided_by_rule|published|auto_published|promoted|filled|linked|bound|enqueued|queued|inserted|created)": ?[1-9]' then 'productive'
    when p_result ~ '"(layer4|sampled_to_layer4|held|held_refused|held_manual_lock|refused|refused_identity|refused_waiting|not_proved_left_for_review|left_for_a_person|skipped_check_failed|ambiguous|quarantined|blocked)": ?[1-9]' then 'held'
    else 'empty' end
$f$;
comment on function security.pim_outcome_class_v1(text, text) is 'PIM (s1176): the outcome class of one execution from its recorded status and result: failed, deferred, running, productive, held, empty or unmeasured.';
revoke all on function security.pim_outcome_class_v1(text, text) from public, anon, authenticated;
grant execute on function security.pim_outcome_class_v1(text, text) to service_role;

create or replace function security.data_delivery_jobs_v1()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $f$
  with st as (
    select security.pipeline_num_v1('data_delivery.net_short_hours', 24)::int short_h, security.pipeline_num_v1('data_delivery.net_long_hours', 168)::int long_h,
           security.pipeline_num_v1('plans.auto_stall_hours', 2)::numeric stall_h, security.pipeline_num_v1('pim.jobs_stall_periods', 3)::numeric stall_p,
           security.pipeline_num_v1('pim.jobs_min_runs', 20)::int min_runs, security.pipeline_num_v1('pim.jobs_empty_share', 0.95)::numeric empty_share,
           security.pipeline_num_v1('pim.jobs_failure_share', 0.2)::numeric fail_share, security.pipeline_num_v1('pim.jobs_deferred_share', 0.3)::numeric deferred_share),
  -- the three dispatchers' own cron rows (jobid), by runner name
  disp as (
    select c.jobid, c.jobname, c.active,
           case when c.jobname ~ '^rollup-scheduler' then 'rollup-scheduler' when c.jobname ~ '^admission-rule-runner' then 'admission-rule-runner' else 'coverage-lane-dispatch' end runner
      from cron.job c where c.jobname ~ '^(rollup-scheduler|admission-rule-runner|coverage-lane-dispatch)(-[a-z])?$'),
  reg as (
    select 'lane'::text k, r.lane_code code, r.legacy_job, r.schedule, r.enabled, r.mode, r.kind sub, r.consecutive_failures, r.open_until, r.last_status, r.last_error,
           r.last_started_at, r.last_finished_at, r.last_ms, coalesce(r.budget_ms, r.expected_ms) budget_ms, r.field, r.owner, r.uses_ai, r.fill_function, r.note,
           'coverage-lane-dispatch'::text runner
      from pipeline.field_execution_registry r
    union all
    select 'rollup', t.target_code, t.legacy_job, t.schedule, t.enabled, t.mode, t.rollup_group, null::int, null::timestamptz, t.last_status, t.last_error,
           t.last_started_at, t.last_finished_at, t.last_ms, t.expected_ms, null, null, null::boolean, null, t.note, 'rollup-scheduler'
      from pipeline.rollup_targets t
    union all
    select 'rule', a.rule_code, a.legacy_job, a.schedule, a.enabled, a.mode, null, a.consecutive_failures, a.open_until, a.last_status, a.last_error,
           a.last_started_at, a.last_finished_at, a.last_ms, coalesce(a.budget_ms, a.expected_ms), null, null, null, null, a.note, 'admission-rule-runner'
      from pipeline.admission_rules a),
  -- one grouped scan of the scheduler history, by jobid
  ch as (
    select d.jobid, min(d.start_time) first_start, max(d.start_time) last_start,
           (array_agg(d.end_time order by d.start_time desc))[1] last_end, (array_agg(d.status order by d.start_time desc))[1] last_status,
           max(d.start_time) filter (where d.status = 'succeeded') last_success,
           (array_agg(left(d.return_message, 240) order by d.start_time desc) filter (where d.status = 'failed'))[1] last_failure,
           max(d.start_time) filter (where d.status = 'failed') last_failed_at,
           count(*) filter (where d.start_time > now() - make_interval(hours => st.short_h)) n_s,
           count(*) filter (where d.start_time > now() - make_interval(hours => st.short_h) and o.cls = 'productive') prod_s,
           count(*) filter (where d.start_time > now() - make_interval(hours => st.short_h) and o.cls = 'held') held_s,
           count(*) filter (where d.start_time > now() - make_interval(hours => st.short_h) and o.cls = 'empty') empty_s,
           count(*) filter (where d.start_time > now() - make_interval(hours => st.short_h) and o.cls = 'failed') fail_s,
           count(*) filter (where d.start_time > now() - make_interval(hours => st.short_h) and o.cls = 'unmeasured') unm_s,
           count(*) n_l, count(*) filter (where o.cls = 'productive') prod_l, count(*) filter (where o.cls = 'held') held_l,
           count(*) filter (where o.cls = 'empty') empty_l, count(*) filter (where o.cls = 'failed') fail_l, count(*) filter (where o.cls = 'unmeasured') unm_l,
           round(avg(extract(epoch from d.end_time - d.start_time)) filter (where d.start_time > now() - make_interval(hours => st.short_h)), 2) avg_s,
           round(max(extract(epoch from d.end_time - d.start_time)) filter (where d.start_time > now() - make_interval(hours => st.short_h)), 2) max_s,
           round(avg(extract(epoch from d.end_time - d.start_time)), 2) avg_l
      from cron.job_run_details d cross join st
      cross join lateral (select security.pim_outcome_class_v1(d.status, d.return_message) cls) o
     where d.start_time > now() - make_interval(hours => st.long_h)
     group by d.jobid),
  hist as (select min(d.start_time) since from cron.job_run_details d),
  -- the three dispatchers' run logs, by register code
  rr as (
    select 'lane'::text k, c.lane_code code, c.status, c.result, c.error, c.due_at at, c.ms from pipeline.coverage_lane_runs c cross join st where c.due_at > now() - make_interval(hours => st.long_h)
    union all
    select 'rollup', u.target_code, u.status, null, u.error, u.due_at, u.ms from pipeline.rollup_runs u cross join st where u.due_at > now() - make_interval(hours => st.long_h)
    union all
    select 'rule', a.rule_code, a.status, a.result, a.error, a.due_at, a.ms from pipeline.admission_rule_runs a cross join st where a.due_at > now() - make_interval(hours => st.long_h)),
  rh as (
    select r.k, r.code, min(r.at) first_at, max(r.at) last_at, max(r.at) filter (where r.status = 'succeeded') last_success,
           (array_agg(left(r.error, 240) order by r.at desc) filter (where r.status = 'failed'))[1] last_failure,
           count(*) filter (where r.at > now() - make_interval(hours => st.short_h)) n_s,
           count(*) filter (where r.at > now() - make_interval(hours => st.short_h) and o.cls = 'productive') prod_s,
           count(*) filter (where r.at > now() - make_interval(hours => st.short_h) and o.cls = 'held') held_s,
           count(*) filter (where r.at > now() - make_interval(hours => st.short_h) and o.cls = 'empty') empty_s,
           count(*) filter (where r.at > now() - make_interval(hours => st.short_h) and o.cls = 'failed') fail_s,
           count(*) filter (where r.at > now() - make_interval(hours => st.short_h) and o.cls = 'deferred') def_s,
           count(*) filter (where r.at > now() - make_interval(hours => st.short_h) and o.cls = 'unmeasured') unm_s,
           count(*) n_l, count(*) filter (where o.cls = 'productive') prod_l, count(*) filter (where o.cls = 'held') held_l, count(*) filter (where o.cls = 'empty') empty_l,
           count(*) filter (where o.cls = 'failed') fail_l, count(*) filter (where o.cls = 'deferred') def_l, count(*) filter (where o.cls = 'unmeasured') unm_l,
           round(avg(r.ms) filter (where r.at > now() - make_interval(hours => st.short_h)) / 1000.0, 2) avg_s,
           round(max(r.ms) filter (where r.at > now() - make_interval(hours => st.short_h)) / 1000.0, 2) max_s, round(avg(r.ms) / 1000.0, 2) avg_l
      from rr r cross join st cross join lateral (select security.pim_outcome_class_v1(r.status, r.result) cls) o
     group by r.k, r.code),
  rhist as (
    select 'lane'::text k, min(due_at) since from pipeline.coverage_lane_runs
    union all select 'rollup', min(due_at) from pipeline.rollup_runs
    union all select 'rule', min(due_at) from pipeline.admission_rule_runs),
  -- next run and the schedule's own period (pg_cron "n seconds" schedules are read as their interval)
  sch as (
    select s.schedule, n1, case when s.schedule ~ '^\d+ seconds?$' then make_interval(secs => split_part(s.schedule, ' ', 1)::int)
                                else security.cron_next_run_v1(s.schedule, n1) - n1 end period
      from (select distinct schedule from cron.job where active union select distinct schedule from reg where schedule is not null) s
      cross join lateral (select case when s.schedule ~ '^\d+ seconds?$' then now() + make_interval(secs => split_part(s.schedule, ' ', 1)::int)
                                      else security.cron_next_run_v1(s.schedule, now()) end n1) x),
  cj as (
    select c.jobid, c.jobname, c.schedule, c.active,
           case when d.jobid is not null then 'dispatcher' when exists (select 1 from reg g where g.legacy_job = c.jobname) then 'moved' else 'own' end role,
           cr.status reg_status, cr.purpose, cr.area, cr.layer,
           (select jsonb_build_object('runner', g.runner, 'kind', g.k, 'code', g.code, 'mode', g.mode, 'enabled', g.enabled) from reg g where g.legacy_job = c.jobname
             order by (g.mode = 'live') desc, g.enabled desc limit 1) moved_to,
           h.first_start, h.last_start, h.last_end, h.last_status, h.last_success, h.last_failure, h.last_failed_at,
           h.n_s, h.prod_s, h.held_s, h.empty_s, h.fail_s, h.unm_s, h.n_l, h.prod_l, h.held_l, h.empty_l, h.fail_l, h.unm_l, h.avg_s, h.max_s, h.avg_l,
           s.n1 next_run, s.period
      from cron.job c
      left join disp d on d.jobid = c.jobid
      left join pipeline.component_register cr on cr.kind = 'job' and cr.name = c.jobname
      left join ch h on h.jobid = c.jobid
      left join sch s on s.schedule = c.schedule and c.active),
  rg as (
    select g.*, h.first_at, h.last_at, h.last_success hist_success, h.last_failure, h.n_s, h.prod_s, h.held_s, h.empty_s, h.fail_s, h.def_s, h.unm_s,
           h.n_l, h.prod_l, h.held_l, h.empty_l, h.fail_l, h.def_l, h.unm_l, h.avg_s, h.max_s, h.avg_l, s.n1 next_run, s.period,
           exists (select 1 from disp d where d.runner = g.runner and d.active) runner_on,
           (select jsonb_agg(d.jobid order by d.jobid) from disp d where d.runner = g.runner) runner_jobids,
           (select x.purpose from pipeline.component_register x where x.kind = 'job' and x.name = g.legacy_job) purpose
      from reg g left join rh h on h.k = g.k and h.code = g.code left join sch s on s.schedule = g.schedule),
  -- states and findings
  cjs as (
    select j.*,
           greatest(make_interval(secs => ((select stall_h from st) * 3600)::int), coalesce(j.period, interval '0') * (select stall_p from st)) stall_after,
           case
             when not j.active and (j.reg_status in ('retiring', 'retired') or j.role = 'moved') then 'retired'
             when not j.active then 'held'
             when coalesce(j.n_s, 0) > 0 and (j.last_status = 'failed' or j.fail_s >= greatest(1, ceil(j.n_s * (select fail_share from st)))) then 'degraded'
             when j.last_success is null and j.last_start is not null and j.last_start > (select since from hist) then 'degraded'
             when j.last_success is not null and j.last_success < now() - greatest(make_interval(secs => ((select stall_h from st) * 3600)::int), coalesce(j.period, interval '0') * (select stall_p from st)) then 'degraded'
             when coalesce(j.n_s, 0) = 0 then 'idle'
             when j.prod_s = 0 and j.held_s = 0 and j.unm_s = 0 and j.empty_s > 0 then 'idle'
             else 'active' end state
      from cj j),
  rgs as (
    select g.*,
           case
             when g.mode = 'shadow' then 'shadow'
             when g.mode <> 'live' then 'held'
             when not g.enabled then 'held'
             when not g.runner_on then 'held'
             when g.open_until > now() then 'degraded'
             when g.last_status = 'failed' or coalesce(g.fail_s, 0) >= greatest(1, ceil(coalesce(g.n_s, 0) * (select fail_share from st))) and coalesce(g.fail_s, 0) > 0 then 'degraded'
             when coalesce(g.last_finished_at, g.last_at) < now() - greatest(make_interval(secs => ((select stall_h from st) * 3600)::int), coalesce(g.period, interval '0') * (select stall_p from st)) then 'degraded'
             when coalesce(g.n_s, 0) = 0 then 'idle'
             when g.prod_s = 0 and g.held_s = 0 and g.unm_s = 0 and g.empty_s > 0 then 'idle'
             else 'active' end state
      from rg g),
  rows_cron as (
    select j.state, jsonb_strip_nulls(jsonb_build_object(
      'component', 'cron', 'jobid', j.jobid, 'name', j.jobname, 'role', j.role, 'schedule', j.schedule, 'active', j.active, 'state', j.state,
      'reason', case j.state
                  when 'retired' then case when j.role = 'moved' then 'switched off; runs on ' || (j.moved_to->>'runner') || ' as ' || (j.moved_to->>'code') else 'switched off; component ' || j.reg_status end
                  when 'held' then 'switched off (cron row inactive) while its component is registered ' || coalesce(j.reg_status, 'nowhere')
                  when 'degraded' then case when j.last_status = 'failed' or coalesce(j.fail_s, 0) > 0 then 'failing' else 'stalled: no success for ' || (select stall_p from st) || ' schedule periods' end
                  when 'idle' then case when coalesce(j.n_s, 0) = 0 then 'not due in the short window' else 'ran and found nothing to do' end end,
      'effective_state', case when j.role = 'moved' then (select g.state from rgs g where g.k = j.moved_to->>'kind' and g.code = j.moved_to->>'code') end,
      'moved_to', j.moved_to, 'purpose', j.purpose, 'area', j.area, 'layer', j.layer, 'registered', j.reg_status,
      'heartbeat', j.last_start, 'last_end', j.last_end, 'last_status', j.last_status, 'last_success', j.last_success,
      'failure_reason', j.last_failure, 'last_failed_at', j.last_failed_at, 'next_run', j.next_run,
      'period_seconds', extract(epoch from j.period)::int, 'stall_after_hours', round(extract(epoch from j.stall_after) / 3600.0, 2),
      'h24', case when j.n_s is null then jsonb_build_object('executions', 0) else jsonb_build_object('executions', j.n_s, 'productive', j.prod_s, 'held', j.held_s, 'empty', j.empty_s, 'failed', j.fail_s, 'unmeasured', j.unm_s, 'avg_seconds', j.avg_s, 'max_seconds', j.max_s) end,
      'd7', case when j.n_l is null then jsonb_build_object('executions', 0, 'partial_since', (select since from hist)) else jsonb_build_object('executions', j.n_l, 'productive', j.prod_l, 'held', j.held_l, 'empty', j.empty_l, 'failed', j.fail_l, 'unmeasured', j.unm_l, 'avg_seconds', j.avg_l,
                     'partial_since', case when (select since from hist) > now() - make_interval(hours => (select long_h from st)) then (select since from hist) end) end,
      'findings', nullif(array_remove(array[
         case when j.active and coalesce(j.fail_s, 0) > 0 then 'failing' end,
         case when j.state = 'degraded' and coalesce(j.fail_s, 0) = 0 and j.last_status is distinct from 'failed' then 'stalled' end,
         case when j.n_l >= (select min_runs from st) and j.prod_l = 0 and j.held_l = 0 and j.unm_l = 0 and j.empty_l >= j.n_l * (select empty_share from st) then 'mostly_empty' end,
         case when j.n_l >= (select min_runs from st) and j.prod_l = 0 and j.held_l >= (j.n_l - j.fail_l) * (select empty_share from st) and j.held_l > 0 then 'repeated_protective_outcome' end,
         case when j.active and j.n_l > 0 and j.unm_l = j.n_l then 'outcome_unmeasured' end,
         case when not j.active and j.last_start > now() - make_interval(hours => (select short_h from st)) then 'switched_off_in_window' end,
         case when j.active and j.role = 'moved' then 'runs_beside_its_register_row' end], null), '{}')))
      j_row from cjs j),
  rows_reg as (
    select g.state, jsonb_strip_nulls(jsonb_build_object(
      'component', g.k, 'code', g.code, 'kind', g.sub, 'runner', g.runner, 'runner_jobids', g.runner_jobids, 'legacy_job', g.legacy_job, 'schedule', g.schedule,
      'enabled', g.enabled, 'mode', g.mode, 'state', g.state,
      'reason', case g.state
                  when 'shadow' then 'runs in shadow; the legacy job stays the effective worker'
                  when 'held' then case when g.mode <> 'live' then 'register mode ' || g.mode when not g.enabled then 'switched off in the register' else 'its dispatcher is switched off' end
                  when 'degraded' then case when g.open_until > now() then 'circuit open until ' || to_char(g.open_until at time zone 'Australia/Melbourne', 'DD Mon HH24:MI') || ' after ' || g.consecutive_failures || ' failures'
                                            when g.last_status = 'failed' or coalesce(g.fail_s, 0) > 0 then 'failing' else 'stalled: no run for ' || (select stall_p from st) || ' schedule periods' end
                  when 'idle' then case when coalesce(g.n_s, 0) = 0 then 'not due in the short window' else 'ran and found nothing to do' end end,
      'purpose', coalesce(g.purpose, g.note), 'field', g.field, 'owner', g.owner, 'uses_ai', g.uses_ai, 'fills', g.fill_function,
      'heartbeat', g.last_started_at, 'last_end', g.last_finished_at, 'last_status', g.last_status, 'last_success', g.hist_success,
      'failure_reason', coalesce(g.last_failure, case when g.last_status = 'failed' then left(g.last_error, 240) end), 'consecutive_failures', nullif(g.consecutive_failures, 0),
      'circuit_open_until', case when g.open_until > now() then g.open_until end, 'next_run', case when g.state not in ('held') then g.next_run end,
      'period_seconds', extract(epoch from g.period)::int, 'budget_ms', g.budget_ms, 'last_ms', g.last_ms,
      'h24', jsonb_build_object('executions', coalesce(g.n_s, 0), 'productive', g.prod_s, 'held', g.held_s, 'empty', g.empty_s, 'failed', g.fail_s, 'deferred', g.def_s, 'unmeasured', g.unm_s, 'avg_seconds', g.avg_s, 'max_seconds', g.max_s),
      'd7', jsonb_build_object('executions', coalesce(g.n_l, 0), 'productive', g.prod_l, 'held', g.held_l, 'empty', g.empty_l, 'failed', g.fail_l, 'deferred', g.def_l, 'unmeasured', g.unm_l, 'avg_seconds', g.avg_l,
                     'partial_since', (select h.since from rhist h where h.k = g.k and h.since > now() - make_interval(hours => (select long_h from st)))),
      'findings', nullif(array_remove(array[
         case when g.open_until > now() then 'circuit_open' end,
         case when coalesce(g.fail_s, 0) > 0 then 'failing' end,
         case when g.state = 'degraded' and not coalesce(g.open_until > now(), false) and coalesce(g.fail_s, 0) = 0 and g.last_status is distinct from 'failed' then 'stalled' end,
         case when g.n_l >= (select min_runs from st) and g.prod_l = 0 and g.held_l = 0 and g.unm_l = 0 and g.empty_l >= (g.n_l - g.def_l) * (select empty_share from st) and g.empty_l > 0 then 'mostly_empty' end,
         case when g.n_l >= (select min_runs from st) and g.prod_l = 0 and g.held_l > 0 and g.held_l >= (g.n_l - g.fail_l - g.def_l) * (select empty_share from st) then 'repeated_protective_outcome' end,
         case when g.n_l >= (select min_runs from st) and g.def_l >= g.n_l * (select deferred_share from st) then 'often_deferred' end,
         case when g.mode = 'live' and g.enabled and g.n_l > 0 and g.unm_l + coalesce(g.def_l, 0) = g.n_l then 'outcome_unmeasured' end], null), '{}')))
      j_row from rgs g),
  allrows as (select state, j_row from rows_cron union all select state, j_row from rows_reg),
  ai as (
    select a.service_code, count(*) filter (where a.at > now() - make_interval(hours => st.short_h)) n_s,
           count(*) filter (where a.at > now() - make_interval(hours => st.short_h) and a.outcome is distinct from 'ok' and a.outcome is distinct from 'success') nf_s,
           round(sum(a.cost_usd) filter (where a.at > now() - make_interval(hours => st.short_h)), 4) usd_s,
           count(*) n_l, count(*) filter (where a.outcome is distinct from 'ok' and a.outcome is distinct from 'success') nf_l, round(sum(a.cost_usd), 4) usd_l
      from pipeline.ai_invocations a cross join st where a.at > now() - make_interval(hours => st.long_h) group by 1),
  fc as (
    select f.use_case, count(*) filter (where f.at > now() - make_interval(hours => st.short_h)) n_s, round(sum(f.credits_used) filter (where f.at > now() - make_interval(hours => st.short_h)), 1) cr_s,
           count(*) filter (where f.at > now() - make_interval(hours => st.short_h) and not coalesce(f.success, false)) nf_s,
           count(*) n_l, round(sum(f.credits_used), 1) cr_l, count(*) filter (where not coalesce(f.success, false)) nf_l
      from pipeline.firecrawl_calls f cross join st where f.at > now() - make_interval(hours => st.long_h) group by 1)
  select jsonb_build_object(
    'as_at', now(),
    'windows', jsonb_build_object('short_hours', (select short_h from st), 'long_hours', (select long_h from st)),
    'history', jsonb_build_object('cron_since', (select since from hist), 'lanes_since', (select since from rhist where k = 'lane'),
                                  'rollups_since', (select since from rhist where k = 'rollup'), 'rules_since', (select since from rhist where k = 'rule')),
    'states', (select jsonb_object_agg(s, coalesce((select count(*) from allrows a where a.state = s), 0)) from unnest(array['active', 'idle', 'held', 'degraded', 'retired', 'shadow']) s),
    'components', coalesce((select jsonb_agg(a.j_row order by array_position(array['degraded', 'held', 'active', 'idle', 'shadow', 'retired'], a.state), a.j_row->>'component', coalesce(a.j_row->>'name', a.j_row->>'code')) from allrows a), '[]'::jsonb),
    'toolset', jsonb_build_object(
      'ai', coalesce((select jsonb_agg(jsonb_build_object('service', service_code, 'h24', jsonb_build_object('attempts', n_s, 'not_ok', nf_s, 'billed_usd', usd_s), 'd7', jsonb_build_object('attempts', n_l, 'not_ok', nf_l, 'billed_usd', usd_l)) order by usd_l desc nulls last) from ai), '[]'::jsonb),
      'firecrawl', coalesce((select jsonb_agg(jsonb_build_object('use_case', use_case, 'h24', jsonb_build_object('calls', n_s, 'failed', nf_s, 'credits', cr_s), 'd7', jsonb_build_object('calls', n_l, 'failed', nf_l, 'credits', cr_l)) order by cr_l desc nulls last) from fc), '[]'::jsonb),
      'attribution', 'By service and use case only: no register links a scheduled job, lane, rule or target to an AI service or a Firecrawl use case, so spend is not split per component.'),
    'meaning', 'One row per cron job (by jobid) and per dispatcher lane, rollup target and admission rule. productive: an admission, publication or hand-off counter above 0; held: only protective counters (Layer 4, held, refused, left for a person); empty: a structured result with every counter at 0; unmeasured: the run records no structured result, so its outcome is measured downstream only, never as 0. partial_since: the retained history starts after the window start.')
$f$;
comment on function security.data_delivery_jobs_v1() is 'PIM (s1176): the jobs Data Delivery helper: every cron job by jobid and every dispatcher lane, rollup target and admission rule, with state, heartbeat, next run, failure reason, outcome classes (24 h and 7 d) and toolset use; counted only in the background PIM snapshot (pim.operations).';
revoke all on function security.data_delivery_jobs_v1() from public, anon, authenticated;
grant execute on function security.data_delivery_jobs_v1() to service_role;

create or replace function security.pim_operations_v1()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $f$
  with st as (select security.pipeline_num_v1('pim.refresh_days', 365)::int d),
  js as (select j rows, (j->>'as_at')::timestamptz measured_at from (select security.data_delivery_jobs_v1() j) x),
  comp as (select c from js cross join lateral jsonb_array_elements(coalesce(js.rows->'components', '[]'::jsonb)) c),
  w as (select c from comp where c->>'component' = 'cron' and (c->>'active')::boolean and c->>'name' <> 'data-delivery'),
  f as (
    select k.iso_alpha2 cc, a.attribute field, count(*) held,
           count(*) filter (where co.last_verified_at is null or co.last_verified_at < now() - make_interval(days => coalesce(fr.refresh_days, st.d))) refresh_due
      from pipeline.course_attribute_coverage a cross join st
      join pipeline.field_register fr on fr.field = a.attribute
      join catalogue.courses co on co.id = a.course_id and co.lifecycle_status = 'active'
      join catalogue.providers p on p.id = co.provider_id join ref.countries k on k.id = p.country_id
     where a.state = 'admitted' and not exists (select 1 from security.provider_hidden_v1 x where x.provider_id = p.id)
     group by 1, 2)
  select jsonb_build_object(
    'as_at', now(),
    'jobs_summary_at', (select measured_at from js),
    'jobs_snapshot', jsonb_build_object('as_at', (select measured_at from js),
                                        'windows', (select rows->'windows' from js), 'history', (select rows->'history' from js)),
    'workers', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                         'job', c->>'name', 'jobid', (c->>'jobid')::int, 'role', c->>'role', 'schedule', c->>'schedule',
                         'last_start', c->'heartbeat', 'last_success', c->'last_success', 'failed_24h', coalesce((c->'h24'->>'failed')::int, 0),
                         'running', c->>'last_status' in ('running', 'starting'),
                         'stalled', c->>'state' = 'degraded' and 'stalled' = any (array(select jsonb_array_elements_text(coalesce(c->'findings', '[]'::jsonb)))),
                         'state', c->>'state', 'reason', c->>'reason', 'heartbeat', c->'heartbeat', 'last_end', c->'last_end', 'last_status', c->>'last_status',
                         'next_run', c->'next_run', 'failure_reason', c->>'failure_reason', 'purpose', c->>'purpose',
                         'effective_state', coalesce(c->>'effective_state', c->>'state'), 'h24', c->'h24', 'd7', c->'d7', 'findings', c->'findings'))
                         order by c->>'name', (c->>'jobid')::int) from w), '[]'::jsonb),
    'stalled_workers', (select count(*) from w where c->>'state' = 'degraded' and 'stalled' = any (array(select jsonb_array_elements_text(coalesce(c->'findings', '[]'::jsonb))))),
    'components', coalesce((select rows->'components' from js), '[]'::jsonb),
    'states', (select rows->'states' from js),
    'holds', coalesce((select jsonb_agg(jsonb_build_object('component', c->>'component', 'jobid', c->'jobid', 'name', coalesce(c->>'name', c->>'code'), 'reason', c->>'reason', 'last_run', c->'heartbeat'))
                         from comp where c->>'state' = 'held'), '[]'::jsonb),
    'toolset', (select rows->'toolset' from js),
    'expired_leases', (select count(*) from pipeline.field_enrich_items e where e.state in ('leased', 'ai') and e.leased_until < now()),
    'freshness_by_country', coalesce((select jsonb_agg(jsonb_build_object('country', cc, 'field', field, 'held', held, 'refresh_due', refresh_due) order by cc, field) from f), '[]'::jsonb),
    'consumer', coalesce((select jsonb_agg(jsonb_build_object('stream', r.stream, 'rows', r.rows, 'measured_at', r.measured_at, 'error', r.error) order by r.stream)
                            from pipeline.data_delivery_readings r where r.measure = 'consumer'), '[]'::jsonb),
    'requests', jsonb_build_object('status', 'not_projected', 'reason', 'No registered database source holds the StudySearch request register; it is kept by the requirements register outside the database.'),
    'meaning', 'Workers are every active scheduled job, by jobid, from the jobs read (security.data_delivery_jobs_v1), counted in the background PIM snapshot; stalled means no success within pim.jobs_stall_periods of its own schedule (never less than plans.auto_stall_hours). components adds every dispatcher lane, rollup target and admission rule, with state, outcomes and findings. Consumer figures are the existing verified read-back of what the website and Zoho read.')
$f$;
comment on function security.pim_operations_v1() is 'PIM (s1175, s1176): every active worker by jobid, every lane, rule and target with state and effectiveness (jobs helper snapshot), freshness by country, verified consumer read-back; counted into the Data Delivery snapshot (pim.operations).';
revoke all on function security.pim_operations_v1() from public, anon, authenticated;
grant execute on function security.pim_operations_v1() to service_role;

do $c$
declare v jsonb := security.consumer_api_check_v1(); j jsonb; o jsonb; b record;
begin
  select * into b from s1176_before;
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'guard: consumer API moved: %', v; end if;
  if (select count(*) from pipeline.manual_locks) < b.locks then raise exception 'guard: a manual lock was removed'; end if;
  if (select count(*) from cron.job where active) <> b.jobs or (select count(*) from cron.job) <> b.jobs_all then raise exception 'guard: the scheduler changed'; end if;
  if (select count(*) from cron.job where active) > 140 then raise exception 'guard: active cron above 140'; end if;  -- fixed: protected ceiling
  if position('security.pim_operations_v1()' in pg_get_functiondef('security.data_delivery_refresh_v1(boolean)'::regprocedure)) = 0 then raise exception 'guard: pim.operations is not in the background count'; end if;
  if position('pim_operations_v1' in pg_get_functiondef('security.data_delivery_v1()'::regprocedure)) > 0 then raise exception 'guard: the screen read counts operations live'; end if;
  j := security.data_delivery_jobs_v1();
  if jsonb_array_length(j->'components') <> (select count(*) from cron.job) + (select count(*) from pipeline.field_execution_registry) + (select count(*) from pipeline.rollup_targets) + (select count(*) from pipeline.admission_rules)
    then raise exception 'guard: a component is missing from the jobs helper'; end if;
  if (select count(distinct (c->>'jobid')) from jsonb_array_elements(j->'components') c where c->>'component' = 'cron') <> (select count(*) from cron.job) then raise exception 'guard: cron rows not keyed by jobid'; end if;
  o := security.pim_operations_v1();
  if jsonb_array_length(o->'workers') <> (select count(*) from cron.job where active and jobname <> 'data-delivery') then raise exception 'guard: workers are not every active job'; end if;
  if jsonb_array_length(o->'freshness_by_country') = 0 or jsonb_array_length(o->'consumer') = 0 then raise exception 'guard: operations read empty'; end if;
  raise notice 'components %, states %, workers %, stalled %', jsonb_array_length(j->'components'), j->'states', jsonb_array_length(o->'workers'), o->'stalled_workers';
end $c$;
