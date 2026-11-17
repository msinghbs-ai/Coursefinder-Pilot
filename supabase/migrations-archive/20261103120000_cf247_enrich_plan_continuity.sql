-- CF-247 platform-led enrichment: work creation continues between plan cycles; manual and automatic runs share one mechanism (Workstream E;
-- Platform Admin direction 3 Nov 2026 09:32, admin docs/platform/nz-enrichment-brief/2026-11-03-platform-led-enrichment-autonomy-mandate-0932.md
-- §3, §4, §6; acceptance report 2026-11-03-platform-enrichment-control-autonomy-acceptance-report.md, engineering plan items 3 and 6;
-- controls audit 2026-11-03-enrichment-controls-audit.md §3.1-§3.4, §5, defects 3, 4, 7, 8, 9, 10).
-- Why (live, read-only, 3 Nov 2026 10:12-10:40 AEDT):
--   a. Automatic enrichment plans fell from about 420 a day (27-28 Oct) to 2 a day: security.enrich_plan_auto_v1 holds every university for
--      plans.redo_days (14) after its last automatic plan, whatever happened to its gaps since; nothing is eligible again until 4 Nov 14:41.
--   b. The standing gap queue (job field-gap-queue, security.field_gap_queue_tick_v1) failed on the 120 s statement time-out on 2 Nov 06:23 and
--      12:23 UTC (runs take 53-101 s). EXPLAIN ANALYZE (read-only SELECTs): the cross-check it runs first (security.field_crosscheck_v1, the
--      _cc select) took 60.3 s, because the per-course subquery was inlined and every adapter reading (two index probes) and every parse
--      function ran again for each use (38 sub-plans, enrich_parse_duration_v1 up to 14 times a course); with the readings fenced (offset 0) the
--      same select returns the same 2,717 rows in 25.6 s. The gap select itself took 4.6 s (a lateral by-index variant measured 6.2 s, so the
--      gap select is left as it is).
--   c. A manual Enrich fields task (and a plan's Fill missing fields step) queued items another open task already held (the standing queue
--      skips them, Start did not) and items of unpublished providers (the standing queue skips them, Start did not).
--   d. Enrichment plan › Cancel the run marked the run cancelled and left the tasks its steps had started running.
--   e. No retry of failed items and no export in Enrich fields or Enrichment plan; f. no spend estimate before Enrich fields Start or before
--      Scholarships › Coverage › Find scholarships now.
--   g. Scheduled jobs › Refresh schedules › Run on demand writes a Layer 2 refresh request that no function processes (206 queued since
--      1 Sep 2026; the last Layer 2 request completed 28 Sep). The screen now offers Run on demand for Layer 1 only and says why; the Layer 2
--      refresh schedules are marked retiring here; 205 stale requests are closed (status cancelled; the one important-date request stays, or
--      the hourly tick would write it again) and the 9 enabled Layer 2 schedules switched off (else the tick refills the queue) by the paste
--      file docs/paste/PASTE-20261103-layer2-refresh-requests-close.sql (with its rollback), guarded by count and id md5 measured read-only.
-- What:
--   1 security.enrich_plan_auto_v1 (md5-guarded replacement): a university planned inside plans.redo_days is planned again when its missing
--     values grew by at least plans.replan_min_new_gaps since its last automatic plan and that plan is at least plans.replan_min_days old;
--     re-plans come after never-planned and due universities and are capped at plans.replan_per_hour (0 = off; ships off). Everything else
--     is as before: the automatic switch, plans.auto_open_max, plans.auto_per_run, the priority countries, the hidden-provider rule, each
--     step waiting for room in its Firecrawl share. The run records what it re-plans (estimate.replan_of, missing_then).
--   2 security.field_crosscheck_v1 (md5-guarded edit), called first by the standing gap queue: each course's readings and each parse are
--     computed once (offset 0 fences), as measured in b. The gap queue function itself is unchanged.
--   3 security.enrich_item_in_flight_v1: the standing queue's in-flight rule (latest item queued, waiting, with AI, leased or for review) for
--     one course or university and field. public.admin_enrich_fields('start') (md5-guarded edit) leaves out such items and unpublished
--     providers (security.provider_hidden_v1) for every field, as the standing queue does.
--   4 security.enrich_plan_cancel_steps_v1: cancelling a plan run stops its pending and waiting steps and cancels each running step's task
--     through the task's own control (public.admin_jobs('cancel'), public.admin_provider_onboarding('stop')), as the person behind the run,
--     the way the step started it; each outcome is noted on the step and in the log. public.admin_enrich_plan('cancel') calls it.
--   5 Retry and export (same engines; screen role as the screen's own actions): admin_enrich_fields('retry') puts the failed items of a
--     finished task into a new task with a reason (rank 4; leaves out items in another open task and unpublished providers; at most
--     enrich.retry_items_max); admin_enrich_fields('export') returns the items of a task with source, quote and evidence, in pages of
--     enrich.export_page_rows (rank 3). admin_enrich_plan('retry') runs the failed, timed-out or stopped steps of a finished run again as a
--     Run now of the same university (same estimate and on-demand allowance; rank 4); admin_enrich_plan('export') returns one row per step
--     of the runs of the last plans.export_days days (one university or all), plans.export_runs_per_page runs a page (rank 3).
--   6 Estimates: admin_enrich_fields('preview') adds estimate (items Start would queue, items already in another task, unpublished; AI US$
--     from security.enrich_unit_costs_v1; most scraper credits) through security.enrich_fields_estimate_v1; admin_enrich_plan('unit_costs')
--     returns the same unit costs and the on-demand allowance left, for the Find scholarships now confirmation.
--   7 Overview limits show the re-plan settings.
-- Run now never changes a recurring schedule (mandate §6): unchanged here; the contract spec checks the three Run now paths.
-- Consumer API: untouched (G3). No consumer function, table or column changes.
-- Replaces: security.enrich_plan_auto_v1, security.field_crosscheck_v1, public.admin_enrich_fields, public.admin_enrich_plan (same names; md5-guarded)
-- Retires: Scheduled jobs › Refresh schedules › Run on demand for Layer 2 and the Layer 2 refresh schedules (marked retiring; requests closed and schedules switched off by the paste file)
-- Nothing is dropped or deleted. Nothing is switched on: re-planning ships off (plans.replan_per_hour 0).

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

-- a whole definition replaced, only from the definition it was written against
create or replace function pg_temp.replace_once(p_sig text, p_before text, p_after text, p_def text) returns text language plpgsql as $f$
begin
  if md5(pg_get_functiondef(p_sig::regprocedure)) = p_after then return p_sig || ': already applied'; end if;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_before then
    raise exception 'live % differs from the definition this change replaces (md5 %)', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)); end if;
  execute p_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the replacement has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after; end if;
  return p_sig || ': applied';
