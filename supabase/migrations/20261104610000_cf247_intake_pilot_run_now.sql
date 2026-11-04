-- CF-247 Course Intake Dates pilot and governed Run Now (Platform Admin 4 Nov 2026 20:05, admin docs/platform/2026-11-04-course-intake-pilot-authority-2005.md
-- §1-§5; 20:02 docs/platform/2026-11-04-immediate-production-validation-direction-2002.md §1-§3: the 10-minute gate).
-- Why: production has no general Run Now for a catalogued job (only scheduler_policy_run_now_v1, for Layer 1 policies), so the pilot could only be
--   seen at the next hourly :26 run of intake-dates-apply, over whatever 200 rows came next. The authority asks for a fixed, automatically
--   selected 20-course cohort run at once through the existing job and its own publication path.
-- What (extends the existing task mechanism, pipeline.admin_jobs + pipeline.admin_job_kinds, as governed_action does; no new scheduler, no
--   new extraction engine, no test-only publishing):
--   1 settings (G2): run_now.jobs (list: jobs Run Now may start; intake-dates-apply only), run_now.pilot_cap (20 courses),
--     run_now.cohort_scan_rows (intake rows the cohort selection plans over).
--   2 task kind 'job_run_now': each Run Now is one pipeline.admin_jobs row, written when it has run ('done' / 'failed') or been refused
--     ('cancelled'); never queued, so the task runner never takes it. Requester, reason, run id, start, finish and counts are on that row.
--   3 pipeline.run_now_cohorts and pipeline.run_now_cohort_members: a fixed cohort, its selection rule and the evidence of each member at selection.
--   4 security.intake_dates_apply_v1(integer, uuid[]): the live job body (md5 d15c04c680dc0128ca5da33556426c43) with a bounded course selector
--     passed to the plan's own uuid[] argument; with a selector, the provenance back-fill is limited to the selected courses. The live
--     security.intake_dates_apply_v1(integer) (md5-guarded) becomes a call of it with no selector: the scheduled job is unchanged in behaviour.
--   5 security.run_now_cohort_create_v1(job, requester, reason): picks the cohort through the job's own plan (security.intake_dates_plan_v2)
--     over the job's next run_now.cohort_scan_rows candidate rows: only courses the plan would fill from the approved calendar and the
--     course's own page; most gaps closed first (year, start date, deadline), spread across providers and evidence patterns. Nothing hand-picked.
--   6 security.job_run_now_v1(job, reason, args, requester) and public.admin_job_run_now_v1(job, reason, args) (signed-in, rank as catalogued):
--     allowlisted, catalogued, scheduled and not paused, job switch on, reason given, cohort within the cap, one run at a time (the job's own
--     advisory lock, tried, not waited for; a duplicate is refused and the run holding it returned; an idempotency key returns the earlier run).
--     It runs the job's own function only; no SQL text is ever taken from the request.
--   7 security.run_now_cohort_verify_v1(cohort): per course before and after, rows filled, the evidence quoted, the Website API v2 read-back
--     (api.website_v2_course_item) and Zoho (public.zoho_edge_course_lookup_v1) where it answers; totals for the §6 table. Writes nothing itself.
-- Replaces: security.intake_dates_apply_v1(integer) (md5-guarded edit, same name: now calls the bounded form with no selector)
-- Retires: nothing
-- Nothing is dropped, deleted or switched on; no job is scheduled, resumed or changed; no catalogue row changes when this migration is applied.
-- Consumer API untouched (G3): read only, by the verification function.

-- the live definition this change edits
do $g$ begin
  if to_regprocedure('security.intake_dates_apply_v1(integer,uuid[])') is null
     and md5(pg_get_functiondef('security.intake_dates_apply_v1(integer)'::regprocedure)) <> 'd15c04c680dc0128ca5da33556426c43' then
    raise exception 'live security.intake_dates_apply_v1(integer) differs from the definition this change edits (md5 %)',
      md5(pg_get_functiondef('security.intake_dates_apply_v1(integer)'::regprocedure));
  end if;
end $g$;

