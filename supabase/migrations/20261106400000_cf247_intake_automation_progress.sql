-- CF-247 Intake Automation Progress (Platform Admin decision 5 Nov 2026 16:36 §3-§8, recorded verbatim in admin
-- docs/platform/2026-11-05-pr882-release-operator-accountability-1636.md; decision 19:14 §10, docs/platform/2026-11-05-centralise-development-claude-parallel-agents-1914.md;
-- process record docs/platform/processes/intake-dates.md). Agent D, branch cf247-intake-progress-ui. Compatibility record: docs/intake-automation-progress.md.
-- Why: the intake dates automation records every decision (pipeline.course_intake_date_events), its current state per intake row
--   (pipeline.course_intake_dates), its job runs (cron.job_run_details) and hourly measurements (pipeline.process_results), but the operator could not
--   see from the Admin UI whether the job is running, stalled or paused, what each run selected, validated, admitted and published, which
--   universities were never reached, what failed and what happens next. "Automation without operational visibility is not complete" (16:36 §0).
-- What (a read-only visibility layer over existing records; the intake scheduler and processing are untouched):
--   1 Reads (SECURITY DEFINER, Operations read rank 3 as public.admin_process_results_v1): public.admin_intake_progress_v1(view, args) with views
--     status (current state, controls the caller may use, alerts), window (latest run, 24 hours, 7 days or 30 days: the ten-step funnel, gross
--     activity and net data gain including withdrawals, one row per university: pilot universities and every other provider processed), runs,
--     failures (every failure or hold by class, with reason, course, evidence version, last attempt, next action, next revisit, integration issue,
--     automatic recovery and whether a person must act) and measurements (saved observer snapshots). All counts come from persisted records.
--     A university not selected in the window is "not_processed"; one selected and evaluated with no row reaching validation is "zero_eligible".
--   2 Observer (16:36 §5): security.intake_progress_record_v1() saves a dated snapshot as process intake-progress in pipeline.process_results and
--     routes zero-yield, monopolising, overdue, publication-mismatch and repeated-deterministic conditions to the existing integration queue through
--     security.integration_issue_upsert_v1 with stable fingerprints (intake-progress:<code>); a cleared condition sets condition_cleared_at. Expected
--     absence of evidence (deterministic absence classes) is recorded as correctly_excluded and raises nothing. It is one more call in the
--     existing job process-results (no new job, no new scheduler); the live command is checked before it is extended.
--   3 Pause/Resume (16:36 §4) uses the existing public.admin_automation_control(job, 'pause'|'resume') and its audit (pipeline.admin_control_events);
--     the status view only says whether the caller's role may use it (rank >= greatest(5, the job's control_rank), not retiring).
--   4 One index on pipeline.course_intake_date_events(run_at) so windows and the latest run are bounded reads (writes beside; processing unchanged).
-- Settings (G2, Settings › Pipeline settings › Process results): intake_progress.stall_minutes, .runs_listed, .failure_rows, .university_rows,
--   .zero_yield_runs, .monopoly_share_pct. The four history windows are the ones named by decision 16:36 §3D (marked fixed).
-- Consumer API: unchanged (G3); search.course_documents is not read here (the publication state written by security.intake_publication_check_v1 is).
-- Replaces: nothing (adds a read layer and one observer call to job process-results)
-- Retires: nothing
-- Nothing is dropped or deleted.

-- 0 guards: the live definitions this change calls (md5 read from production 5 Nov 2026 19:18 AEDT) and the live process-results command -------
do $g$
declare x text[]; v text;
begin
  foreach x slice 1 in array array[
      ['security.intake_ui_scopes_v1()', '94bae55f4ecfeca5957f17a0327ba660'],
      ['security.integration_issue_upsert_v1(jsonb,text)', 'f9d7bf1a6dbe94ba97c34f10817f56c1'],
      ['security.admin_automation_control_v1(text,text,jsonb)', '431aff603f21b8c8a030073b07a08259'],
      ['public.admin_automation_control(text,text,jsonb)', 'b032f84e705b926ce7026f209116111a'],
      ['security.pipeline_num_v1(text,numeric)', '09f9b1551daf42b4a0c9795e6f30c6d4'],
      ['security.current_role_rank()', 'd709d92dbd7a648ccf78e594d68ca980']] loop
    if md5(pg_get_functiondef(x[1]::regprocedure)) <> x[2] then
      raise exception 'live % differs from the definition this change relies on (md5 %, expected %)', x[1], md5(pg_get_functiondef(x[1]::regprocedure)), x[2];
    end if;
  end loop;
  select command into v from cron.job where jobname = 'process-results';
  if v is distinct from 'select security.intake_publication_check_v1(); select security.process_results_record_v1(); select security.process_results_recovery_record_v1()'
     and v is distinct from 'select security.intake_publication_check_v1(); select security.process_results_record_v1(); select security.process_results_recovery_record_v1(); select security.intake_progress_record_v1()' then
    raise exception 'live process-results command differs from the one this change extends: %', v;
  end if;
end $g$;