end $f$;

-- 0. the definitions the new code calls are the ones it was written against (not changed here)
do $g$
declare r record;
begin
  for r in select * from (values ('security.enrich_plan_start_step_v1(uuid,text)', '4e240fab607122eff455ea3c57b5447f'),
                                 ('security.enrich_unit_costs_v1()', '9ffc69020b6f84c3b4b0af11650b634f'),
                                 ('security.enrich_plan_priority_v1()', '366ff12040bac05d4e494956319a2b76')) v(sig, m) loop
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then raise exception 'live % differs from the definition this change was written against', r.sig; end if;
  end loop;
end $g$;

-- 1. settings (G2) -----------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'plans.replan_per_hour', 'Enrichment plans: re-plans an hour when gaps grow',
  'A university planned in the last plans.redo_days days is planned again when its missing values grew since that plan; at most this many such re-plans start in an hour, after the universities that are due anyway. 0 switches re-planning off (shipped off, 3 Nov 2026).',
  'number', '0'::jsonb, '0', '100', 'plans an hour', 125, 'Onboarding', 'security.enrich_plan_auto_v1 (job enrich-plan-auto); public.admin_enrich_plan overview',
  'Platform Admin direction 3 Nov 2026 09:32 §4: automatic plans stopped for 14 days whatever happened to the gaps'),
 ('pipeline', 'plans.replan_min_new_gaps', 'Enrichment plans: new missing values that count as a change',
  'A university is re-planned early only when its missing values rose by at least this many since its last automatic plan.',
  'number', '5'::jsonb, '1', '10000', 'missing values', 126, 'Onboarding', 'security.enrich_plan_auto_v1',
  'Platform Admin direction 3 Nov 2026 09:32 §4: re-plan when the gaps change'),
 ('pipeline', 'plans.replan_min_days', 'Enrichment plans: shortest time between a plan and a re-plan',
  'A university is never re-planned sooner than this many days after its last automatic plan, however its gaps changed.',
  'number', '2'::jsonb, '0', '14', 'days', 127, 'Onboarding', 'security.enrich_plan_auto_v1',
  'Platform Admin direction 3 Nov 2026 09:32 §4: no flood of re-plans'),
 ('pipeline', 'plans.export_days', 'Enrichment plans: export covers the last',
  'Export results (CSV) on Enrichment plan lists the runs started in this many days.',
  'number', '30'::jsonb, '1', '365', 'days', 128, 'Onboarding', 'public.admin_enrich_plan export',
  'Platform Admin direction 3 Nov 2026 09:32 §3: export execution and evidence results'),
 ('pipeline', 'plans.export_runs_per_page', 'Enrichment plans: runs in one export page',
  'Export results (CSV) reads the runs in pages of this many.', 'number', '500'::jsonb, '10', '5000', 'runs', 129, 'Onboarding', 'public.admin_enrich_plan export',
  'Platform Admin direction 3 Nov 2026 09:32 §3: export execution and evidence results'),
 ('pipeline', 'enrich.export_page_rows', 'Enrich fields: items in one export page',
  'Export results (CSV) on Enrich fields reads a task''s items in pages of this many.', 'number', '2000'::jsonb, '100', '10000', 'items', 107, 'Job sizes',
  'public.admin_enrich_fields export', 'Platform Admin direction 3 Nov 2026 09:32 §3: export execution and evidence results'),
 ('pipeline', 'enrich.retry_items_max', 'Enrich fields: most failed items retried at once',
  'Retry failed items puts at most this many failed items of a finished task into a new task.', 'number', '5000'::jsonb, '1', '100000', 'items', 108, 'Job sizes',
  'public.admin_enrich_fields retry', 'Platform Admin direction 3 Nov 2026 09:32 §3: retry failed items')