-- 1 settings (G2) --------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'run_now.jobs', 'Run now: jobs it may start',
  'The catalogued jobs a Platform Admin may start at once with Run now, on a fixed cohort, through the job''s own function and rules. A job not listed here is refused.',
  'list', '["intake-dates-apply"]'::jsonb, null, null, 'jobs', 1101, 'Run now', 'security.job_run_now_v1 (public.admin_job_run_now_v1)',
  'Platform Admin 4 Nov 2026 20:05 §3: governed Run Now for an existing catalogue job'),
 ('pipeline', 'run_now.pilot_cap', 'Run now: most courses in a cohort',
  'The most courses a Run now cohort holds, and so the most one Run now may touch.', 'number',
  to_jsonb(20), 1, 200, 'courses', 1102, 'Run now', 'security.run_now_cohort_create_v1; security.job_run_now_v1',
  'Platform Admin 4 Nov 2026 20:05 §1 and §3: pilot batch cap of 20 courses'),
 ('pipeline', 'run_now.cohort_scan_rows', 'Run now: intake rows looked at to pick a cohort',
  'A cohort is picked from the job''s own plan for its next this-many candidate intake rows (read only). Larger finds more eligible courses and takes longer.', 'number',
  to_jsonb(1500), 20, 10000, 'rows', 1103, 'Run now', 'security.run_now_cohort_create_v1',
  'Platform Admin 4 Nov 2026 20:05 §1: select courses through existing eligibility rules')
on conflict (toolset_key, key) do nothing;

-- 2 the task kind --------------------------------------------------------------------------------------------------------------------
insert into pipeline.admin_job_kinds(kind, label, what, can_pause, added_in)
values ('job_run_now', 'Run now', 'A catalogued job run at once on a fixed cohort by a Platform Admin, through the job''s own function and rules: allowlisted, not paused, one at a time, with a reason. Written when it has run or been refused; never queued.', false, 'CF-247 4 Nov 2026 20:05')
on conflict (kind) do nothing;
create unique index if not exists admin_jobs_run_now_idempotency_uq on pipeline.admin_jobs ((args->>'idempotency_key')) where kind = 'job_run_now' and args ? 'idempotency_key';

-- 3 the fixed cohort -------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.run_now_cohorts(
  id uuid primary key default gen_random_uuid(),
  job text not null references pipeline.automation_catalogue(jobname),
  label text not null,
  selection_rule text not null,
  selection jsonb not null default '{}'::jsonb,
  requested_by uuid not null,
  reason text not null,
  created_at timestamptz not null default now());
comment on table pipeline.run_now_cohorts is 'CF-247 Run now (Platform Admin 4 Nov 2026 20:05 §1, §3): a fixed cohort picked automatically by the job''s own plan for a Run now and its audit: the rule, the settings used, how many rows and courses were looked at and found eligible (the denominator), who asked and why. Never read by the consumer API.';
create table if not exists pipeline.run_now_cohort_members(
  cohort_id uuid not null references pipeline.run_now_cohorts(id),
  course_id uuid not null,
  provider_id uuid not null,
  pick int not null,
  pattern text not null,
  fills text[] not null,
  evidence jsonb not null,
  primary key (cohort_id, course_id));
comment on table pipeline.run_now_cohort_members is 'CF-247 Run now (Platform Admin 4 Nov 2026 20:05 §1): the courses of a fixed cohort, the order picked, the evidence pattern, which fields the plan said it would fill, and per intake row the evidence at selection (approved calendar, its document, the page wording and calendar quotes, the value before and the value planned). Never read by the consumer API.';
alter table pipeline.run_now_cohorts enable row level security;
alter table pipeline.run_now_cohort_members enable row level security;
revoke all on pipeline.run_now_cohorts, pipeline.run_now_cohort_members from anon, authenticated;