-- 1 settings (G2) ------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'intake_progress.stall_minutes', 'Automation progress: a job is overdue after',
  'Process results › Automation progress shows the intake job as stalled, and the observer raises an integration issue, when the job is on and its last run started longer ago than this.',
  'number', to_jsonb(90), 30, 1440, 'minutes', 1020, 'Process results', 'security.intake_progress_status_v1; job process-results', 'Platform Admin decision 5 Nov 2026 16:36 §3A, §6: distinguish a healthy idle job from a stalled one'),
 ('pipeline', 'intake_progress.runs_listed', 'Automation progress: runs listed',
  'Most runs listed in the selected history window on Process results › Automation progress (newest first).',
  'number', to_jsonb(24), 5, 200, 'runs', 1021, 'Process results', 'public.admin_intake_progress_v1', 'Decision 16:36 §3D: bounded history'),
 ('pipeline', 'intake_progress.failure_rows', 'Automation progress: failures listed',
  'Most failed or held intake rows listed at once on Process results › Automation progress (newest first; filter by class or university for more).',
  'number', to_jsonb(50), 10, 500, 'rows', 1022, 'Process results', 'public.admin_intake_progress_v1; security.intake_progress_failures_v1', 'Decision 16:36 §3E: bounded failure list'),
 ('pipeline', 'intake_progress.university_rows', 'Automation progress: providers listed',
  'Most providers in the university table: every pilot university first, then the other providers processed in the window, most rows first.',
  'number', to_jsonb(60), 10, 500, 'providers', 1023, 'Process results', 'security.intake_progress_universities_v1', 'Decision 16:36 §3C: bounded university table'),
 ('pipeline', 'intake_progress.zero_yield_runs', 'Automation progress: zero-yield after this many runs',
  'The observer records a zero-yield condition (integration queue, fingerprint intake-progress:zero-yield) when this many scheduled intake runs in a row admitted nothing although rows reached validation or failed for a platform reason.',
  'number', to_jsonb(3), 1, 24, 'runs', 1024, 'Process results', 'security.intake_progress_alerts_v1; job process-results', 'Decision 16:36 §5, §6: repeated zero-yield runs'),
 ('pipeline', 'intake_progress.monopoly_share_pct', 'Automation progress: one provider monopolising',
  'Over the same recent scheduled runs, one provider taking at least this share of the rows while a pilot university still has pending work is raised as monopolising.',
  'number', to_jsonb(80), 50, 100, 'per cent', 1025, 'Process results', 'security.intake_progress_alerts_v1; job process-results', 'Decision 16:36 §6: one university monopolising processing')
on conflict (toolset_key, key) do nothing;

-- 2 a bounded read of runs and windows (writes beside the intake tables; nothing in processing reads it) -----------------------------------------
create index if not exists course_intake_date_events_run_idx on pipeline.course_intake_date_events(run_at desc);

-- 3 reads ---------------------------------------------------------------------------------------------------------------------------------------
create or replace function security.intake_progress_window_v1(p_since timestamptz, p_until timestamptz) returns jsonb
language sql stable security definer set search_path to '' as $function$
  -- 16:36 §3B: the ten-step funnel from persisted decisions; selected = admitted + nothing new + refused or held (reconciles row for row)
  with e as (select e.* from pipeline.course_intake_date_events e where e.run_at >= p_since and e.run_at <= p_until)
  select jsonb_build_object('since', p_since, 'until', p_until,
    'runs', count(distinct e.run_at) filter (where e.outcome <> 'withdrawn'),
    'scheduled_runs', count(distinct e.run_at) filter (where e.outcome <> 'withdrawn' and not e.bounded),
    'run_now_runs', count(distinct e.run_at) filter (where e.outcome <> 'withdrawn' and e.bounded),
    'withdrawal_actions', count(distinct e.run_at) filter (where e.outcome = 'withdrawn'),
    'selected', count(*) filter (where e.outcome <> 'withdrawn'),
    'selected_courses', count(distinct e.course_id) filter (where e.outcome <> 'withdrawn'),
    'examined', count(*) filter (where e.outcome <> 'withdrawn' and (e.reason is not null or e.outcome in ('filled', 'nothing_new'))),
    'evidence_found', count(*) filter (where e.outcome <> 'withdrawn' and e.page_quote is not null),
    'dates_extracted', count(*) filter (where e.outcome <> 'withdrawn' and (e.start_quote is not null or e.deadline_quote is not null or e.outcome = 'filled')),
    'dates_validated', count(*) filter (where e.outcome = 'filled' or e.failure_class = 'admission_held'),
    'admitted', count(*) filter (where e.outcome = 'filled'),
    'published', count(*) filter (where e.outcome = 'filled' and e.publication_state = 'published'),
    'publication_failed', count(*) filter (where e.outcome = 'filled' and e.publication_state = 'consumer_publication_failed'),
    'provider_not_published', count(*) filter (where e.outcome = 'filled' and e.publication_state in ('provider_not_published', 'course_not_in_consumer_source')),
    'publication_not_checked', count(*) filter (where e.outcome = 'filled' and e.publication_state is null),
    'nothing_new', count(*) filter (where e.outcome = 'nothing_new'),
    'refused_or_held', count(*) filter (where e.outcome = 'skipped'),
    'awaiting_revisit', count(*) filter (where e.outcome = 'skipped' and e.next_revisit_at is not null),
    'waiting_for_change', count(*) filter (where e.outcome = 'skipped' and e.deterministic),
    'withdrawn', count(*) filter (where e.outcome = 'withdrawn'),
    'net_gain', count(*) filter (where e.outcome = 'filled') - count(*) filter (where e.outcome = 'withdrawn'),
    'classes', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select coalesce(x.failure_class, 'not_classified_yet') k, count(*) n from e x
                 where x.outcome = 'skipped' group by 1) c))
  from e
$function$;
comment on function security.intake_progress_window_v1(timestamptz, timestamptz) is 'CF-247 Automation Progress (decision 5 Nov 2026 16:36 §3B, §3D): the intake funnel over a window of persisted decisions (pipeline.course_intake_date_events): selected, examined, evidence found, dates extracted, validated, admitted, published, refused or held, awaiting revisit, withdrawn and net gain. Read only.';