on conflict (toolset_key, key) do nothing;

-- 3. the in-flight rule and the estimate ---------------------------------------------------------------------------------------------------
create or replace function security.enrich_item_in_flight_v1(p_provider uuid, p_course uuid, p_field text) returns boolean
language sql stable security definer set search_path = '' as $$
  -- the standing gap queue's rule (security.field_gap_queue_tick_v1): the latest item of this course (or university) and field is being
  -- worked on, or waits for a person
  select coalesce(case when p_course is not null
    then (select e.state in ('queued', 'waiting', 'ai', 'leased', 'review') from pipeline.field_enrich_items e
           where e.course_id = p_course and e.field = p_field and e.provider_id = p_provider order by e.id desc limit 1)
    else (select e.state in ('queued', 'waiting', 'ai', 'leased', 'review') from pipeline.field_enrich_items e
           where e.course_id is null and e.provider_id = p_provider and e.field = p_field order by e.id desc limit 1) end, false)
$$;
comment on function security.enrich_item_in_flight_v1(uuid, uuid, text) is 'CF-247 3 Nov 2026 (Platform Admin 09:32 §6): true when the latest Enrich fields item of this course (or university, course null) and field is queued, waiting, with AI, leased or for review. Manual tasks, retries and the standing queue leave such items to the task that holds them.';
revoke all on function security.enrich_item_in_flight_v1(uuid, uuid, text) from public, anon, authenticated;

create or replace function security.enrich_fields_estimate_v1(p_cc text[], p_pids uuid[], p_fields text[], p_ai boolean, p_scraper boolean) returns jsonb
language sql stable security definer set search_path = '' as $$
  with scope as (
    select c.id, c.provider_id, c.duration_value, c.study_level_id, c.delivery_mode, c.primary_field_id, c.open_to_international
      from catalogue.courses c join catalogue.providers p on p.id = c.provider_id join ref.countries k on k.id = p.country_id
     where c.lifecycle_status = 'active' and (cardinality(p_cc) = 0 or k.iso_alpha2::text = any (p_cc)) and (cardinality(p_pids) = 0 or c.provider_id = any (p_pids))),
  miss as (
    select s.id, s.provider_id, f.x field, exists (select 1 from security.provider_hidden_v1 h where h.provider_id = s.provider_id) hidden
      from scope s cross join unnest(p_fields) f(x)
     where f.x not in ('provider_address', 'campus_region', 'campus_list')
       and case f.x when 'campus' then not exists (select 1 from catalogue.course_campuses x where x.course_id = s.id)
                    when 'duration' then s.duration_value is null when 'level' then s.study_level_id is null
                    when 'delivery' then nullif(btrim(s.delivery_mode), '') is null when 'field_of_study' then s.primary_field_id is null
                    when 'international' then s.open_to_international is null
                    when 'english' then not exists (select 1 from catalogue.course_english_requirements x where x.course_id = s.id and coalesce(x.status, 'active') = 'active')
                    when 'intakes' then not exists (select 1 from catalogue.course_intakes x where x.course_id = s.id and x.status = 'active') else false end),
  m as (select m0.*, (not m0.hidden and security.enrich_item_in_flight_v1(m0.provider_id, m0.id, m0.field)) in_task from miss m0),
  u as (select coalesce((security.enrich_unit_costs_v1()->>'enrich_usd_per_item')::numeric, 0) usd)
  select jsonb_build_object('estimate', jsonb_build_object(
    'items', (select count(*) from m where not hidden and not in_task),
    'in_task', (select count(*) from m where in_task),
    'unpublished', (select count(*) from m where hidden),
    'usd_per_item', u.usd,
    'usd', case when p_ai then round((select count(*) from m where not hidden and not in_task) * u.usd, 4) else 0 end,
    'credits_max', case when p_scraper then (select count(distinct m2.id) from m m2 where not m2.hidden and not m2.in_task
                                               and not exists (select 1 from pipeline.coverage_course_pages g where g.course_id = m2.id and g.evidence_id is not null)) else 0 end))
    from u
$$;
comment on function security.enrich_fields_estimate_v1(text[], uuid[], text[], boolean, boolean) is 'CF-247 3 Nov 2026 (Platform Admin 09:32 §3 "Estimate new Firecrawl/AI expenditure"): what Enrich fields Start would queue for a scope (course fields), the items another open task holds, the items of unpublished providers, the AI estimate (items x the average AI cost of an item in the last 30 days, security.enrich_unit_costs_v1) and the most scraper credits (one read for each course without a stored page, only when new reads are allowed).';
revoke all on function security.enrich_fields_estimate_v1(text[], uuid[], text[], boolean, boolean) from public, anon, authenticated;