-- 4 the job with a bounded selector ----------------------------------------------------------------------------------------------------
create or replace function security.intake_dates_apply_v1(p_limit integer, p_course_ids uuid[])
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_on boolean := coalesce((security.toolset_setting('pipeline', 'intake_dates.apply_enabled') #>> '{}')::boolean, false);
        v_filled int := 0; v_seen int := 0; v_courses uuid[] := '{}'; p record; v_n int; v_prov int := 0;
begin
  if not v_on then return jsonb_build_object('enabled', false, 'filled', 0); end if;
  perform pg_advisory_xact_lock(hashtext('cf247 intake dates apply'));  -- fixed: one run at a time
  -- 23:24 provenance: values filled before the page wording was kept get it now (as stored now), with the approved calendar's document
  update pipeline.course_intake_dates d
     set page_quote = coalesce(left(security.intake_page_wording_v1(d.course_id, i.evidence_id, e.source_url), 600), ''),
         calendar_evidence_id = cal.evidence_id, calendar_url = cal.url
    from catalogue.course_intakes i left join pipeline.evidence_artifacts e on e.id = i.evidence_id, pipeline.provider_policy_proposals cal
   where d.intake_id in (select d2.intake_id from pipeline.course_intake_dates d2 where d2.outcome = 'filled' and d2.calendar_url is null
                            and (p_course_ids is null or d2.course_id = any (p_course_ids))
                          limit security.pipeline_num_v1('batch.intake_dates_apply', 200)::int)
     and i.id = d.intake_id and cal.id = d.proposal_id;
  get diagnostics v_prov = row_count;
  for p in select * from security.intake_dates_plan_v2(p_course_ids, p_limit) loop
    v_seen := v_seen + 1;
    if p.outcome = 'filled' then
      update catalogue.course_intakes i
         set intake_year = coalesce(i.intake_year, p.new_year), start_date = coalesce(i.start_date, p.new_start),
             application_deadline = coalesce(i.application_deadline, p.new_deadline)
       where i.id = p.intake_id and i.status = 'active'
         and (i.intake_year is null or i.intake_year = coalesce(p.new_year, i.intake_year));
      get diagnostics v_n = row_count;  -- 0 when a lock or the same-month guard kept the row as it was
      if v_n = 1 then v_filled := v_filled + 1; v_courses := v_courses || p.course_id; end if;
    end if;
    insert into pipeline.course_intake_dates(intake_id, course_id, provider_id, proposal_id, outcome, reason, periods, start_precision, deadline_kind, deadline_text,
                                             start_quote, deadline_quote, before_value, after_value, applied_at, page_quote, calendar_evidence_id, calendar_url, rule)
    select p.intake_id, p.course_id, p.provider_id, p.proposal_id,
           case when p.outcome = 'filled' and v_n = 0 then 'skipped' else p.outcome end,
           case when p.outcome = 'filled' and v_n = 0 then 'kept by a lock or the same-month guard' else p.reason end,
           p.periods, p.start_precision, p.deadline_kind, p.deadline_text, p.start_quote, p.deadline_quote, p.before_value,
           (select jsonb_build_object('year', i.intake_year, 'start_date', i.start_date, 'application_deadline', i.application_deadline) from catalogue.course_intakes i where i.id = p.intake_id), now(),
           p.page_quote, p.calendar_evidence_id, p.calendar_url, p.rule
    on conflict (intake_id) do update set proposal_id = excluded.proposal_id, outcome = excluded.outcome, reason = excluded.reason, periods = excluded.periods,
           start_precision = excluded.start_precision, deadline_kind = excluded.deadline_kind, deadline_text = excluded.deadline_text, start_quote = excluded.start_quote,
           deadline_quote = excluded.deadline_quote, before_value = excluded.before_value, after_value = excluded.after_value, applied_at = excluded.applied_at,
           page_quote = excluded.page_quote, calendar_evidence_id = excluded.calendar_evidence_id, calendar_url = excluded.calendar_url, rule = excluded.rule;
    v_n := null;
  end loop;
  if cardinality(v_courses) > 0 then
    perform search.refresh_course_enrichment_scoped_v1((select array_agg(distinct x) from unnest(v_courses) x), true);
  end if;
  return jsonb_build_object('enabled', true, 'looked_at', v_seen, 'filled', v_filled, 'provenance_completed', v_prov, 'courses', coalesce(cardinality((select array_agg(distinct x) from unnest(v_courses) x)), 0),
                            'bounded', p_course_ids is not null, 'selected_courses', coalesce(cardinality(p_course_ids), 0));
end $function$;
revoke all on function security.intake_dates_apply_v1(integer, uuid[]) from public, anon, authenticated;
comment on function security.intake_dates_apply_v1(integer, uuid[]) is 'CF-247 intake dates, job intake-dates-apply with a bounded course selector (Platform Admin 4 Nov 2026 20:05 §3): the job''s body, with the selected courses passed to security.intake_dates_plan_v2. A null selector is the scheduled job. Called by security.intake_dates_apply_v1(integer) and by Run now (security.job_run_now_v1).';

create or replace function security.intake_dates_apply_v1(p_limit integer default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  -- 4 Nov 2026 (Run now): the body is security.intake_dates_apply_v1(integer, uuid[]); no selector is the scheduled job, as before
  return security.intake_dates_apply_v1(p_limit, null::uuid[]);
end $function$;
revoke all on function security.intake_dates_apply_v1(integer) from public, anon, authenticated;

-- 5 the cohort, picked by the job's own plan ---------------------------------------------------------------------------------------------
create or replace function security.run_now_cohort_create_v1(p_job text, p_requester uuid, p_reason text, p_label text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_cap int := security.pipeline_num_v1('run_now.pilot_cap', 20)::int;
        v_scan int := security.pipeline_num_v1('run_now.cohort_scan_rows', 1500)::int;
        v_id uuid := gen_random_uuid(); v_rows int; v_filled_rows int; v_courses int; v_providers int; v_n int;
        v_rule constant text := 'intake-dates-plan-v2 filled; most fields gained first; round-robin over providers, then evidence patterns; md5(course id) breaks ties';  -- fixed: the name of this rule in the record
begin
  if p_job is distinct from 'intake-dates-apply' then raise exception 'no cohort rule for job %', p_job; end if;
  if p_requester is null then raise exception 'a requester is required'; end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'a reason is required'; end if;
  if not exists (select 1 from pipeline.automation_catalogue where jobname = p_job) then raise exception 'job % is not catalogued', p_job; end if;
  -- one statement: the job's plan (read only), the denominator, the cohort record and its members
  with plan as materialized (select * from security.intake_dates_plan_v2(null, v_scan)),
  f as (select * from plan where outcome = 'filled'),
  sel as (select (select count(*) from plan) rows_planned, count(*) rows_eligible, count(distinct course_id) courses_eligible, count(distinct provider_id) providers_eligible from f),
  coh as (
    insert into pipeline.run_now_cohorts(id, job, label, selection_rule, selection, requested_by, reason)
    select v_id, p_job, coalesce(nullif(btrim(p_label), ''), 'Intake dates pilot ' || to_char(now() at time zone 'Australia/Melbourne', 'DD Mon YYYY HH24:MI')), v_rule,
           jsonb_build_object('rows_planned', sel.rows_planned, 'rows_eligible', sel.rows_eligible, 'courses_eligible', sel.courses_eligible,
                              'providers_eligible', sel.providers_eligible, 'cap', v_cap, 'scan_rows', v_scan, 'skipped_by_reason',
                              (select coalesce(jsonb_object_agg(r, n), '{}'::jsonb) from (select coalesce(reason, outcome) r, count(*) n from plan where outcome <> 'filled' group by 1) x)),
           p_requester, btrim(p_reason)
      from sel returning id),
  c as (select course_id, min(provider_id::text)::uuid provider_id,
               array_remove(array[case when bool_or(new_year is not null) then 'year' end, case when bool_or(new_start is not null) then 'start_date' end,
                                  case when bool_or(new_deadline is not null) then 'application_deadline' end], null) fills,
               string_agg(distinct coalesce(start_precision, '-') || '/' || coalesce(deadline_kind, '-'), '+') pattern,
               jsonb_agg(jsonb_build_object('intake_id', intake_id, 'proposal_id', proposal_id, 'calendar_evidence_id', calendar_evidence_id, 'calendar_url', calendar_url,
                         'periods', periods, 'page_quote', page_quote, 'start_quote', start_quote, 'deadline_quote', deadline_quote, 'deadline_kind', deadline_kind,
                         'before', before_value, 'planned', jsonb_build_object('year', new_year, 'start_date', new_start, 'application_deadline', new_deadline), 'rule', rule)
                         order by intake_id) evidence
          from f group by course_id),
  r as (select c.*, row_number() over (partition by provider_id order by cardinality(fills) desc, md5(course_id::text)) rp,
               row_number() over (partition by pattern order by cardinality(fills) desc, md5(course_id::text)) rq from c),
  pick as (select r.*, row_number() over (order by rp, rq, cardinality(fills) desc, md5(course_id::text)) n from r),
  ins as (insert into pipeline.run_now_cohort_members(cohort_id, course_id, provider_id, pick, pattern, fills, evidence)
          select coh.id, pick.course_id, pick.provider_id, pick.n, pick.pattern, pick.fills, pick.evidence from pick, coh where pick.n <= v_cap returning 1)
  select (select count(*) from ins), sel.rows_planned, sel.rows_eligible, sel.courses_eligible, sel.providers_eligible
    into v_n, v_rows, v_filled_rows, v_courses, v_providers from sel;
  return jsonb_build_object('cohort_id', v_id, 'job', p_job, 'members', v_n, 'cap', v_cap, 'rows_planned', v_rows, 'rows_eligible', v_filled_rows,
                            'courses_eligible', v_courses, 'providers_eligible', v_providers,
                            'providers_in_cohort', (select count(distinct provider_id) from pipeline.run_now_cohort_members where cohort_id = v_id),
                            'patterns_in_cohort', (select count(distinct pattern) from pipeline.run_now_cohort_members where cohort_id = v_id));
end $function$;
revoke all on function security.run_now_cohort_create_v1(text, uuid, text, text) from public, anon, authenticated;
comment on function security.run_now_cohort_create_v1(text, uuid, text, text) is 'CF-247 Run now (Platform Admin 4 Nov 2026 20:05 §1): picks a fixed cohort of at most run_now.pilot_cap courses for job intake-dates-apply from its own plan (security.intake_dates_plan_v2, read only) over run_now.cohort_scan_rows candidate rows; records the rule, the denominator and each member''s evidence. Never hand-picked.';

-- 6 Run now --------------------------------------------------------------------------------------------------------------------------
create or replace function security.job_run_now_v1(p_job text, p_reason text, p_args jsonb, p_requester uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_cap int := security.pipeline_num_v1('run_now.pilot_cap', 20)::int;
        v_id uuid := gen_random_uuid(); v_key text := nullif(btrim(coalesce(p_args->>'idempotency_key', '')), '');
        v_cohort pipeline.run_now_cohorts%rowtype; v_ids uuid[]; v_rank int; v_cat pipeline.automation_catalogue%rowtype;
        v_prev pipeline.admin_jobs%rowtype; v_why text; v_res jsonb; v_start timestamptz := clock_timestamp(); v_calls int; v_by jsonb; v_holder jsonb;
        v_err text; v_title text;
begin
  if p_requester is null then raise exception 'a requester is required'; end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'a reason is required'; end if;
  if v_key is not null then
    select * into v_prev from pipeline.admin_jobs where kind = 'job_run_now' and args->>'idempotency_key' = v_key;
    if found then return jsonb_build_object('run_id', v_prev.id, 'state', v_prev.state, 'repeat', true, 'result', v_prev.result); end if;
  end if;
  select * into v_cat from pipeline.automation_catalogue where jobname = p_job;
  select coalesce(max(r.rank), 0) into v_rank from security.user_roles ur join security.roles r on r.code = ur.role_code
   where ur.user_id = p_requester and (ur.expires_at is null or ur.expires_at > now()) and r.status = 'active';
  select * into v_cohort from pipeline.run_now_cohorts where id = nullif(p_args->>'cohort_id', '')::uuid;
  v_ids := array(select m.course_id from pipeline.run_now_cohort_members m where m.cohort_id = v_cohort.id order by m.pick);
  v_why := case
    when not (p_job = any (array(select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'run_now.jobs'), '[]'::jsonb))))) then 'job is not on the Run now list'
    when v_cat.jobname is null then 'job is not catalogued'
    when v_rank < greatest(coalesce(v_cat.control_rank, 6), 1) then 'requester rank ' || v_rank || ' is below the job''s rank ' || coalesce(v_cat.control_rank, 6)
    when not exists (select 1 from cron.job j where j.jobname = p_job) then 'job is not scheduled'
    when exists (select 1 from cron.job j where j.jobname = p_job and not j.active) then 'job is paused'
    when p_job = 'intake-dates-apply' and not coalesce((security.toolset_setting('pipeline', 'intake_dates.apply_enabled') #>> '{}')::boolean, false) then 'job switch is off (Intake dates: on)'
    when p_job <> 'intake-dates-apply' then 'no bounded runner for this job'
    when v_cohort.id is null then 'a cohort_id is required'
    when v_cohort.job <> p_job then 'cohort belongs to job ' || v_cohort.job
    when coalesce(cardinality(v_ids), 0) = 0 then 'cohort has no courses'
    when cardinality(v_ids) > v_cap then 'cohort has ' || cardinality(v_ids) || ' courses, over the cap of ' || v_cap
    when not pg_try_advisory_xact_lock(hashtext('cf247 intake dates apply')) then 'a run of this job is in progress'  -- the job's own lock, tried, never waited for
  end;
  v_title := 'Run now: ' || coalesce(v_cat.label, p_job) || coalesce(' (' || v_cohort.label || ')', '');
  if v_why is not null then
    if v_why = 'a run of this job is in progress' then
      select jsonb_build_object('pid', a.pid, 'since', a.query_start, 'query', left(a.query, 160)) into v_holder
        from pg_catalog.pg_locks l join pg_catalog.pg_stat_activity a on a.pid = l.pid
       where l.locktype = 'advisory' and l.granted and l.objid = (hashtext('cf247 intake dates apply')::bigint & 4294967295)::oid and a.pid <> pg_backend_pid() limit 1;
    end if;
    insert into pipeline.admin_jobs(id, kind, lane, state, title, args, result, requested_by, reason, created_at, started_at, updated_at, finished_at, scope, outcome)
    values (v_id, 'job_run_now', 'run_now', 'cancelled', v_title || ' (refused)',
            jsonb_strip_nulls(jsonb_build_object('job', p_job, 'cohort_id', v_cohort.id, 'idempotency_key', v_key)),
            jsonb_strip_nulls(jsonb_build_object('refused', v_why, 'in_flight', v_holder)), p_requester, btrim(p_reason), v_start, v_start, clock_timestamp(), clock_timestamp(),
            'cohort:' || coalesce(v_cohort.id::text, '-'), 'refused');
    return jsonb_strip_nulls(jsonb_build_object('run_id', v_id, 'state', 'refused', 'refused', v_why, 'in_flight', v_holder));
  end if;
  begin
    v_res := security.intake_dates_apply_v1(security.pipeline_num_v1('batch.intake_dates_apply', 200)::int, v_ids);
  exception when others then
    get stacked diagnostics v_err = message_text;
  end;
  -- vendor calls made while it ran (the job reads stored readings only; any call here is unexpected spend)
  select count(*) into v_calls from pipeline.edge_request_log l where l.created_at >= v_start;
  select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) into v_by from (
    select d.outcome || coalesce(': ' || d.reason, '') k, count(*) n from pipeline.course_intake_dates d
     where d.course_id = any (v_ids) and d.applied_at = now() group by 1) x;
  v_res := coalesce(v_res, '{}'::jsonb) || jsonb_build_object(
    'processed', coalesce((v_res->>'looked_at')::int, 0), 'admitted', coalesce((v_res->>'filled')::int, 0),
    'skipped', coalesce((v_res->>'looked_at')::int, 0) - coalesce((v_res->>'filled')::int, 0), 'failed', case when v_err is null then 0 else 1 end,
    'by_outcome', v_by, 'vendor_calls', v_calls, 'cohort_id', v_cohort.id, 'courses', cardinality(v_ids), 'error', v_err);
  insert into pipeline.admin_jobs(id, kind, lane, state, title, args, result, error, requested_by, reason, created_at, started_at, updated_at, finished_at, scope, outcome)
  values (v_id, 'job_run_now', 'run_now', case when v_err is null then 'done' else 'failed' end, v_title,
          jsonb_strip_nulls(jsonb_build_object('job', p_job, 'cohort_id', v_cohort.id, 'idempotency_key', v_key, 'courses', cardinality(v_ids))),
          v_res, v_err, p_requester, btrim(p_reason), v_start, v_start, clock_timestamp(), clock_timestamp(), 'cohort:' || v_cohort.id, case when v_err is null then 'ran' else 'failed' end);
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('run_now', case when v_err is null then 'ran' else 'failed' end, p_job, jsonb_build_object('task', v_id, 'cohort_id', v_cohort.id, 'result', v_res), p_requester);
  return jsonb_build_object('run_id', v_id, 'state', case when v_err is null then 'done' else 'failed' end, 'started_at', v_start, 'finished_at', clock_timestamp()) || v_res;
end $function$;
revoke all on function security.job_run_now_v1(text, text, jsonb, uuid) from public, anon, authenticated;
comment on function security.job_run_now_v1(text, text, jsonb, uuid) is 'CF-247 Run now (Platform Admin 4 Nov 2026 20:05 §3): runs an allowlisted (run_now.jobs), catalogued, scheduled and unpaused job at once on a fixed cohort (run_now.pilot_cap) through the job''s own function and rules; rank as catalogued; reason required; one run at a time (the job''s own advisory lock, tried); idempotency key; records requester, reason, start, finish and counts as a pipeline.admin_jobs row of kind job_run_now. Never takes SQL text.';

create or replace function public.admin_job_run_now_v1(p_job text, p_reason text, p_args jsonb default '{}'::jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if auth.uid() is null then raise exception 'sign in required' using errcode = '42501'; end if;
  if security.current_role_rank() < coalesce((select a.control_rank from pipeline.automation_catalogue a where a.jobname = p_job), 6) then
    raise exception 'your role cannot start this job' using errcode = '42501';
  end if;
  return security.job_run_now_v1(p_job, p_reason, coalesce(p_args, '{}'::jsonb), auth.uid());
end $function$;
revoke all on function public.admin_job_run_now_v1(text, text, jsonb) from public, anon;
grant execute on function public.admin_job_run_now_v1(text, text, jsonb) to authenticated;
comment on function public.admin_job_run_now_v1(text, text, jsonb) is 'CF-247 Run now (Platform Admin 4 Nov 2026 20:05 §3): the signed-in entry to security.job_run_now_v1; rank as the job''s catalogue row says.';

-- 7 verification (writes nothing itself) ------------------------------------------------------------------------------------------------
create or replace function security.run_now_cohort_verify_v1(p_cohort uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare c pipeline.run_now_cohorts%rowtype; m record; v_rows jsonb := '[]'; v_course jsonb; v_web jsonb; v_zoho jsonb; v_added jsonb; v_after jsonb;
        t_sel int := 0; t_elig int := 0; t_adm int := 0; t_pub int := 0; t_zoho int := 0; t_wrong int := 0; v_n int; v_p int; v_w int;
begin
  select * into c from pipeline.run_now_cohorts where id = p_cohort;
  if c.id is null then raise exception 'unknown cohort'; end if;
  for m in select * from pipeline.run_now_cohort_members where cohort_id = p_cohort order by pick loop
    t_sel := t_sel + 1;
    t_elig := t_elig + jsonb_array_length(m.evidence);
    -- values filled for this course since the cohort was picked, with the evidence the job recorded
    select coalesce(jsonb_agg(jsonb_build_object('intake_id', d.intake_id, 'before', d.before_value, 'after', d.after_value, 'periods', d.periods,
                     'page_quote', d.page_quote, 'start_quote', d.start_quote, 'deadline_quote', d.deadline_quote, 'calendar_url', d.calendar_url, 'applied_at', d.applied_at,
                     'as_planned', d.after_value = coalesce(d.before_value, '{}') || jsonb_strip_nulls((select e->'planned' from jsonb_array_elements(m.evidence) e where (e->>'intake_id')::uuid = d.intake_id)))
                     order by d.intake_id), '[]'), count(*)
      into v_added, v_n
      from pipeline.course_intake_dates d where d.course_id = m.course_id and d.outcome = 'filled' and d.applied_at >= c.created_at;
    select coalesce(jsonb_agg(jsonb_build_object('intake_id', i.id, 'label', i.intake_label, 'year', i.intake_year, 'start_date', i.start_date,
                     'application_deadline', i.application_deadline, 'status', i.status) order by i.id), '[]')
      into v_after from catalogue.course_intakes i where i.id in (select (e->>'intake_id')::uuid from jsonb_array_elements(m.evidence) e);
    begin v_web := api.website_v2_course_item(m.course_id) -> 'intakes'; exception when others then v_web := jsonb_build_object('error', sqlerrm); end;
    begin v_zoho := public.zoho_edge_course_lookup_v1(m.course_id::text); exception when others then v_zoho := jsonb_build_object('error', sqlerrm); end;
    -- a filled value is published when the website returns an intake with the same start date (or the same year where no date was filled)
    select count(*) filter (where exists (select 1 from jsonb_array_elements(case when jsonb_typeof(v_web) = 'array' then v_web else '[]' end) w
                                           where (a->'after'->>'start_date' is not null and w->>'start_date' = a->'after'->>'start_date')
                                              or (a->'after'->>'start_date' is null and w->>'year' = a->'after'->>'year'))),
           count(*) filter (where not coalesce((a->>'as_planned')::boolean, false))
      into v_p, v_w from jsonb_array_elements(v_added) a;
    t_adm := t_adm + v_n; t_pub := t_pub + v_p; t_wrong := t_wrong + v_w;
    if v_zoho ? 'error' is false and v_zoho is not null then t_zoho := t_zoho + 1; end if;
    v_rows := v_rows || jsonb_build_array(jsonb_build_object('pick', m.pick, 'course_id', m.course_id, 'provider_id', m.provider_id, 'pattern', m.pattern, 'fills', m.fills,
      'at_selection', m.evidence, 'now', v_after, 'added', v_added, 'admitted', v_n, 'published', v_p, 'not_as_planned', v_w,
      'website_intakes', v_web, 'zoho_intakes', coalesce(v_zoho->'intakes', v_zoho->'course'->'intakes', case when v_zoho ? 'error' then v_zoho end, to_jsonb('no intake field'::text))));
  end loop;
  return jsonb_build_object('cohort_id', c.id, 'job', c.job, 'label', c.label, 'rule', c.selection_rule, 'picked_at', c.created_at, 'selection', c.selection,
    'totals', jsonb_build_object('selected', t_sel, 'eligible_values', t_elig, 'admitted', t_adm, 'published', t_pub, 'not_as_planned', t_wrong, 'zoho_checked', t_zoho,
      'skipped_or_failed', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select d.outcome || coalesce(': ' || d.reason, '') k, count(*) n
                            from pipeline.course_intake_dates d join pipeline.run_now_cohort_members mm on mm.course_id = d.course_id and mm.cohort_id = c.id
                           where d.outcome <> 'filled' and d.applied_at >= c.created_at group by 1) x),
      'vendor_calls', (select coalesce(sum((j.result->>'vendor_calls')::int), 0) from pipeline.admin_jobs j where j.kind = 'job_run_now' and j.args->>'cohort_id' = c.id::text)),
    'runs', (select coalesce(jsonb_agg(jsonb_build_object('run_id', j.id, 'state', j.state, 'reason', j.reason, 'started_at', j.started_at, 'finished_at', j.finished_at,
                     'processed', j.result->'processed', 'admitted', j.result->'admitted', 'skipped', j.result->'skipped', 'failed', j.result->'failed', 'refused', j.result->'refused')
                     order by j.created_at), '[]') from pipeline.admin_jobs j where j.kind = 'job_run_now' and j.args->>'cohort_id' = c.id::text),
    'courses', v_rows);
end $function$;
revoke all on function security.run_now_cohort_verify_v1(uuid) from public, anon, authenticated;
comment on function security.run_now_cohort_verify_v1(uuid) is 'CF-247 Run now (Platform Admin 4 Nov 2026 20:02 §6, 20:05 §4): per cohort course the evidence at selection, the values now, the rows filled since selection with their quotes, the Website API v2 read-back and Zoho where it answers; totals for the validation table. Writes nothing itself.';

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.run_now_cohorts', 'Layer 2', 'Admission', 'Run now: fixed cohorts and their selection record', 'active', '{}', '20261104610000'),
 ('table', 'pipeline.run_now_cohort_members', 'Layer 2', 'Admission', 'Run now: cohort courses and their evidence at selection', 'active', '{}', '20261104610000'),
 ('function', 'security.intake_dates_apply_v1(integer,uuid[])', 'Layer 2', 'Admission', 'Job intake-dates-apply with a bounded course selector', 'active', '{}', '20261104610000'),
 ('function', 'security.run_now_cohort_create_v1', 'Layer 2', 'Admission', 'Run now: cohort picked by the job''s own plan', 'active', '{}', '20261104610000'),
 ('function', 'security.job_run_now_v1', 'Layer 2', 'Admission', 'Run now: governed start of an allowlisted catalogued job on a cohort', 'active', '{}', '20261104610000'),
 ('function', 'public.admin_job_run_now_v1', 'Layer 2', 'Admission', 'Run now: signed-in entry', 'active', '{}', '20261104610000'),
 ('function', 'security.run_now_cohort_verify_v1', 'Layer 2', 'Admission', 'Run now: cohort verification (read only)', 'active', '{}', '20261104610000')
on conflict do nothing;

-- post-check: the scheduled job is unchanged, nothing switched on, the edit is the intended one
do $$
begin
  if md5(pg_get_functiondef('security.intake_dates_apply_v1(integer)'::regprocedure)) <> '90e2250d2bcfda720b00ad93cada20db' then
    raise exception 'run now post-check: intake_dates_apply_v1(integer) has an unexpected definition (md5 %)', md5(pg_get_functiondef('security.intake_dates_apply_v1(integer)'::regprocedure)); end if;
  if md5(pg_get_functiondef('security.intake_dates_apply_v1(integer,uuid[])'::regprocedure)) <> 'd47fbe685ae62287264a1909c988e9d6' then
    raise exception 'run now post-check: intake_dates_apply_v1(integer,uuid[]) has an unexpected definition (md5 %)', md5(pg_get_functiondef('security.intake_dates_apply_v1(integer,uuid[])'::regprocedure)); end if;
  if exists (select 1 from cron.job where command ~ 'run_now') then raise exception 'run now post-check: Run now is never scheduled'; end if;
  if (select command from cron.job where jobname = 'intake-dates-apply') is distinct from
     'select security.intake_dates_apply_v1(security.pipeline_num_v1(''batch.intake_dates_apply'', 200)::int)' then
    raise exception 'run now post-check: the job command changed'; end if;
end $$;
select 'run now: cohort, governed start and verification for intake-dates-apply; the scheduled job unchanged' ok;