create or replace function security.intake_progress_universities_v1(p_since timestamptz, p_until timestamptz) returns jsonb
language sql stable security definer set search_path to '' as $function$
  -- 16:36 §3C: one row per university; a university not selected in the window is not_processed, one selected with no row reaching validation is zero_eligible
  with sc as (select (x.e->>'id')::uuid id, x.e->>'name' name, x.ord from jsonb_array_elements(security.intake_ui_scopes_v1()) with ordinality x(e, ord)),
  m as (select (u->>'provider_id')::uuid id, (u->>'never_examined')::int never_examined
          from (select r.summary from pipeline.process_results r where r.process_key = 'intake-dates' order by r.measured_at desc limit 1) s,
               jsonb_array_elements(coalesce(s.summary->'universities', '[]'::jsonb)) u),
  w as (select e.provider_id, count(*) filter (where e.outcome <> 'withdrawn') sel, count(distinct e.course_id) filter (where e.outcome <> 'withdrawn') courses,
               count(*) filter (where e.outcome = 'filled' or e.failure_class = 'admission_held') validated, count(*) filter (where e.outcome = 'filled') admitted,
               count(*) filter (where e.outcome = 'filled' and e.publication_state = 'published') published, count(*) filter (where e.outcome = 'skipped') held,
               count(*) filter (where e.outcome = 'withdrawn') withdrawn, count(distinct e.run_at) filter (where e.outcome <> 'withdrawn') runs
          from pipeline.course_intake_date_events e where e.run_at >= p_since and e.run_at <= p_until group by e.provider_id),
  ids as (select sc.id, true pilot, sc.ord, 0::bigint sel from sc
          union all select w.provider_id, false, null, w.sel from w where w.provider_id not in (select id from sc)),
  pick as (select * from ids order by pilot desc, ord, sel desc, id limit security.pipeline_num_v1('intake_progress.university_rows', 60)::int)
  select coalesce(jsonb_agg(x order by (x->>'pilot')::boolean desc, (x->>'ord')::int nulls last, (x->>'selected')::int desc, x->>'university'), '[]'::jsonb) from (
    select jsonb_build_object('provider_id', pick.id, 'pilot', pick.pilot, 'ord', pick.ord,
      'university', coalesce((select sc.name from sc where sc.id = pick.id), (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = pick.id)),
      'state', case when coalesce(w.sel, 0) = 0 then 'not_processed' when w.validated = 0 then 'zero_eligible' when w.admitted > 0 then 'admitted' else 'eligible_not_admitted' end,
      'selected', coalesce(w.sel, 0), 'courses', coalesce(w.courses, 0), 'runs', coalesce(w.runs, 0), 'eligible', coalesce(w.validated, 0),
      'admitted', coalesce(w.admitted, 0), 'published', coalesce(w.published, 0), 'held', coalesce(w.held, 0), 'withdrawn', coalesce(w.withdrawn, 0),
      'never_examined', m.never_examined,
      'revisit_due', (select count(*) from pipeline.course_intake_dates d where d.provider_id = pick.id and d.next_revisit_at <= now()),
      'pending', case when m.never_examined is not null then m.never_examined + (select count(*) from pipeline.course_intake_dates d where d.provider_id = pick.id and d.next_revisit_at <= now()) end,
      'held_now', (select count(*) from pipeline.course_intake_dates d where d.provider_id = pick.id and d.outcome = 'skipped'),
      'last_run', (select max(e.run_at) from pipeline.course_intake_date_events e where e.provider_id = pick.id and e.outcome <> 'withdrawn'),
      'next_revisit', (select min(d.next_revisit_at) from pipeline.course_intake_dates d where d.provider_id = pick.id and d.next_revisit_at > now())) x
    from pick left join w on w.provider_id = pick.id left join m on m.id = pick.id) y
$function$;
comment on function security.intake_progress_universities_v1(timestamptz, timestamptz) is 'CF-247 Automation Progress (decision 16:36 §3C): one row per pilot university (security.intake_ui_scopes_v1) and per other provider processed in the window: state (not_processed: not selected in the window; zero_eligible: selected and evaluated, no row reached validation), selected, eligible (validated), admitted, published, held, withdrawn, pending (never examined at the latest measurement plus revisits due), last run and next revisit. Read only.';

create or replace function security.intake_progress_runs_v1(p_since timestamptz, p_until timestamptz, p_limit int) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
declare v_job bigint := (select j.jobid from cron.job j where j.jobname = 'intake-dates-apply'); v_cron jsonb;
begin
  -- the job's recent runs, newest first by run id (bounded: the primary key is read backwards)
  select coalesce(jsonb_agg(jsonb_build_object('runid', d.runid, 'status', d.status, 'start', d.start_time, 'end', d.end_time) order by d.runid desc), '[]'::jsonb) into v_cron
    from (select d.* from cron.job_run_details d where d.jobid = v_job order by d.runid desc limit p_limit * 2) d;
  return (with r as (select distinct e.run_at from pipeline.course_intake_date_events e where e.run_at >= p_since and e.run_at <= p_until order by e.run_at desc limit p_limit)
    select coalesce(jsonb_agg(x order by x->>'run_at' desc), '[]'::jsonb) from (
      select jsonb_build_object('run_at', r.run_at,
        'kind', case when bool_and(e.outcome = 'withdrawn') then 'withdrawal' when bool_or(e.bounded) then 'run_now' else 'scheduled' end,
        'cron_run', case when not bool_or(e.bounded) and not bool_and(e.outcome = 'withdrawn') then
                      (select c from jsonb_array_elements(v_cron) c where (c->>'start')::timestamptz <= r.run_at order by (c->>'start')::timestamptz desc limit 1) end,
        'selected', count(*) filter (where e.outcome <> 'withdrawn'), 'courses', count(distinct e.course_id), 'providers', count(distinct e.provider_id),
        'evidence_found', count(*) filter (where e.outcome <> 'withdrawn' and e.page_quote is not null),
        'validated', count(*) filter (where e.outcome = 'filled' or e.failure_class = 'admission_held'), 'admitted', count(*) filter (where e.outcome = 'filled'),
        'published', count(*) filter (where e.outcome = 'filled' and e.publication_state = 'published'), 'held', count(*) filter (where e.outcome = 'skipped'),
        'withdrawn', count(*) filter (where e.outcome = 'withdrawn'),
        'by_provider', (select coalesce(jsonb_agg(jsonb_build_object('provider_id', b.provider_id, 'university', b.name, 'rows', b.n, 'admitted', b.a) order by b.n desc), '[]'::jsonb)
                          from (select e2.provider_id, coalesce(p.display_name, p.canonical_name) name, count(*) n, count(*) filter (where e2.outcome = 'filled') a
                                  from pipeline.course_intake_date_events e2 left join catalogue.providers p on p.id = e2.provider_id
                                 where e2.run_at = r.run_at group by 1, 2) b)) x
        from r join pipeline.course_intake_date_events e on e.run_at = r.run_at group by r.run_at) z);
end $function$;
comment on function security.intake_progress_runs_v1(timestamptz, timestamptz, integer) is 'CF-247 Automation Progress (decision 16:36 §3B, §3D): each intake run in the window (one run = one decision time in pipeline.course_intake_date_events): kind (scheduled, governed Run Now, withdrawal), the matching intake-dates-apply cron run id and status, its funnel and its rows by provider. Read only.';