-- 4. cancelling a plan run cancels the tasks its steps started -----------------------------------------------------------------------------
create or replace function security.enrich_plan_cancel_steps_v1(p_run uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r pipeline.enrich_plan_runs%rowtype; s jsonb; i int; v_claims text := current_setting('request.jwt.claims', true); v_note text; v_steps jsonb;
        v_tasks jsonb := '[]'::jsonb; v_n int := 0;
begin
  select * into r from pipeline.enrich_plan_runs where id = p_run;
  if r.id is null then return jsonb_build_object('steps_cancelled', 0, 'tasks', v_tasks); end if;
  v_steps := r.steps;
  for i in 0 .. coalesce(jsonb_array_length(r.steps), 0) - 1 loop
    s := r.steps->i;
    continue when coalesce(s->>'status', '') not in ('pending', 'waiting', 'running');
    v_note := 'cancelled with the run: ' || p_reason;
    if s->>'status' = 'running' and nullif(s->'ref'->>'id', '') is not null and s->'ref'->>'kind' in ('job', 'onboarding') then
      begin
        -- the task was started as the person behind the run (security.enrich_plan_start_step_v1); it is cancelled the same way, through its own control
        perform set_config('request.jwt.claims', json_build_object('sub', r.requested_by, 'role', 'authenticated')::text, true);
        if s->'ref'->>'kind' = 'job' then
          perform public.admin_jobs('cancel', jsonb_build_object('id', s->'ref'->>'id', 'reason', 'Enrichment plan cancelled: ' || p_reason));
        else
          perform public.admin_provider_onboarding('stop', jsonb_build_object('ids', jsonb_build_array(s->'ref'->>'id'), 'reason', 'Enrichment plan cancelled: ' || p_reason));
        end if;
        v_note := 'task cancelled with the run: ' || p_reason;
        v_tasks := v_tasks || jsonb_build_object('step', s->>'step', 'kind', s->'ref'->>'kind', 'id', s->'ref'->>'id', 'cancelled', true);
      exception when others then
        v_note := 'the task could not be cancelled (' || left(sqlerrm, 200) || '); see Task manager';
        v_tasks := v_tasks || jsonb_build_object('step', s->>'step', 'kind', s->'ref'->>'kind', 'id', s->'ref'->>'id', 'cancelled', false, 'error', left(sqlerrm, 200));
      end;
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
    v_steps := jsonb_set(v_steps, array[i::text], s || jsonb_build_object('status', 'cancelled', 'note', v_note, 'finished_at', now()));
    v_n := v_n + 1;
  end loop;
  update pipeline.enrich_plan_runs set steps = v_steps, updated_at = now() where id = p_run;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('enrich_plan', 'cancel', r.provider_id::text, jsonb_build_object('run', p_run, 'reason', p_reason, 'steps_cancelled', v_n, 'tasks', v_tasks), auth.uid());
  return jsonb_build_object('steps_cancelled', v_n, 'tasks', v_tasks);
end $$;
comment on function security.enrich_plan_cancel_steps_v1(uuid, text) is 'CF-247 3 Nov 2026 (Platform Admin 09:32 §3 "Cancel safely"): the pending, waiting and running steps of a cancelled plan run become cancelled; each running step''s task is cancelled through its own control (admin_jobs cancel, provider onboarding stop) as the person behind the run, the way the step started it. Each outcome is on the step and in admin_control_events.';
revoke all on function security.enrich_plan_cancel_steps_v1(uuid, text) from public, anon, authenticated;

-- 5. automatic plans: re-plan when the gaps grew ------------------------------------------------------------------------------------------
select pg_temp.replace_once('security.enrich_plan_auto_v1()', 'f9409768bf82bbb29f17ce514c8f9b11', '2d8944d7624b90cbbefb9925d602c92b', $d$CREATE OR REPLACE FUNCTION security.enrich_plan_auto_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c pipeline.enrich_plan_control%rowtype; v_open int; v_room int; v_n int := 0; q record; v_plan jsonb; v_steps jsonb;
        v_redo int := security.pipeline_num_v1('plans.redo_days', 14)::int;
        -- 3 Nov 2026 (Platform Admin 09:32 §4): a university whose missing values grew since its last automatic plan is planned again before
        -- plans.redo_days, at most plans.replan_per_hour an hour (0 = off), never sooner than plans.replan_min_days after that plan
        v_re_max int := security.pipeline_num_v1('plans.replan_per_hour', 0)::int;
        v_re_rise int := security.pipeline_num_v1('plans.replan_min_new_gaps', 5)::int;
        v_re_days int := security.pipeline_num_v1('plans.replan_min_days', 2)::int;
        v_re_used int; v_re int := 0; v_is_re boolean;
begin
  select * into c from pipeline.enrich_plan_control where id = 1;
  if not coalesce(c.auto_enabled, false) then return jsonb_build_object('auto', 'off'); end if;
  select count(*) into v_open from pipeline.enrich_plan_runs where mode = 'auto' and state in ('queued', 'running');
  v_room := least(security.pipeline_num_v1('plans.auto_open_max', 20)::int - v_open, security.pipeline_num_v1('plans.auto_per_run', 10)::int);
  if v_room <= 0 then return jsonb_build_object('auto', 'full', 'open', v_open); end if;
  select count(*) into v_re_used from pipeline.enrich_plan_runs
   where mode = 'auto' and estimate ? 'replan_of' and created_at > now() - make_interval(hours => 1);  -- fixed: the re-plan cap is a count per hour
  for q in select x.*, l.id last_id, l.created_at last_at, l.missing_then
             from security.enrich_plan_priority_v1() x
             left join lateral (select r.id, r.created_at, (r.estimate->>'missing')::numeric missing_then from pipeline.enrich_plan_runs r
                                 where r.provider_id = x.provider_id and r.mode = 'auto' order by r.created_at desc limit 1) l on true
            where not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = x.provider_id)  -- 22 Oct 2026 (Platform Admin 11:42): unpublished providers wait; publishing them again brings them back
              and not exists (select 1 from pipeline.enrich_plan_runs r where r.provider_id = x.provider_id and r.state in ('queued', 'running'))
              and (l.id is null or l.created_at <= now() - make_interval(days => v_redo)
                   or (v_re_max > 0 and l.created_at <= now() - make_interval(days => v_re_days) and x.missing >= l.missing_then + v_re_rise))
            order by (l.id is null or l.created_at <= now() - make_interval(days => v_redo)) desc,
                     (x.country in (select jsonb_array_elements_text(coalesce(s.value, '[]'::jsonb)) from pipeline.platform_toolset_settings s
                                     where s.toolset_key = 'pipeline' and s.key = 'plans.priority_countries')) desc,
                     x.missing desc, x.best_rank nulls last limit v_room * 3 loop
    exit when v_n >= v_room;
    v_is_re := q.last_id is not null and q.last_at > now() - make_interval(days => v_redo);
    continue when v_is_re and v_re_used + v_re >= v_re_max;
    v_plan := security.enrich_plan_v1(q.provider_id);
    v_steps := (select coalesce(jsonb_agg(x || jsonb_build_object('status', 'pending')), '[]'::jsonb) from jsonb_array_elements(v_plan->'steps') x where not coalesce((x->>'running')::boolean, false));
    continue when jsonb_array_length(v_steps) = 0 or (select bool_and(coalesce((x->>'person')::boolean, false)) from jsonb_array_elements(v_steps) x);
    insert into pipeline.enrich_plan_runs(provider_id, mode, steps, estimate, requested_by, reason)
    values (q.provider_id, 'auto', v_steps, jsonb_build_object('credits', v_plan->'est_credits', 'usd', v_plan->'est_usd', 'missing', q.missing)
              || case when v_is_re then jsonb_build_object('replan_of', q.last_id, 'missing_then', q.missing_then) else '{}'::jsonb end, c.owner,
            case when v_is_re then 'Automatic enrichment plan (missing values grew from ' || q.missing_then || ' to ' || q.missing || ' since the last plan): '
                 else 'Automatic enrichment plan (most missing first): ' end || c.reason)
    on conflict do nothing;
    if found then v_n := v_n + 1; if v_is_re then v_re := v_re + 1; end if; end if;
  end loop;
  return jsonb_build_object('auto', 'on', 'started', v_n, 'replanned', v_re, 'open', v_open + v_n);
end $function$
$d$);

-- 6. the standing gap queue's cross-check: each reading once -----------------------------------------------------------------------------------------------
select pg_temp.edit_once('security.field_crosscheck_v1()', '1023e1373007f09773d2d529d489e9ba', 'b8a5b2de244c277aa4b9e47547017dd7', array[
  array[$o$                from catalogue.courses c where c.lifecycle_status = 'active') x
$o$, $n$                from catalogue.courses c where c.lifecycle_status = 'active' offset 0) x  -- 3 Nov 2026: each course's readings once (inlined, they ran again for every use: 60 s)
$n$],
  array[$o$nullif(btrim(x.ex->>'duration'), '')) d) p,$o$, $n$nullif(btrim(x.ex->>'duration'), '')) d offset 0) p,$n$],
  array[$o$nullif(btrim(x.ex->>'study_level'), '')) l) p$o$, $n$nullif(btrim(x.ex->>'study_level'), '')) l offset 0) p$n$],
  array[$o$x.provider_id) m) p$o$, $n$x.provider_id) m offset 0) p$n$]
], array[1, 1, 1, 1]);

-- 7. Enrich fields: in-flight and published rules at Start; estimate; retry; export ----------------------------------------------------------
select pg_temp.edit_once('public.admin_enrich_fields(text,jsonb)', '184f74ae316051ec0cb4dd62c22b190d', '349584fc0e9b605e1067cbbd488e435a', array[
  array[$o$v_n int; v_title text;
begin$o$, $n$v_n int; v_title text; v_src pipeline.admin_jobs%rowtype;
begin$n$],
  array[$o$              from f);
  elsif p_action = 'start' then$o$, $n$              from f)
           -- 3 Nov 2026 (Platform Admin 09:32 §3): what Start would queue and its estimated spend
           || security.enrich_fields_estimate_v1(v_cc, v_pids, v_fields, coalesce((p_args->>'ai')::boolean, true), coalesce((p_args->>'scraper')::boolean, false));
  elsif p_action = 'start' then$n$],
  array[$o$     where c.lifecycle_status = 'active' and f.x <> 'provider_address'
$o$, $n$     where c.lifecycle_status = 'active' and f.x <> 'provider_address'
       -- 3 Nov 2026 (Platform Admin 09:32 §6): the standing queue's rules; unpublished providers wait, and an item another open task holds is left to it
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = c.provider_id)
       and not security.enrich_item_in_flight_v1(c.provider_id, c.id, f.x)