create or replace function security.intake_progress_failures_v1(p_class text, p_provider uuid, p_limit int) returns jsonb
language sql stable security definer set search_path to '' as $function$
  -- 16:36 §3E: every failure or hold, from the current state of each intake row (pipeline.course_intake_dates)
  with f as (select d.*, coalesce(d.failure_class, case when d.publication_state = 'consumer_publication_failed' then 'consumer_publication_failed' else 'not_classified_yet' end) cls,
                    (d.failure_class in ('course_level_exception', 'admission_held', 'wrong_institution_or_campus', 'no_valid_calendar_source')
                     or d.next_action in ('human_decision_required', 'calendar_needs_correction')) person
               from pipeline.course_intake_dates d
              where (d.outcome <> 'filled' or d.failure_class is not null or d.publication_state = 'consumer_publication_failed'))
  select jsonb_build_object(
    'classes', (select coalesce(jsonb_agg(jsonb_build_object('class', c.cls, 'rows', c.n, 'universities', c.u, 'person_required', c.p, 'deterministic', c.det) order by c.n desc), '[]'::jsonb)
                  from (select f.cls, count(*) n, count(distinct f.provider_id) u, count(*) filter (where f.person) p, bool_and(coalesce(f.deterministic, false)) det from f group by f.cls) c),
    'total', (select count(*) from f),
    'shown_limit', p_limit,
    'rows', (select coalesce(jsonb_agg(x order by x->>'last_attempt' desc), '[]'::jsonb) from (
       select jsonb_build_object('intake_id', f.intake_id, 'course_id', f.course_id, 'provider_id', f.provider_id,
         'university', (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = f.provider_id),
         'course_title', (select coalesce(c.display_title, c.canonical_title) from catalogue.courses c where c.id = f.course_id),
         'course_url', (select c.course_url from catalogue.courses c where c.id = f.course_id),
         'intake', (select i.intake_label || coalesce(' ' || i.intake_year, '') from catalogue.course_intakes i where i.id = f.intake_id),
         'class', f.cls, 'outcome', f.outcome, 'next_action', f.next_action,
         'reason', coalesce(f.reason, case when f.publication_state = 'consumer_publication_failed' then 'admitted, but the value is not in the Website API v2 source (publication check)'
                                           when f.failure_class = 'missing_application_deadline_evidence' then 'admitted without an application deadline: no closing date is printed for it'
                                           else 'no reason recorded' end),
         'evidence_version', jsonb_build_object('calendar_set', f.calendar_set, 'evidence_year', f.evidence_year, 'reader', f.reader, 'rule', f.rule,
                                                'inputs', left(f.inputs_fp, 12), 'calendar_url', f.calendar_url, 'calendar_evidence_id', f.calendar_evidence_id),
         'last_attempt', f.applied_at, 'next_revisit_at', f.next_revisit_at, 'revisit_trigger', f.revisit_trigger, 'related_case', f.related_case,
         'publication_state', f.publication_state,
         'issue', (select jsonb_build_object('ref', i.issue_ref, 'status', i.status, 'severity', i.severity) from pipeline.integration_issues i
                    where i.status <> 'closed' and (f.course_id = any (i.course_ids) or (f.related_case is not null and i.correlation_key = f.related_case))
                    order by i.severity, i.id limit 1),
         'automatic', case when f.publication_state = 'consumer_publication_failed' then 'checked again by the next publication check'
                           when f.deterministic then 'looked at again when its input changes: ' || coalesce(f.revisit_trigger, 'a change of calendar, reader, page or settings')
                           when f.next_revisit_at is not null then 'looked at again on its revisit date'
                           else 'not scheduled' end,
         'auto_recover', coalesce(f.publication_state = 'consumer_publication_failed' or f.deterministic or f.next_revisit_at is not null, false),
         'person_required', f.person) x
       from f where (p_class is null or f.cls = p_class) and (p_provider is null or f.provider_id = p_provider)
       order by f.applied_at desc limit p_limit) y))
$function$;
comment on function security.intake_progress_failures_v1(text, uuid, integer) is 'CF-247 Automation Progress (decision 16:36 §3E): every failed or held intake row by class (with universities and how many need a person), and the newest rows with category, exact reason, university and course, evidence version, last attempt, next action, next revisit or trigger, open integration issue, whether the platform recovers automatically and whether a person must act. Read only.';

create or replace function security.intake_progress_status_v1(p_rank int) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
declare j record; c record; v_last record; v_ok timestamptz; v_obs record; v_state text; v_next timestamptz; v_m int; v_latest timestamptz; v_run jsonb; v_day jsonb;
        v_stall int := security.pipeline_num_v1('intake_progress.stall_minutes', 90)::int; v_meas jsonb; v_rec jsonb; v_meas_at timestamptz; v_on boolean; v_retiring boolean;