$n$],
  array[$o$     where 'campus_region' = any (v_fields)
$o$, $n$     where 'campus_region' = any (v_fields)
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id) and not security.enrich_item_in_flight_v1(p.id, null, 'campus_region')
$n$],
  array[$o$       where nullif(btrim(p.address_line1), '') is null and coalesce(p.lifecycle_status, 'active') = 'active'
$o$, $n$       where nullif(btrim(p.address_line1), '') is null and coalesce(p.lifecycle_status, 'active') = 'active'
         and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id) and not security.enrich_item_in_flight_v1(p.id, null, 'provider_address')
$n$],
  array[$o$  elsif p_action = 'rule_set' then$o$, $n$  elsif p_action = 'retry' then
    -- 3 Nov 2026 (Platform Admin 09:32 §3 "Retry failed items"): the failed items of a finished task go into a new task of the same engine,
    -- with a reason; items another open task holds and unpublished providers are left out, as at Start
    if v_rank < 4 then raise exception 'Pipeline Operator role or above required' using errcode = '42501'; end if;
    v_reason := btrim(coalesce(p_args->>'reason', ''));
    if length(v_reason) < 4 then raise exception 'give a reason (it is kept with the task)'; end if;
    select * into v_src from pipeline.admin_jobs j where j.id = nullif(p_args->>'job_id', '')::uuid and j.kind = 'enrich_fields';
    if v_src.id is null then raise exception 'unknown task'; end if;
    if v_src.state not in ('done', 'failed', 'cancelled') then raise exception 'the task is still open; retry its failed items when it has finished'; end if;
    select count(*) into v_n from (select 1 from pipeline.field_enrich_items e
      where e.job_id = v_src.id and e.state = 'failed' and e.field <> 'campus_list'
        and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = e.provider_id)
        and not security.enrich_item_in_flight_v1(e.provider_id, e.course_id, e.field)
      limit security.pipeline_num_v1('enrich.retry_items_max', 5000)::int) z;
    if v_n = 0 then raise exception 'no failed item to retry (or each is already in another open task)'; end if;
    insert into pipeline.admin_jobs(kind, lane, state, title, args, progress, requested_by, reason, scope)
    values ('enrich_fields', 'enrich', 'queued', left('Retry failed · ' || v_src.title, 200), (v_src.args - 'standing') || jsonb_build_object('retry_of', v_src.id),
            jsonb_build_object('done', 0, 'total', 0), auth.uid(), v_reason, v_src.scope)
    returning id into v_job;
    insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field)
    select v_job, e.provider_id, e.course_id, e.field from pipeline.field_enrich_items e
     where e.job_id = v_src.id and e.state = 'failed' and e.field <> 'campus_list'
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = e.provider_id)
       and not security.enrich_item_in_flight_v1(e.provider_id, e.course_id, e.field)
     order by e.id limit security.pipeline_num_v1('enrich.retry_items_max', 5000)::int
    on conflict do nothing;
    insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state)
    select distinct v_job, e.provider_id, null::uuid, 'campus_list', 'waiting' from pipeline.field_enrich_items e where e.job_id = v_job and e.field = 'campus'
    on conflict do nothing;
    select count(*) into v_n from pipeline.field_enrich_items where job_id = v_job;
    update pipeline.admin_jobs set progress = jsonb_build_object('done', 0, 'total', v_n) where id = v_job;
    insert into pipeline.admin_job_events(job_id, note, detail) values (v_job, v_n || ' failed item(s) to settle again', jsonb_build_object('retry_of', v_src.id, 'reason', v_reason));
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('enrich_fields', 'retry_failed', v_src.id::text, jsonb_build_object('job_id', v_job, 'items', v_n, 'reason', v_reason), auth.uid());
    return jsonb_build_object('job_id', v_job, 'items', v_n, 'retry_of', v_src.id);
  elsif p_action = 'export' then
    -- 3 Nov 2026 (Platform Admin 09:32 §3 "Export execution and evidence results"): every item of a task with its source, quote and evidence,
    -- in pages (pass the last id as after)
    return (select jsonb_build_object('rows', coalesce(jsonb_agg(z.x order by z.id), '[]'::jsonb), 'page_rows', security.pipeline_num_v1('enrich.export_page_rows', 2000)) from (
      select e.id, jsonb_build_object('id', e.id, 'university', coalesce(p.display_name, p.canonical_name), 'course', c.canonical_title, 'course_code', c.course_code,
               'course_id', e.course_id, 'provider_id', e.provider_id, 'field', e.field, 'state', e.state, 'source', e.source, 'value', e.value, 'quote', e.quote,
               'reason', e.reason, 'evidence_id', e.evidence_id, 'attempts', e.attempts, 'cost_usd', e.cost_usd, 'updated_at', e.updated_at) x
        from pipeline.field_enrich_items e join catalogue.providers p on p.id = e.provider_id left join catalogue.courses c on c.id = e.course_id
       where e.job_id = nullif(p_args->>'job_id', '')::uuid and e.id > coalesce(nullif(p_args->>'after', '')::bigint, 0)
       order by e.id limit security.pipeline_num_v1('enrich.export_page_rows', 2000)::int) z);
  elsif p_action = 'rule_set' then$n$]
], array[1, 1, 1, 1, 1, 1]);