begin
  select * into j from cron.job x where x.jobname = 'intake-dates-apply';
  select * into c from pipeline.automation_catalogue x where x.jobname = 'intake-dates-apply';
  select d.runid, d.status, d.start_time, d.end_time, left(d.return_message, 300) message into v_last from cron.job_run_details d where d.jobid = j.jobid order by d.runid desc limit 1;
  select d.start_time into v_ok from cron.job_run_details d where d.jobid = j.jobid and d.status = 'succeeded' order by d.runid desc limit 1;
  select d.runid, d.status, d.start_time into v_obs from cron.job_run_details d where d.jobid = (select x.jobid from cron.job x where x.jobname = 'process-results') order by d.runid desc limit 1;
  v_on := coalesce((security.toolset_setting('pipeline', 'intake_dates.apply_enabled') #>> '{}')::boolean, false);
  v_retiring := exists (select 1 from pipeline.component_register r where r.kind = 'job' and r.name = 'intake-dates-apply' and r.status in ('retiring', 'retired'));
  v_state := case when j.jobid is null then 'missing' when not j.active then 'paused' when not v_on then 'switched_off'
                  when v_last.status in ('running', 'starting') then 'running' when v_last.status = 'failed' then 'failed'
                  when v_last.start_time is null or v_last.start_time < now() - make_interval(mins => v_stall) then 'stalled' else 'waiting' end;
  if j.schedule ~ '^\d{1,2} \* \* \* \*$' then  -- an hourly schedule: the next minute past the hour
    v_m := split_part(j.schedule, ' ', 1)::int;
    v_next := date_trunc('hour', now()) + make_interval(mins => v_m);
    if v_next <= now() then v_next := v_next + make_interval(hours => 1); end if;  -- fixed: cron hour arithmetic
  end if;
  select max(e.run_at) into v_latest from pipeline.course_intake_date_events e where e.outcome <> 'withdrawn';
  v_run := case when v_latest is not null then security.intake_progress_window_v1(v_latest, v_latest) end;
  v_day := security.intake_progress_window_v1(now() - make_interval(days => 1), now());  -- fixed: the 24-hour rate named by decision 16:36 §3A
  select r.summary, r.measured_at into v_meas, v_meas_at from pipeline.process_results r where r.process_key = 'intake-dates' order by r.measured_at desc limit 1;
  select r.summary into v_rec from pipeline.process_results r where r.process_key = 'intake-recovery' order by r.measured_at desc limit 1;
  return jsonb_build_object(
    'as_at', now(), 'job', 'intake-dates-apply', 'label', coalesce(c.label, 'Intake dates apply'), 'state', v_state, 'schedule', j.schedule, 'active', j.active, 'apply_enabled', v_on,
    'last_run', case when v_last.runid is not null then jsonb_build_object('runid', v_last.runid, 'status', v_last.status, 'started_at', v_last.start_time, 'finished_at', v_last.end_time,
                       'message', case when v_last.status <> 'succeeded' then v_last.message end) end,
    'running_run', case when v_state = 'running' then v_last.runid end,
    'last_success', v_ok, 'next_run', v_next, 'stall_minutes', v_stall,
    'current_university', case when v_state = 'running' then 'not recorded until the run commits (a run is one transaction)' end,
    'batch', security.pipeline_num_v1('batch.intake_dates_apply', 200), 'provider_share', security.pipeline_num_v1('intake_dates.provider_share', 25),
    'pilot_share_pct', security.pipeline_num_v1('intake_dates.pilot_batch_share', 60),
    'scope', (select coalesce(jsonb_agg(e->>'name' order by o), '[]'::jsonb) from jsonb_array_elements(security.intake_ui_scopes_v1()) with ordinality s(e, o)),
    'latest_run', v_run, 'latest_run_admitted_nothing', coalesce((v_run->>'admitted')::int = 0, false),
    'rate_per_hour_24h', round(coalesce((v_day->>'selected')::numeric, 0) / 24, 1),  -- fixed: per hour over the 24-hour window
    'last_24h', v_day,
    'pending', jsonb_build_object('never_examined', (v_meas->'totals'->>'never_examined')::int, 'measured_at', v_meas_at,
       'revisit_due', (select count(*) from pipeline.course_intake_dates d where d.next_revisit_at <= now())),
    'held', (select jsonb_build_object('held', count(*), 'timed_revisit', count(*) filter (where d.next_revisit_at is not null),
                                       'waiting_for_change', count(*) filter (where d.deterministic),
                                       'person_required', count(*) filter (where d.failure_class in ('course_level_exception', 'admission_held', 'wrong_institution_or_campus', 'no_valid_calendar_source')
                                                                          or d.next_action in ('human_decision_required', 'calendar_needs_correction')))
               from pipeline.course_intake_dates d where d.outcome = 'skipped'),
    'usage', jsonb_build_object('ai_cost_usd', (select sum((u->>'ai_cost_usd_7_days')::numeric) from jsonb_array_elements(coalesce(v_meas->'universities', '[]'::jsonb)) u),
       'ai_window_days', security.pipeline_num_v1('process_results.window_days', 7), 'firecrawl_credits_used', (v_rec->'refresh'->>'credits_used')::numeric,
       'firecrawl_credits_counted', (v_rec->'refresh'->>'credits_counted')::numeric, 'firecrawl_budget', (v_rec->'refresh'->>'budget')::numeric),
    'observer', jsonb_build_object('job', 'process-results', 'last_run', v_obs.start_time, 'status', v_obs.status,
       'last_snapshot', (select max(r.measured_at) from pipeline.process_results r where r.process_key = 'intake-progress')),
    'controls', jsonb_build_object('job', 'intake-dates-apply', 'control_rank', greatest(5, coalesce(c.control_rank, 6)), 'retiring', v_retiring,
       'can_pause_resume', j.jobid is not null and p_rank >= greatest(5, coalesce(c.control_rank, 6)) and (not v_retiring or j.active),
       'can_run_now', p_rank >= 4, 'can_measure', p_rank >= 4));
end $function$;
comment on function security.intake_progress_status_v1(integer) is 'CF-247 Automation Progress (decision 16:36 §3A, §4): the intake-dates-apply job now: enabled, paused, switched off, running, waiting, failed or stalled (last start older than intake_progress.stall_minutes), last and running run id, last success, next run, batch, provider and pilot shares, scope, latest run funnel (and whether it admitted nothing), rate, pending work, held work, AI and Firecrawl use from the saved measurements, the observer, and which existing controls the caller''s role may use. Read only.';

create or replace function security.intake_progress_alerts_v1(p_status jsonb) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
declare v_n int := security.pipeline_num_v1('intake_progress.zero_yield_runs', 3)::int; v_pct numeric := security.pipeline_num_v1('intake_progress.monopoly_share_pct', 80);
        v_runs timestamptz[]; v_agg record; v_top record; v_pending_other int; v_pub int; v_rep int; v_out jsonb := '[]'::jsonb; v_last_ok timestamptz; v_cal jsonb;
begin
  -- the last N scheduled runs (not governed Run Now, not withdrawals)
  select coalesce(array_agg(run_at order by run_at desc), '{}') into v_runs from (
    select distinct e.run_at from pipeline.course_intake_date_events e where not e.bounded and e.outcome <> 'withdrawn' order by e.run_at desc limit v_n) r;
  select count(*) filter (where e.outcome = 'filled') admitted, count(*) rows_, count(*) filter (where e.failure_class = 'admission_held') validated_held,
         count(*) filter (where e.outcome = 'skipped' and (e.failure_class is null or e.failure_class in ('calendar_interpretation_failed', 'consumer_publication_failed'))) defect,
         count(distinct e.provider_id) providers
    into v_agg
    from pipeline.course_intake_date_events e
   where e.run_at = any (v_runs) and e.outcome <> 'withdrawn';
  select max(e.run_at) into v_last_ok from pipeline.course_intake_date_events e where e.outcome = 'filled';
  -- zero yield (16:36 §5): N scheduled runs in a row admitted nothing although rows reached validation or failed for a platform reason;
  -- expected absence of evidence (deterministic absence classes only) is correctly_excluded and raises nothing
  v_out := v_out || jsonb_build_object('code', 'zero_yield', 'label', 'Repeated zero-yield runs', 'routed', true,
    'tripped', cardinality(v_runs) >= v_n and coalesce(v_agg.admitted, 0) = 0 and coalesce(v_agg.rows_, 0) > 0 and (coalesce(v_agg.validated_held, 0) + coalesce(v_agg.defect, 0)) > 0,
    'zero_reason', case when cardinality(v_runs) = 0 then 'no_eligible_work' when coalesce(v_agg.admitted, 0) > 0 then null
                        when (coalesce(v_agg.validated_held, 0) + coalesce(v_agg.defect, 0)) > 0 then 'technical_failure' else 'correctly_excluded' end,
    'affected', coalesce(v_agg.rows_, 0),
    'evidence', jsonb_build_object('runs', to_jsonb(v_runs), 'rows', coalesce(v_agg.rows_, 0), 'validated_but_held', coalesce(v_agg.validated_held, 0),
                                   'platform_failures', coalesce(v_agg.defect, 0), 'providers', coalesce(v_agg.providers, 0)),
    'last_success_stage', case when v_last_ok is not null then 'last value admitted ' || to_char(v_last_ok at time zone 'Australia/Sydney', 'DD Mon HH24:MI') else 'no value admitted yet' end,
    'next_action', 'Open the failure list: rows held by a lock need the lock reviewed; reader or publication failures go to the integration queue owner.');
  -- one provider monopolising (16:36 §6)
  select e.provider_id, count(*) n, (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = e.provider_id) name into v_top
    from pipeline.course_intake_date_events e where e.run_at = any (v_runs) and e.outcome <> 'withdrawn' group by e.provider_id order by count(*) desc limit 1;
  select count(*) into v_pending_other from jsonb_array_elements(security.intake_ui_scopes_v1()) s
   where (s->>'id')::uuid is distinct from v_top.provider_id
     and exists (select 1 from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id
                  where c.provider_id = (s->>'id')::uuid and i.status = 'active' and c.lifecycle_status = 'active'
                    and (i.intake_year is null or i.start_date is null or i.application_deadline is null)
                    and not exists (select 1 from pipeline.course_intake_dates d where d.intake_id = i.id));
  v_out := v_out || jsonb_build_object('code', 'monopoly', 'label', 'One university monopolising processing', 'routed', true,
    'tripped', coalesce(v_agg.rows_, 0) > 0 and v_top.n * 100.0 / v_agg.rows_ >= v_pct and v_pending_other > 0 and cardinality(v_runs) >= v_n,
    'affected', coalesce(v_top.n, 0),
    'evidence', jsonb_build_object('provider_id', v_top.provider_id, 'university', v_top.name, 'share_pct', case when coalesce(v_agg.rows_, 0) > 0 then round(v_top.n * 100.0 / v_agg.rows_, 1) end,
                                   'pilot_universities_waiting', v_pending_other, 'runs', to_jsonb(v_runs)),
    'last_success_stage', 'selection (the intake plan)', 'next_action', 'Check the provider and pilot shares (Settings › Pipeline settings › Intake dates); the scheduler itself is not changed here.');
  -- the job overdue, stalled or failed (16:36 §6)
  v_out := v_out || jsonb_build_object('code', 'job_overdue', 'label', 'Intake job overdue, stalled or failed', 'routed', true,
    'tripped', p_status->>'state' in ('stalled', 'failed'), 'affected', case when p_status->>'state' in ('stalled', 'failed') then 1 else 0 end,
    'evidence', jsonb_build_object('state', p_status->>'state', 'last_run', p_status->'last_run', 'stall_minutes', p_status->'stall_minutes'),
    'last_success_stage', coalesce('last successful run ' || to_char((p_status->>'last_success')::timestamptz at time zone 'Australia/Sydney', 'DD Mon HH24:MI'), 'no successful run recorded'),
    'next_action', 'Open Scheduled jobs › Automations › Intake dates apply: read the last run message; resume only through the existing control.');
  -- publication mismatch (16:36 §6)
  select count(*) into v_pub from pipeline.course_intake_dates d where d.publication_state = 'consumer_publication_failed';
  v_out := v_out || jsonb_build_object('code', 'publication_mismatch', 'label', 'Admitted values not in the Website API source', 'routed', true, 'tripped', v_pub > 0, 'affected', v_pub,
    'evidence', jsonb_build_object('rows', v_pub, 'retries', security.pipeline_num_v1('retry.intake_publication_checks', 3)),
    'last_success_stage', 'admission', 'next_action', 'The publication check retries; if it stays, verify the course in Website API v2 and route it to the integration queue owner.');
  -- repeated deterministic failures in the last day (an unchanged deterministic failure must never be repeated, mandate 12:44 §9)
  select count(distinct e.intake_id) into v_rep from pipeline.course_intake_date_events e
   where e.run_at >= now() - make_interval(days => 1) and e.deterministic and e.outcome = 'skipped'  -- fixed: the one-day check named by decision 16:36 §6
     and exists (select 1 from pipeline.course_intake_date_events p where p.intake_id = e.intake_id and p.run_at < e.run_at and p.failure_class = e.failure_class
                   and p.calendar_set is not distinct from e.calendar_set and p.reader is not distinct from e.reader);
  v_out := v_out || jsonb_build_object('code', 'repeated_deterministic', 'label', 'Deterministic failures repeated without a change', 'routed', true, 'tripped', v_rep > 0, 'affected', v_rep,
    'evidence', jsonb_build_object('intake_rows', v_rep), 'last_success_stage', 'classification',
    'next_action', 'An unchanged deterministic failure should wait for its input to change: report the rows to the intake owner (P0 rule).');
  -- shown only (routed by their existing mechanisms)
  v_out := v_out || jsonb_build_object('code', 'stale_calendar', 'label', 'Calendar editions stale', 'routed', false,
    'affected', (select count(*) from pipeline.course_intake_dates d where d.failure_class = 'stale_calendar_edition'),
    'tripped', exists (select 1 from pipeline.course_intake_dates d where d.failure_class = 'stale_calendar_edition'),
    'evidence', jsonb_build_object('class', 'stale_calendar_edition'), 'last_success_stage', 'calendar reading',
    'next_action', 'Calendar refresh (job calendar-reread) asks for newer editions within its credit budget; universities without a usable calendar are flagged by process-results.');
  v_out := v_out || jsonb_build_object('code', 'human_decisions', 'label', 'Pending human decisions', 'routed', false,
    'affected', coalesce((p_status->'held'->>'person_required')::int, 0), 'tripped', coalesce((p_status->'held'->>'person_required')::int, 0) > 0,
    'evidence', jsonb_build_object('rows', p_status->'held'->'person_required'), 'last_success_stage', 'classification',
    'next_action', 'Review blockers: Layer 4 Review and the integration queue.');
  v_out := v_out || jsonb_build_object('code', 'budget', 'label', 'Firecrawl budget for calendar refresh reached', 'routed', false,
    'tripped', coalesce((p_status->'usage'->>'firecrawl_credits_counted')::numeric >= (p_status->'usage'->>'firecrawl_budget')::numeric, false),
    'affected', coalesce((p_status->'usage'->>'firecrawl_credits_counted')::numeric, 0),
    'evidence', jsonb_build_object('counted', p_status->'usage'->'firecrawl_credits_counted', 'budget', p_status->'usage'->'firecrawl_budget'),
    'last_success_stage', 'calendar refresh', 'next_action', 'A Platform Admin decides whether to raise central.calendar_refresh_credit_budget.');
  select jsonb_agg(jsonb_build_object('university', a->>'university', 'before', (b->>'calendars_valid')::int, 'now', (a->>'calendars_valid')::int)) into v_cal
    from (select r.summary from pipeline.process_results r where r.process_key = 'intake-dates' order by r.measured_at desc limit 1) n, jsonb_array_elements(n.summary->'universities') a,
         (select r.summary from pipeline.process_results r where r.process_key = 'intake-dates' order by r.measured_at desc offset 1 limit 1) o, jsonb_array_elements(o.summary->'universities') b
   where a->>'provider_id' = b->>'provider_id' and (a->>'calendars_valid') is distinct from (b->>'calendars_valid');
  v_out := v_out || jsonb_build_object('code', 'source_coverage', 'label', 'Valid calendars changed since the previous measurement', 'routed', false,
    'tripped', v_cal is not null, 'affected', coalesce(jsonb_array_length(v_cal), 0), 'evidence', coalesce(v_cal, '[]'::jsonb), 'last_success_stage', 'measurement',
    'next_action', 'Open the university in Process results to see which calendar was added or set aside.');
  return v_out;
end $function$;
comment on function security.intake_progress_alerts_v1(jsonb) is 'CF-247 Automation Progress (decision 16:36 §5, §6): the intake alert conditions, each with affected count, evidence, last successful stage and next action: zero yield, monopolising, job overdue or failed, publication mismatch, repeated deterministic failures (routed to the integration queue by the observer), and stale calendars, pending human decisions, refresh budget and calendar coverage change (shown; routed by their existing mechanisms). Read only.';

-- 4 observer: one more call in the existing process-results job -----------------------------------------------------------------------------
create or replace function security.intake_progress_record_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_status jsonb := security.intake_progress_status_v1(0); v_alerts jsonb; v_id bigint; a jsonb; v_iss jsonb; v_out jsonb := '{}'::jsonb; v_fp text; v_summary jsonb;
begin
  v_alerts := security.intake_progress_alerts_v1(v_status);
  v_summary := jsonb_build_object('process', 'intake-progress', 'measured_at', now(), 'status', v_status - 'controls', 'alerts', v_alerts,
    'universities_24h', security.intake_progress_universities_v1(now() - make_interval(days => 1), now()));  -- fixed: the 24-hour window named by decision 16:36 §3D
  insert into pipeline.process_results(process_key, scope_key, measured_at, summary, markdown, measured_by)
  values ('intake-progress', 'top-au', now(), v_summary,
          '# Automation progress: intake dates (generated)' || chr(10) || chr(10) || 'Measured ' || to_char(now() at time zone 'Australia/Sydney', 'YYYY-MM-DD HH24:MI') || ' Sydney. State '
          || (v_status->>'state') || '; latest run admitted ' || coalesce(v_status->'latest_run'->>'admitted', 'none') || ' of ' || coalesce(v_status->'latest_run'->>'selected', '0') || ' rows.' || chr(10),
          coalesce(auth.uid()::text, 'job process-results'))
  returning id into v_id;
  for a in select * from jsonb_array_elements(v_alerts) loop
    continue when not (a->>'routed')::boolean;
    v_fp := 'intake-progress:' || replace(a->>'code', '_', '-');
    if (a->>'tripped')::boolean then
      v_iss := security.integration_issue_upsert_v1(jsonb_build_object(
        'fingerprint', v_fp, 'title', 'Intake dates: ' || (a->>'label'), 'layer', 'Layer 2', 'subsystem', 'intake-dates', 'severity', 'P2', 'workstream', 'A8',
        'validation_layer', 'V4', 'source', 'process-results',
        'root_cause_class', case a->>'code' when 'job_overdue' then 'job_config' when 'repeated_deterministic' then 'code_defect' else 'unclassified' end,
        'failure', format('%s: %s affected. Last successful stage: %s.', a->>'label', a->>'affected', a->>'last_success_stage'),
        'expected', a->>'next_action',
        'evidence', jsonb_build_object('alert', a, 'process_result_id', v_id),
        'provider_ids', case when a->'evidence'->>'provider_id' is not null then jsonb_build_array(a->'evidence'->>'provider_id') else '[]'::jsonb end), 'process-results');
      v_out := v_out || jsonb_build_object(a->>'code', v_iss->>'issue_ref');
    else
      update pipeline.integration_issues i set condition_cleared_at = now()
       where i.fingerprint = v_fp and i.condition_cleared_at is null and i.status <> 'closed';
    end if;
  end loop;
  return jsonb_build_object('id', v_id, 'state', v_status->>'state', 'issues', v_out);
end $function$;
comment on function security.intake_progress_record_v1() is 'CF-247 Automation Progress observer (decision 16:36 §5, §6): saves a dated snapshot (process intake-progress in pipeline.process_results: status, latest run funnel, 24-hour university rows, alerts) and routes the zero-yield, monopolising, overdue, publication-mismatch and repeated-deterministic conditions to the existing integration queue (security.integration_issue_upsert_v1, fingerprint intake-progress:<code>, P2, workstream A8); a cleared condition sets condition_cleared_at. Called by job process-results; nothing earlier is overwritten.';

-- 5 the role-checked browser bridge (read only; Pause/Resume stays public.admin_automation_control) -----------------------------------------------
create or replace function public.admin_intake_progress_v1(p_view text, p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path to '' set statement_timeout to '20s' as $function$
declare v_rank int := security.current_role_rank(); v_since timestamptz; v_until timestamptz := now(); v_window text := coalesce(p_args->>'window', 'latest'); v_status jsonb;
        v_runs int := security.pipeline_num_v1('intake_progress.runs_listed', 24)::int;
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Operations read permission required' using errcode = '42501'; end if;
  if p_view = 'status' then
    v_status := security.intake_progress_status_v1(v_rank);
    return v_status || jsonb_build_object('alerts', security.intake_progress_alerts_v1(v_status), 'rank', v_rank);
  elsif p_view in ('window', 'runs') then
    if v_window = 'latest' then
      select max(e.run_at) into v_since from pipeline.course_intake_date_events e where e.outcome <> 'withdrawn';
      v_until := v_since;
    elsif v_window in ('24h', '7d', '30d') then
      v_since := now() - make_interval(days => case v_window when '24h' then 1 when '7d' then 7 else 30 end);  -- fixed: the windows named by decision 16:36 §3D
    else raise exception 'unknown window %', v_window using errcode = '22023';
    end if;
    if v_since is null then return jsonb_build_object('window', v_window, 'empty', true, 'universities', security.intake_progress_universities_v1(now(), now())); end if;
    if p_view = 'runs' then return security.intake_progress_runs_v1(v_since, v_until, v_runs); end if;
    return jsonb_build_object('window', v_window, 'since', v_since, 'until', v_until, 'funnel', security.intake_progress_window_v1(v_since, v_until),
      'universities', security.intake_progress_universities_v1(v_since, v_until), 'runs', security.intake_progress_runs_v1(v_since, v_until, v_runs));
  elsif p_view = 'failures' then
    return security.intake_progress_failures_v1(nullif(p_args->>'class', ''), nullif(p_args->>'provider_id', '')::uuid,
                                                security.pipeline_num_v1('intake_progress.failure_rows', 50)::int);
  elsif p_view = 'measurements' then
    return (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'measured_at', r.measured_at, 'measured_by', r.measured_by, 'state', r.summary->'status'->>'state',
                     'latest_run', r.summary->'status'->'latest_run', 'alerts', (select coalesce(jsonb_agg(a->>'code'), '[]'::jsonb) from jsonb_array_elements(r.summary->'alerts') a where (a->>'tripped')::boolean))
                     order by r.measured_at desc), '[]'::jsonb)
              from (select * from pipeline.process_results r where r.process_key = 'intake-progress' order by r.measured_at desc
                     limit security.pipeline_num_v1('process_results.history_rows', 30)::int) r);
  end if;
  raise exception 'unknown view %', p_view using errcode = '22023';