-- 8. Enrichment plan: cancel cancels the tasks; retry; export; unit costs; re-plan limits ---------------------------------------------------
select pg_temp.edit_once('public.admin_enrich_plan(text,jsonb)', 'bd460fcd0e5b4e1dfd41ec1065c2a60c', '0c9d3ec1b7d043e2d9f3ac83f9d99e1d', array[
  array[$o$'redo_days', security.pipeline_num_v1('plans.redo_days', 14), $o$,
        $n$'redo_days', security.pipeline_num_v1('plans.redo_days', 14), 'replan_per_hour', security.pipeline_num_v1('plans.replan_per_hour', 0),
                                   'replan_min_new_gaps', security.pipeline_num_v1('plans.replan_min_new_gaps', 5), 'replan_min_days', security.pipeline_num_v1('plans.replan_min_days', 2),
                                   $n$],
  array[$o$     where id = (p_args->>'run_id')::uuid and state in ('queued', 'running');
    return jsonb_build_object('cancelled', found);$o$,
        $n$     where id = (p_args->>'run_id')::uuid and state in ('queued', 'running') returning id into v_id;
    if v_id is null then return jsonb_build_object('cancelled', false); end if;
    -- 3 Nov 2026 (Platform Admin 09:32 §3 "Cancel safely"): the run's open steps stop and each running step's task is cancelled
    return jsonb_build_object('cancelled', true) || security.enrich_plan_cancel_steps_v1(v_id, coalesce(nullif(v_reason, ''), 'by a person'));$n$],
  array[$o$  elsif p_action = 'control' then$o$,
        $n$  elsif p_action = 'retry' then
    -- 3 Nov 2026 (Platform Admin 09:32 §3 "Retry failed items"): the failed, timed-out or stopped steps of a finished run run again as a Run now
    -- of the same university, through the same steps, estimate and on-demand allowance
    if v_rank < 4 then raise exception 'Pipeline Operator role or above required' using errcode = '42501'; end if;
    if length(v_reason) < 4 then raise exception 'give a reason (kept with the run)'; end if;
    select r.provider_id, jsonb_agg(s->'step') into v_pid, v_steps
      from pipeline.enrich_plan_runs r cross join lateral jsonb_array_elements(r.steps) s
     where r.id = nullif(p_args->>'run_id', '')::uuid and r.state in ('done', 'failed', 'cancelled') and s->>'status' in ('failed', 'timed_out', 'stopped')
     group by r.provider_id;
    if v_pid is null then raise exception 'nothing to retry: the run is still open, or none of its steps failed'; end if;
    return public.admin_enrich_plan('run', jsonb_build_object('provider', v_pid, 'steps', v_steps,
             'reason', 'Retry of the failed steps of run ' || left(p_args->>'run_id', 8) || ': ' || v_reason)) || jsonb_build_object('retry_of', p_args->>'run_id', 'steps', v_steps);
  elsif p_action = 'export' then
    -- 3 Nov 2026 (Platform Admin 09:32 §3 "Export execution and evidence results"): one row per step of each run of the last plans.export_days
    -- days (one university, or all), plans.export_runs_per_page runs a page
    return jsonb_build_object('page_runs', security.pipeline_num_v1('plans.export_runs_per_page', 500),
      'runs', (select count(*) from (select 1 from pipeline.enrich_plan_runs r0
               where (v_pid is null or r0.provider_id = v_pid) and r0.created_at > now() - make_interval(days => security.pipeline_num_v1('plans.export_days', 30)::int)
               limit security.pipeline_num_v1('plans.export_runs_per_page', 500)::int offset greatest(coalesce(nullif(p_args->>'offset', '')::int, 0), 0)) c),
      'rows', (select coalesce(jsonb_agg(to_jsonb(z) order by z.created_at desc, z.run, z.step_no), '[]'::jsonb) from (
      select r.id run, coalesce(p.display_name, p.canonical_name) university, r.provider_id, r.mode, r.state, r.created_at, r.finished_at, r.reason, r.needs_person,
             e.o step_no, e.s->>'step' step, e.s->>'label' label, e.s->>'status' status, e.s->>'note' note, e.s->'ref'->>'kind' task_kind, e.s->'ref'->>'id' task_id,
             e.s->>'started_at' step_started_at, e.s->>'finished_at' step_finished_at, e.s->>'est_credits' est_credits, e.s->>'est_usd' est_usd,
             r.actual->>'credits' actual_credits, r.actual->>'usd' actual_usd
        from (select * from pipeline.enrich_plan_runs r0
               where (v_pid is null or r0.provider_id = v_pid) and r0.created_at > now() - make_interval(days => security.pipeline_num_v1('plans.export_days', 30)::int)
               order by r0.created_at desc, r0.id
               limit security.pipeline_num_v1('plans.export_runs_per_page', 500)::int offset greatest(coalesce(nullif(p_args->>'offset', '')::int, 0), 0)) r
        join catalogue.providers p on p.id = r.provider_id
        cross join lateral jsonb_array_elements(r.steps) with ordinality e(s, o)) z));
  elsif p_action = 'unit_costs' then
    -- 3 Nov 2026 (Platform Admin 09:32 §3 "Estimate new Firecrawl/AI expenditure"): the unit costs the plan estimates use, for other confirmations
    return jsonb_build_object('unit_costs', security.enrich_unit_costs_v1(), 'on_demand', jsonb_build_object('credits_left', v_left_c, 'usd_left', v_left_u));
  elsif p_action = 'control' then$n$]
], array[1, 1, 1]);