end $function$;
comment on function public.admin_intake_progress_v1(text, jsonb) is 'CF-247 Automation Progress (decision 5 Nov 2026 16:36 §3-§8): Layer 2/3 Operations › Process results › Automation progress. Views status, window (latest, 24h, 7d, 30d), runs, failures (class, provider_id) and measurements, from persisted records only; Operations read (rank 3) and above. Read only: Pause/Resume is the existing public.admin_automation_control.';
revoke all on function public.admin_intake_progress_v1(text, jsonb) from public, anon;
grant execute on function public.admin_intake_progress_v1(text, jsonb) to authenticated;
revoke all on function security.intake_progress_window_v1(timestamptz, timestamptz), security.intake_progress_universities_v1(timestamptz, timestamptz),
  security.intake_progress_runs_v1(timestamptz, timestamptz, integer), security.intake_progress_failures_v1(text, uuid, integer), security.intake_progress_status_v1(integer),
  security.intake_progress_alerts_v1(jsonb), security.intake_progress_record_v1() from public, anon, authenticated;

-- 6 job (G1): process-results gains one call (no new job; catalogued) ----------------------------------------------------------------------------
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('process-results', 'Admission', 67, 'Process results (intake dates)', 'Hourly at :53: records a dated measurement of the intake dates process.', 5, false)
on conflict (jobname) do nothing;
select cron.schedule('process-results', '53 * * * *', 'select security.intake_publication_check_v1(); select security.process_results_record_v1(); select security.process_results_recovery_record_v1(); select security.intake_progress_record_v1()');
update pipeline.automation_catalogue set description = description || ' Then records the Automation progress snapshot (process intake-progress) and routes zero-yield, monopolising, overdue, publication-mismatch and repeated-deterministic conditions to the integration queue (decision 5 Nov 2026 16:36 §5, §6).'
 where jobname = 'process-results' and description not like '%Automation progress%';

-- 7 component register (housekeeping) ------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('function', 'public.admin_intake_progress_v1', 'Platform', 'Operations', 'Process results › Automation progress: intake status, funnel, universities, history and failures (read only)', 'active', '{}', '20261106400000'),
 ('function', 'security.intake_progress_record_v1', 'Platform', 'Operations', 'Automation progress observer: snapshot and zero-yield routing (job process-results)', 'active', '{}', '20261106400000')
on conflict (kind, name) do nothing;