-- 9. housekeeping: the register -------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('function', 'security.enrich_item_in_flight_v1', 'Layer 2/3', 'Enrichment', 'The standing gap queue''s in-flight rule for one course or university and field (manual Start, retry, standing queue)', 'active', '{}', '20261103120000'),
 ('function', 'security.enrich_fields_estimate_v1', 'Layer 2/3', 'Enrichment', 'Enrich fields Preview: items Start would queue and their estimated AI and scraper spend', 'active', '{}', '20261103120000'),
 ('function', 'security.enrich_plan_cancel_steps_v1', 'Layer 2/3', 'Enrichment', 'Cancelling a plan run cancels the tasks its steps started', 'active', '{}', '20261103120000')
on conflict do nothing;
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaced_by, retire_after, introduced_in, note) values
 ('screen', 'Scheduled jobs › Refresh schedules › Run on demand (Layer 2)', 'L2 read', 'Scheduled jobs',
  'Run on demand for a Layer 2 refresh schedule (writes pipeline.refresh_requests for Layer 2)', 'retiring',
  'Layer 2/3 Build & enrich engines and their own Run now (Enrich fields, Enrichment plan, Course sources, Scholarships)',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261103120000',
  '3 Nov 2026 (controls audit defect 3): no function processes Layer 2 refresh requests (206 queued since 1 Sep); the button offers Layer 1 only'),
 ('screen', 'Scheduled jobs › Refresh schedules (Layer 2 schedules)', 'L2 read', 'Scheduled jobs',
  'The Layer 2 rows of pipeline.refresh_policies (PRISMS, QILT, DFAT and Study Australia scholarships, RMIT, UQ and Federation course pages)', 'retiring',
  'Layer 2/3 Build & enrich engines (standing gap queue, enrichment plans, course-link search, scholarship discovery)',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261103120000',
  '3 Nov 2026: switched off and their stale requests closed by docs/paste/PASTE-20261103-layer2-refresh-requests-close.sql')
on conflict (kind, name) do update set status = excluded.status, replaced_by = excluded.replaced_by, retire_after = excluded.retire_after, note = excluded.note, updated_at = now()
 where pipeline.component_register.status = 'active';
update pipeline.component_register set note = coalesce(note || '. ', '') || '3 Nov 2026 (20261103120000): plan continuity, dedupe, cancel, retry, export', updated_at = now()
 where kind = 'function' and name in ('security.enrich_plan_auto_v1', 'security.field_crosscheck_v1', 'public.admin_enrich_fields', 'public.admin_enrich_plan')
   and coalesce(note, '') not like '%20261103120000%';

-- 10. post-check -----------------------------------------------------------------------------------------------------------------------------
do $$
begin
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline'
        and key in ('plans.replan_per_hour', 'plans.replan_min_new_gaps', 'plans.replan_min_days', 'plans.export_days', 'plans.export_runs_per_page', 'enrich.export_page_rows', 'enrich.retry_items_max')) <> 7 then
    raise exception 'plan continuity post-check: settings missing'; end if;
end $$;

select 'plan continuity: re-plan (off), gap-queue cross-check reads once, dedupe and published rule at Start, cancel cascades, retry, export, estimates' ok;
