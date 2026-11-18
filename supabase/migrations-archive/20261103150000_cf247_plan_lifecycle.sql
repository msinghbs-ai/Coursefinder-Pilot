-- CF-247 enrichment-plan lifecycle: safe re-planning, one plan per university, no orphaned work (Agent A; Platform Admin P0 mandate
-- 3 Nov 2026 10:44 §3 Agent A, admin docs/platform/nz-enrichment-brief/2026-11-03-p0-continuous-orchestration-mandate-1044.md; builds on
-- 20261103120000_cf247_enrich_plan_continuity, v2.15.419).
-- Why (live, read-only, 3 Nov 2026 10:45-11:08 AEDT; v2.15.419 confirmed deployed at 11:05 by md5):
--   a. v2.15.419 re-plans a university inside plans.redo_days (14) only when its missing values grew. A university whose gaps did not grow
--      stays held even when new verified evidence arrived after its last plan (a course page bound and read with evidence, or its central
--      pages searched again), or when a step of its last plan failed for a cause that has since cleared (Firecrawl share refilled, the task
--      behind a timed-out step ended, a transient error some hours ago). Nothing stops the same inputs being planned twice, and a re-plan
--      repeats steps that were already done.
--   b. Order: due universities are taken by country priority and most missing first, so a university with few gaps can wait behind
--      larger ones indefinitely (no age fairness).
--   c. Run now on a university with an open automatic plan is refused ("a plan is already running"), so the operator cannot act; a Run now
--      done yesterday does not stop an automatic plan of the same university today.
--   Measured 11:06 (read-only; the rules below, settings at their defaults): of 1,601 universities the picker sees with no open plan, 1,589
--   are held by plans.redo_days and 12 have never been planned. Held universities that would qualify: grown gaps 131 (v2.15.419), new
--   verified course pages 348 (central pages 0), retryable steps 7; 403 in all (AU 215, NZ 145, CA 43), each subject to plans.replan_per_hour.
--   Retrying by time without plans.retry_waits_for_change would have taken 979: 791 adapters stopped for too few pages or nothing ready and
--   245 course-page searches that cannot start. Orphaned plan tasks today: 0 (no open plan run; 0 Run now plans ever).
--   d. Cancel (v2.15.419) cancels the running steps' tasks, but nothing in security.enrich_plan_start_step_v1 refuses a run that is no longer
--      open, and nothing checks for plan tasks still running without a live plan (a step that timed out "carries on").
-- What:
--   1 security.enrich_plan_inputs_v1(provider): what a re-plan depends on, against the university's latest run (any mode): new verified
--     evidence since it finished (course pages read with evidence, central pages searched), and the steps that became retryable (a share
--     skip whose share has room again; a failed, stopped or cancelled step plans.retry_after_hours after it ended; a timed-out step whose
--     task has ended failed or cancelled), each at most plans.step_retry_max times in plans.redo_days. A cause that time does not clear
--     (plans.retry_waits_for_change: too few pages, nothing ready, no website, not a search target, every course already has a page) is not
--     retryable by time: measured 3 Nov, those are 1,036 of the 1,043 unfinished last steps, and retrying them would be a loop. Read-only.
--   2 security.enrich_plan_auto_v1 (md5-guarded replacement of the v2.15.419 definition):
--     - re-plans early on new evidence (plans.replan_on_evidence) and on retryable steps (plans.replan_on_retry), beside v2.15.419's grown
--       gaps; all early re-plans share plans.replan_per_hour and wait plans.replan_min_days after the university's latest plan of any mode;
--     - an input fingerprint (missing values, verified evidence, central pages, retryable steps) is kept on each run; an early re-plan with the
--       same fingerprint as the latest run is not started, and one that found no step to run is recorded in pipeline.enrich_plan_noop (new
--       table) and not evaluated again until its fingerprint changes (so universities with nothing to do never hold the hourly slots);
--     - index pipeline.enrich_plan_runs (provider_id, created_at desc) for the per-university latest-run reads;
--     - an early re-plan keeps only steps whose inputs changed (Find course pages when gaps grew; Fill missing fields when gaps grew or
--       evidence is new), retryable steps, and steps the latest run did not have; a done step whose inputs did not change is not redone;
--     - plans.fair_order: never-planned first, then due, then early re-plans, each longest-waiting first (country priority and most missing
--       after age);
--     - plans.run_now_supersedes_auto: a university with a Run now inside plans.replan_min_days is not planned automatically.
--     Everything else is as before (automatic switch, open and per-run caps, hidden providers, Firecrawl share waits in the tick).
--   3 public.admin_enrich_plan('run') (md5-guarded edit): Run now on a university with an open automatic plan supersedes it
--     (plans.run_now_supersedes_auto): its steps not started end "superseded by Run now", its running steps' tasks are carried into the
--     Run now plan (monitored there, not started twice), and the automatic run ends cancelled; an open Run now plan is never superseded
--     (the refusal says so). The one-open-plan-per-university index is unchanged. Overview limits show the new settings.
--   4 security.enrich_plan_start_step_v1 and security.enrich_plan_tick_v1 (md5-guarded edits): a run that is not queued or running starts
--     no step (start_step refuses; the tick marks the step cancelled instead of starting it). security.enrich_plan_cancel_steps_v1
--     (v2.15.419; md5-guarded edit) cancels each task as the person who started that task, so a task carried over from a superseded
--     automatic plan is cancelled with the Run now plan (as the run's person, a Pipeline Operator was refused and the task carried on).
--   5 security.enrich_plan_orphans_v1 (read-only) lists plan tasks (admin_jobs with a plan_run, provider onboarding a plan step started)
--     that are still open while no open plan run has them as a running step, by cause. security.enrich_plan_orphans_issue_v1 raises or
--     clears the integration issue enrich_plan_orphans (P1, A7 Scheduling); job integration-validate calls it after its checks.
-- Ships off: plans.replan_on_evidence 0, plans.replan_on_retry 0, plans.fair_order 0 (plans.replan_per_hour stays 0 from v2.15.419).
-- On (fixes): plans.run_now_supersedes_auto 1 (mandate: "Fix interactions between automatic and manual runs"), the cancelled-run guards,
-- the orphan check (read-only; raises an integration issue only).
-- Consumer API: untouched (G3).
-- Replaces: security.enrich_plan_auto_v1, public.admin_enrich_plan, security.enrich_plan_start_step_v1, security.enrich_plan_tick_v1,
--   security.enrich_plan_cancel_steps_v1 (same names; md5-guarded)
-- Retires: nothing (the unconditional plans.redo_days hold stays as the periodic re-plan; early re-plans are added beside it)
-- Nothing is dropped or deleted.

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
  for r in select * from (values ('security.enrich_plan_v1(uuid)', '818ef130484e567c35a7a2cf5a99d7c8'),
                                 ('security.enrich_plan_priority_v1()', '366ff12040bac05d4e494956319a2b76')) v(sig, m) loop
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then raise exception 'live % differs from the definition this change was written against', r.sig; end if;
  end loop;
end $g$;

-- 1. settings (G2) -----------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'plans.replan_on_evidence', 'Enrichment plans: re-plan when new evidence arrives',
  '1: a university planned in the last plans.redo_days days is planned again early when verified evidence arrived after its latest plan finished (a course page read with evidence, or its central pages searched again). Counts against plans.replan_per_hour. 0 switches it off (shipped off, 3 Nov 2026).',
  'number', '0'::jsonb, '0', '1', 'on (1) or off (0)', 130, 'Onboarding', 'security.enrich_plan_auto_v1 (job enrich-plan-auto)',
  'Platform Admin P0 mandate 3 Nov 2026 10:44 §3 Agent A: re-plan when new verified evidence becomes available'),
 ('pipeline', 'plans.replan_on_retry', 'Enrichment plans: re-plan when a failed step can run again',
  '1: a university is planned again early when a step of its latest plan failed for a cause that has cleared (its Firecrawl share has room again, its task ended, or plans.retry_after_hours passed after an error). Counts against plans.replan_per_hour. 0 switches it off (shipped off, 3 Nov 2026).',
  'number', '0'::jsonb, '0', '1', 'on (1) or off (0)', 131, 'Onboarding', 'security.enrich_plan_auto_v1; security.enrich_plan_inputs_v1',
  'Platform Admin P0 mandate 3 Nov 2026 10:44 §3 Agent A: re-plan when a failed step becomes retryable'),
 ('pipeline', 'plans.retry_after_hours', 'Enrichment plans: wait before a failed step is retried',
  'A step that failed, stopped or was cancelled (not with its plan) counts as retryable this many hours after it ended.',
  'number', '6'::jsonb, '1', '168', 'hours', 132, 'Onboarding', 'security.enrich_plan_inputs_v1',
  'Platform Admin P0 mandate 3 Nov 2026 10:44 §3 Agent A: transient errors are retried, not looped'),
 ('pipeline', 'plans.step_retry_max', 'Enrichment plans: most unfinished ends of one step before it is no longer retried early',
  'A step that ended unfinished (failed, stopped, cancelled, timed out or skipped) in this many of the university''s plans in the last plans.redo_days days is not a reason to re-plan early; the periodic re-plan still includes it.',
  'number', '3'::jsonb, '1', '20', 'plans', 133, 'Onboarding', 'security.enrich_plan_inputs_v1',
  'Platform Admin P0 mandate 3 Nov 2026 10:44 §3 Agent A: prevent unbounded rescheduling loops'),
 ('pipeline', 'plans.fair_order', 'Enrichment plans: longest-waiting universities first',
  '1: automatic plans take never-planned universities first, then those due, then early re-plans, each longest-waiting first (country priority and most missing after that). 0 keeps the earlier order (due first, country priority, most missing). Shipped off, 3 Nov 2026.',
  'number', '0'::jsonb, '0', '1', 'on (1) or off (0)', 134, 'Onboarding', 'security.enrich_plan_auto_v1',
  'Platform Admin P0 mandate 3 Nov 2026 10:44 §3 Agent A: prevent plan starvation'),
 ('pipeline', 'plans.run_now_supersedes_auto', 'Enrichment plans: Run now takes over an open automatic plan',
  '1: Run now on a university with an open automatic plan ends that plan (its steps not started are superseded; the tasks its running steps started carry on inside the Run now plan), and a university with a Run now in the last plans.replan_min_days days is not planned automatically. An open Run now plan is never taken over. 0: Run now is refused while any plan is open.',
  'number', '1'::jsonb, '0', '1', 'on (1) or off (0)', 135, 'Onboarding', 'public.admin_enrich_plan run; security.enrich_plan_auto_v1',
  'Platform Admin P0 mandate 3 Nov 2026 10:44 §3 Agent A: fix interactions between automatic and manual runs'),
 ('pipeline', 'plans.orphan_lookback_days', 'Enrichment plans: orphan check looks at plans of the last',
  'The orphan check (integration-validate) looks for provider onboarding started by plan steps in this many days that is still open without a live plan.',
  'number', '30'::jsonb, '1', '365', 'days', 136, 'Onboarding', 'security.enrich_plan_orphans_v1',
  'Platform Admin P0 mandate 3 Nov 2026 10:44 §3 Agent A: no orphaned work'),
 ('pipeline', 'plans.retry_waits_for_change', 'Enrichment plans: failure causes time does not clear',
  'A failed or stopped step whose note contains one of these is not retried because time passed: it waits for new evidence (plans.replan_on_evidence), new gaps, or the periodic re-plan. Measured 3 Nov 2026: 791 of the 1,043 unfinished last steps were adapters stopped for too few pages or nothing ready, and 245 were course-page searches that cannot start (not a search target, no website, every course already has a page).',
  'list', '["too_few_pages", "nothing_ready", "no_website", "not a search target", "no website is recorded", "already has a read page", "Needs a website first"]'::jsonb,
  null, null, 'causes', 137, 'Onboarding', 'security.enrich_plan_inputs_v1',
  'Platform Admin P0 mandate 3 Nov 2026 10:44 §3 Agent A: a failed step is retried only when its cause has cleared')
on conflict (toolset_key, key) do nothing;

-- the latest runs of a university are read per university (the automatic picker and the re-plan inputs)
create index if not exists enrich_plan_runs_provider_created on pipeline.enrich_plan_runs (provider_id, created_at desc);

-- an early re-plan that found nothing to do for these inputs is not looked at again until they change (no hourly re-evaluation, no starvation)
create table if not exists pipeline.enrich_plan_noop (
  provider_id uuid primary key references catalogue.providers(id) on delete cascade,
  fingerprint text not null,
  at timestamptz not null default now());
comment on table pipeline.enrich_plan_noop is 'CF-247 3 Nov 2026 (Platform Admin P0 mandate 10:44 §3 Agent A): one row per university whose latest early re-plan evaluation found no step to run, with the input fingerprint it was evaluated on. security.enrich_plan_auto_v1 does not evaluate that university again until its fingerprint (missing values, verified evidence, central pages, retryable steps) changes, so universities with nothing to do do not hold the hourly slots. Written only by security.enrich_plan_auto_v1; never read by the consumer API.';
revoke all on table pipeline.enrich_plan_noop from public, anon, authenticated;

-- 2. what a re-plan depends on ----------------------------------------------------------------------------------------------------------------
create or replace function security.enrich_plan_inputs_v1(p_provider uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  with a as (select r.id, r.state, r.steps, r.created_at, coalesce(r.finished_at, r.created_at) base from pipeline.enrich_plan_runs r
              where r.provider_id = p_provider order by r.created_at desc limit 1)
  select jsonb_build_object(
    'last_run', a.id, 'last_state', a.state, 'last_at', a.created_at, 'since', a.base,
    'evidence_at', ev.at, 'evidence_new', coalesce(ev.n, 0),
    'central_at', cs.searched_at, 'central_new', coalesce(cs.searched_at > a.base, false),
    'retry_steps', coalesce(rt.steps, '[]'::jsonb))
    from (select 1) one
    left join a on true
    -- verified course pages: bound, read, with stored evidence (index provider_id, read_at)
    left join lateral (select max(g.read_at) at, count(*) filter (where g.read_at > a.base) n from pipeline.coverage_course_pages g
                        where g.provider_id = p_provider and g.evidence_id is not null and g.read_status = 'read') ev on true
    left join lateral (select s.searched_at from pipeline.provider_central_search s where s.provider_id = p_provider and s.state = 'done') cs on true
    -- steps of the latest run (not one a person cancelled) whose failure cause has cleared, each retried a bounded number of times
    left join lateral (select jsonb_agg(distinct s->>'step') steps from jsonb_array_elements(case when a.state = 'cancelled' then '[]'::jsonb else a.steps end) s
       where ((s->>'status' = 'skipped' and coalesce(s->>'note', '') like 'no room in the % share%'
               and security.fc_budget_left_v1(case s->>'group' when 'course_search' then 'course_link_search' when 'scholarships' then 'sch_scrape' when 'reads' then 'scrape' when 'central' then 'central_map' else 'other' end)
                   >= least(coalesce((s->>'est_credits')::numeric, 0), security.fc_setting_num_v1('daily_share_' || (s->>'group'), 0)))
          or (s->>'status' in ('failed', 'stopped', 'cancelled')
              and coalesce((s->>'finished_at')::timestamptz, a.base) <= now() - make_interval(hours => security.pipeline_num_v1('plans.retry_after_hours', 6)::int)
              -- a cause that time does not clear (too few pages, no website, not a search target ...) waits for new evidence or gaps
              and not exists (select 1 from pipeline.platform_toolset_settings w cross join lateral jsonb_array_elements_text(coalesce(w.value, '[]'::jsonb)) k(t)
                               where w.toolset_key = 'pipeline' and w.key = 'plans.retry_waits_for_change' and position(lower(k.t) in lower(coalesce(s->>'note', ''))) > 0))
          or (s->>'status' = 'timed_out'
              and case s->'ref'->>'kind'
                    when 'job' then exists (select 1 from pipeline.admin_jobs j where j.id = nullif(s->'ref'->>'id', '')::uuid and j.state in ('failed', 'cancelled'))
                    when 'onboarding' then exists (select 1 from pipeline.provider_onboarding o where o.id = nullif(s->'ref'->>'id', '')::uuid and o.status in ('stopped', 'cancelled'))
                    else true end))
         and (select count(*) from pipeline.enrich_plan_runs r2 cross join lateral jsonb_array_elements(r2.steps) s2
               where r2.provider_id = p_provider and r2.created_at > now() - make_interval(days => security.pipeline_num_v1('plans.redo_days', 14)::int)
                 and s2->>'step' = s->>'step' and s2->>'status' in ('failed', 'stopped', 'cancelled', 'timed_out', 'skipped'))
             < security.pipeline_num_v1('plans.step_retry_max', 3)) rt on true
$$;
comment on function security.enrich_plan_inputs_v1(uuid) is 'CF-247 3 Nov 2026 (Platform Admin P0 mandate 10:44 §3 Agent A): what an early re-plan of a university depends on, against its latest plan run of any mode: new verified evidence since that run finished (course pages read with stored evidence; central pages searched), and the steps that became retryable (share has room again; failed, stopped or cancelled step after plans.retry_after_hours; timed-out step whose task ended failed or cancelled), each at most plans.step_retry_max unfinished ends in plans.redo_days. Read-only.';
revoke all on function security.enrich_plan_inputs_v1(uuid) from public, anon, authenticated;

-- 3. automatic plans: re-plan on gaps, evidence or retryable steps; fingerprint; done steps kept; fair order ------------------------------
select pg_temp.replace_once('security.enrich_plan_auto_v1()', '2d8944d7624b90cbbefb9925d602c92b', '14d4769267f827736a0d4e2f013c4dad', $d$CREATE OR REPLACE FUNCTION security.enrich_plan_auto_v1()
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
        -- 3 Nov 2026 (Platform Admin P0 mandate 10:44 §3 Agent A): also re-plan on new verified evidence and on steps that can run again
        -- (each 0 = off), longest-waiting first (0 = the earlier order), and leave a university with a recent Run now to it
        v_on_ev boolean := security.pipeline_num_v1('plans.replan_on_evidence', 0) > 0;
        v_on_rt boolean := security.pipeline_num_v1('plans.replan_on_retry', 0) > 0;
        v_fair boolean := security.pipeline_num_v1('plans.fair_order', 0) > 0;
        v_defer boolean := security.pipeline_num_v1('plans.run_now_supersedes_auto', 1) > 0;
        v_re_used int; v_re int := 0; v_is_re boolean; v_in jsonb; v_why text[]; v_fp text; v_same int := 0; v_gaps boolean; v_ev boolean; v_rt jsonb;
begin
  select * into c from pipeline.enrich_plan_control where id = 1;
  if not coalesce(c.auto_enabled, false) then return jsonb_build_object('auto', 'off'); end if;
  select count(*) into v_open from pipeline.enrich_plan_runs where mode = 'auto' and state in ('queued', 'running');
  v_room := least(security.pipeline_num_v1('plans.auto_open_max', 20)::int - v_open, security.pipeline_num_v1('plans.auto_per_run', 10)::int);
  if v_room <= 0 then return jsonb_build_object('auto', 'full', 'open', v_open); end if;
  select count(*) into v_re_used from pipeline.enrich_plan_runs
   where mode = 'auto' and estimate ? 'replan_of' and created_at > now() - make_interval(hours => 1);  -- fixed: the re-plan cap is a count per hour
  for q in select z.* from (
           select x.*, l.id last_id, l.created_at last_at, l.missing_then, a.id any_id, a.created_at any_at, a.steps any_steps, a.estimate->>'fingerprint' any_fp,
                  i.v inputs, i.fp inputs_fp,
                  case when l.id is null then 0 when l.created_at <= now() - make_interval(days => v_redo) then 1 else 2 end tier
             from security.enrich_plan_priority_v1() x
             left join lateral (select r.id, r.created_at, (r.estimate->>'missing')::numeric missing_then from pipeline.enrich_plan_runs r
                                 where r.provider_id = x.provider_id and r.mode = 'auto' order by r.created_at desc limit 1) l on true
             left join lateral (select r.id, r.created_at, r.steps, r.estimate from pipeline.enrich_plan_runs r
                                 where r.provider_id = x.provider_id order by r.created_at desc limit 1) a on true
             -- the evidence and retry inputs, read only for universities held inside plans.redo_days and only when those re-plans are on
             -- the inputs of a university held inside plans.redo_days, read only when early re-plans are on, with their fingerprint
             left join lateral (select i0.v, md5(jsonb_build_object('missing', x.missing, 'evidence_at', i0.v->'evidence_at', 'central_at', i0.v->'central_at',
                                                                    'retry', i0.v->'retry_steps')::text) fp
                                  from (select security.enrich_plan_inputs_v1(x.provider_id) v) i0
                                 where v_re_max > 0 and l.id is not null and l.created_at > now() - make_interval(days => v_redo)
                                   and a.created_at <= now() - make_interval(days => v_re_days)) i on true
            where not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = x.provider_id)  -- 22 Oct 2026 (Platform Admin 11:42): unpublished providers wait; publishing them again brings them back
              and not exists (select 1 from pipeline.enrich_plan_runs r where r.provider_id = x.provider_id and r.state in ('queued', 'running'))
              and (l.id is null
                   or (l.created_at <= now() - make_interval(days => v_redo) and not (v_defer and a.created_at > now() - make_interval(days => v_re_days)))
                   or (v_re_max > 0 and l.created_at <= now() - make_interval(days => v_re_days) and a.created_at <= now() - make_interval(days => v_re_days)
                       and x.missing >= l.missing_then + v_re_rise)
                   or (v_on_ev and ((i.v->>'evidence_new')::int > 0 or (i.v->>'central_new')::boolean))
                   or (v_on_rt and jsonb_array_length(i.v->'retry_steps') > 0))
              -- an early re-plan of unchanged inputs: not the inputs of the latest run, nor inputs already found to need nothing
              and (i.fp is null or (i.fp is distinct from a.estimate->>'fingerprint'
                                    and not exists (select 1 from pipeline.enrich_plan_noop n where n.provider_id = x.provider_id and n.fingerprint = i.fp)))) z
            order by case when v_fair then z.tier else 0 end,
                     (z.last_id is null or z.last_at <= now() - make_interval(days => v_redo)) desc,
                     (z.country in (select jsonb_array_elements_text(coalesce(s.value, '[]'::jsonb)) from pipeline.platform_toolset_settings s
                                     where s.toolset_key = 'pipeline' and s.key = 'plans.priority_countries')) desc,
                     case when v_fair then z.any_at end asc nulls first,
                     z.missing desc, z.best_rank nulls last limit v_room * 3 loop
    exit when v_n >= v_room;
    v_is_re := q.last_id is not null and q.last_at > now() - make_interval(days => v_redo);
    continue when v_is_re and v_re_used + v_re >= v_re_max;
    v_plan := security.enrich_plan_v1(q.provider_id);
    v_steps := (select coalesce(jsonb_agg(x || jsonb_build_object('status', 'pending')), '[]'::jsonb) from jsonb_array_elements(v_plan->'steps') x where not coalesce((x->>'running')::boolean, false));
    v_in := coalesce(q.inputs, security.enrich_plan_inputs_v1(q.provider_id));
    v_why := '{}';
    if v_is_re then
      v_gaps := q.last_at <= now() - make_interval(days => v_re_days) and q.missing >= q.missing_then + v_re_rise;
      v_ev := v_on_ev and ((v_in->>'evidence_new')::int > 0 or (v_in->>'central_new')::boolean);
      v_rt := case when v_on_rt then coalesce(v_in->'retry_steps', '[]'::jsonb) else '[]'::jsonb end;
      if v_gaps then v_why := v_why || 'gaps'::text; end if;
      if v_ev then v_why := v_why || 'evidence'::text; end if;
      if jsonb_array_length(v_rt) > 0 then v_why := v_why || 'retry'::text; end if;
      -- a step the latest run finished, whose inputs did not change, is not done again
      v_steps := (select coalesce(jsonb_agg(x), '[]'::jsonb) from jsonb_array_elements(v_steps) x
                   where v_rt ? (x->>'step')
                      or (v_gaps and x->>'step' in ('pages', 'fields'))
                      or (v_ev and x->>'step' = 'fields')
                      or not exists (select 1 from jsonb_array_elements(coalesce(q.any_steps, '[]'::jsonb)) s where s->>'step' = x->>'step'));
    end if;
    -- the input fingerprint (missing values, verified evidence, central pages, retryable steps)
    v_fp := coalesce(q.inputs_fp, md5(jsonb_build_object('missing', q.missing, 'evidence_at', v_in->'evidence_at', 'central_at', v_in->'central_at',
                                                         'retry', v_in->'retry_steps')::text));
    if jsonb_array_length(v_steps) = 0 or (select bool_and(coalesce((x->>'person')::boolean, false)) from jsonb_array_elements(v_steps) x) then
      if v_is_re then  -- nothing to do for these inputs: not looked at again until they change
        insert into pipeline.enrich_plan_noop as n(provider_id, fingerprint, at) values (q.provider_id, v_fp, now())
        on conflict (provider_id) do update set fingerprint = excluded.fingerprint, at = excluded.at;
        v_same := v_same + 1;
      end if;
      continue;
    end if;
    insert into pipeline.enrich_plan_runs(provider_id, mode, steps, estimate, requested_by, reason)
    values (q.provider_id, 'auto', v_steps, jsonb_build_object('credits', v_plan->'est_credits', 'usd', v_plan->'est_usd', 'missing', q.missing, 'fingerprint', v_fp,
                                                               'inputs', v_in - 'last_state' - 'since')
              || case when v_is_re then jsonb_build_object('replan_of', q.last_id, 'missing_then', q.missing_then, 'replan_why', to_jsonb(v_why), 'after_run', q.any_id) else '{}'::jsonb end, c.owner,
            case when v_is_re then 'Automatic enrichment plan (' || array_to_string(array_remove(array[
                   case when 'gaps' = any (v_why) then 'missing values grew from ' || q.missing_then || ' to ' || q.missing || ' since the last plan' end,
                   case when 'evidence' = any (v_why) then 'new verified evidence since the last plan' end,
                   case when 'retry' = any (v_why) then 'steps that can run again: ' || (select string_agg(t, ', ') from jsonb_array_elements_text(v_rt) t) end], null), '; ') || '): '
                 else 'Automatic enrichment plan (most missing first): ' end || c.reason)
    on conflict do nothing;
    if found then v_n := v_n + 1; if v_is_re then v_re := v_re + 1; end if; end if;
  end loop;
  return jsonb_build_object('auto', 'on', 'started', v_n, 'replanned', v_re, 'nothing_to_do', v_same, 'open', v_open + v_n);
end $function$
$d$);

-- 4. a cancelled run starts nothing ------------------------------------------------------------------------------------------------------------
select pg_temp.edit_once('security.enrich_plan_start_step_v1(uuid,text)', '4e240fab607122eff455ea3c57b5447f', '50b4ea8f613389062efc2116ece62db7', array[
  array[$o$  select * into r from pipeline.enrich_plan_runs where id = p_run;
$o$, $n$  select * into r from pipeline.enrich_plan_runs where id = p_run;
  -- 3 Nov 2026 (Platform Admin P0 mandate 10:44 §3 Agent A): a run that was cancelled, superseded or has finished starts no further step
  if r.id is null or r.state not in ('queued', 'running') then raise exception 'the plan run is %; no further step starts', coalesce(r.state, 'missing'); end if;
$n$]
], array[1]);

select pg_temp.edit_once('security.enrich_plan_tick_v1(uuid)', '0ba546e23715c8d3244e840c49e61e9b', '613782d4a04d3e6ce123c8837339d5e0', array[
  array[$o$      elsif nullif(s->>'blocked', '') is not null and exists$o$, $n$      elsif (select x.state from pipeline.enrich_plan_runs x where x.id = r.id) not in ('queued', 'running') then
        v_state := 'cancelled'; v_note := 'the run is no longer open; the step was not started';  -- 3 Nov 2026 (P0 mandate 10:44 §3 Agent A)
      elsif nullif(s->>'blocked', '') is not null and exists$n$]
], array[1]);

-- 5. Run now and an open automatic plan: one plan per university, the automatic one superseded ------------------------------------------------
select pg_temp.edit_once('public.admin_enrich_plan(text,jsonb)', '0c9d3ec1b7d043e2d9f3ac83f9d99e1d', 'dab650c5adefd9b0b9c006b0c5db4d5d', array[
  array[$o$v_id uuid; v_cc text := upper(nullif(btrim(coalesce(p_args->>'country', '')), ''));$o$,
        $n$v_id uuid; v_cc text := upper(nullif(btrim(coalesce(p_args->>'country', '')), ''));
        v_open jsonb; v_carry jsonb := '[]'::jsonb;$n$],
  array[$o$'replan_min_days', security.pipeline_num_v1('plans.replan_min_days', 2),
$o$, $n$'replan_min_days', security.pipeline_num_v1('plans.replan_min_days', 2),
                                   'replan_on_evidence', security.pipeline_num_v1('plans.replan_on_evidence', 0), 'replan_on_retry', security.pipeline_num_v1('plans.replan_on_retry', 0),
                                   'retry_after_hours', security.pipeline_num_v1('plans.retry_after_hours', 6), 'step_retry_max', security.pipeline_num_v1('plans.step_retry_max', 3),
                                   'fair_order', security.pipeline_num_v1('plans.fair_order', 0), 'run_now_supersedes_auto', security.pipeline_num_v1('plans.run_now_supersedes_auto', 1),
$n$],
  array[$o$    if v_plan->'open_run' is not null and v_plan->>'open_run' <> 'null' then raise exception 'a plan is already running for this university'; end if;
$o$, $n$    -- 3 Nov 2026 (Platform Admin P0 mandate 10:44 §3 Agent A): one plan per university. Run now on a university with an open automatic plan
    -- takes it over (plans.run_now_supersedes_auto): the tasks its running steps started are carried into this run, not started twice
    if v_plan->'open_run' is not null and v_plan->>'open_run' <> 'null' then
      select to_jsonb(r) into v_open from pipeline.enrich_plan_runs r where r.id = (v_plan->'open_run'->>'id')::uuid and r.state in ('queued', 'running') for update;
    end if;
    if v_open is not null and (v_open->>'mode' <> 'auto' or security.pipeline_num_v1('plans.run_now_supersedes_auto', 1) <= 0) then
      raise exception 'a plan is already running for this university%', case when v_open->>'mode' = 'manual'
        then ' (a Run now started ' || to_char((v_open->>'created_at')::timestamptz, 'DD Mon YYYY HH24:MI') || '); wait for it to finish or cancel it first' else '' end;
    end if;
    if v_open is not null then
      v_carry := (select coalesce(jsonb_agg(s || jsonb_build_object('note', 'carried over from the automatic plan this Run now superseded')), '[]'::jsonb)
                    from jsonb_array_elements(v_open->'steps') s where s->>'status' = 'running');
    end if;
$n$],
  array[$o$    if jsonb_array_length(v_steps) = 0 then raise exception 'choose at least one step'; end if;
$o$, $n$    v_steps := (select coalesce(jsonb_agg(x), '[]'::jsonb) from jsonb_array_elements(v_steps) x
                 where not exists (select 1 from jsonb_array_elements(v_carry) k where k->>'step' = x->>'step'));  -- already running: carried, not started again
    if jsonb_array_length(v_steps) + jsonb_array_length(v_carry) = 0 then raise exception 'choose at least one step'; end if;
$n$],
  array[$o$    insert into pipeline.enrich_plan_runs(provider_id, mode, steps, estimate, requested_by, reason)
    values (v_pid, 'manual', v_steps, jsonb_build_object('credits', v_est_c, 'usd', v_est_u), auth.uid(), v_reason) returning id into v_id;
$o$, $n$    if v_open is not null then
      update pipeline.enrich_plan_runs set state = 'cancelled', finished_at = now(), updated_at = now(), reason = reason || ' · superseded by Run now: ' || v_reason,
             steps = (select coalesce(jsonb_agg(case when s->>'status' in ('pending', 'waiting') then s || jsonb_build_object('status', 'cancelled', 'note', 'superseded by Run now', 'finished_at', now())
                                                     when s->>'status' = 'running' then s || jsonb_build_object('status', 'handed_over', 'note', 'task carried into the Run now plan', 'finished_at', now())
                                                     else s end order by o), '[]'::jsonb)
                        from jsonb_array_elements(steps) with ordinality e(s, o))
       where id = (v_open->>'id')::uuid;
    end if;
    insert into pipeline.enrich_plan_runs(provider_id, mode, steps, estimate, requested_by, reason)
    values (v_pid, 'manual', v_steps || v_carry, jsonb_build_object('credits', v_est_c, 'usd', v_est_u) || case when v_open is not null then jsonb_build_object('superseded', v_open->>'id') else '{}'::jsonb end,
            auth.uid(), v_reason) returning id into v_id;
    if v_open is not null then
      update pipeline.admin_jobs set args = args || jsonb_build_object('plan_run', v_id, 'plan_mode', 'manual', 'superseded_run', v_open->>'id')
       where id in (select nullif(k->'ref'->>'id', '')::uuid from jsonb_array_elements(v_carry) k where k->'ref'->>'kind' = 'job');
      insert into pipeline.admin_control_events(area, action, target, detail, actor)
      values ('enrich_plan', 'supersede', v_pid::text, jsonb_build_object('run', v_id, 'superseded', v_open->>'id', 'carried', v_carry, 'reason', v_reason), auth.uid());
    end if;
$n$]
], array[1, 1, 1, 1, 1]);

-- 5b. cancelling a run cancels each task as the person who started that task (a task carried over from a superseded automatic plan was
-- started as that plan's owner; cancelled as the Run now person, a Pipeline Operator would be refused and the task would carry on)
select pg_temp.edit_once('security.enrich_plan_cancel_steps_v1(uuid,text)', '60ec6f01a645eae5e246daa3e721deac', '209ac4e0a45fa307e3efb81f1e541598', array[
  array[$o$        perform set_config('request.jwt.claims', json_build_object('sub', r.requested_by, 'role', 'authenticated')::text, true);$o$,
        $n$        perform set_config('request.jwt.claims', json_build_object('sub', coalesce(case when s->'ref'->>'kind' = 'job' then
                   (select j.requested_by from pipeline.admin_jobs j where j.id = (s->'ref'->>'id')::uuid) end, r.requested_by), 'role', 'authenticated')::text, true);$n$]
], array[1]);

-- 6. no orphaned plan work: a read-only check and its integration issue ---------------------------------------------------------------------------
create or replace function security.enrich_plan_orphans_v1() returns jsonb
language sql stable security definer set search_path = '' as $$
  with live as (select s->'ref'->>'kind' kind, s->'ref'->>'id' id from pipeline.enrich_plan_runs r cross join lateral jsonb_array_elements(r.steps) s
                 where r.state in ('queued', 'running') and s->>'status' = 'running' and nullif(s->'ref'->>'id', '') is not null),
  jobs as (select 'job' kind, j.id, j.kind task, j.state status, j.created_at, nullif(j.args->>'plan_run', '')::uuid run_id from pipeline.admin_jobs j
            where j.state not in ('done', 'failed', 'cancelled') and j.args ? 'plan_run'
              and not exists (select 1 from live where live.kind = 'job' and live.id = j.id::text)),
  onb as (select distinct on (o.id) 'onboarding' kind, o.id, 'provider_onboarding' task, o.status, o.created_at, r.id run_id
            from pipeline.enrich_plan_runs r cross join lateral jsonb_array_elements(r.steps) s
            join pipeline.provider_onboarding o on o.id = nullif(s->'ref'->>'id', '')::uuid
           where s->'ref'->>'kind' = 'onboarding' and r.created_at > now() - make_interval(days => security.pipeline_num_v1('plans.orphan_lookback_days', 30)::int)
             and o.status not in ('done', 'cancelled', 'stopped', 'waiting_admit', 'scholarships')
             and not exists (select 1 from live where live.kind = 'onboarding' and live.id = o.id::text)
           order by o.id, r.created_at desc),
  t as (select t0.*, r.state run_state, r.provider_id,
               (select s->>'status' from jsonb_array_elements(r.steps) s where s->'ref'->>'id' = t0.id::text limit 1) step_status
          from (select * from jobs union all select * from onb) t0 left join pipeline.enrich_plan_runs r on r.id = t0.run_id),
  c as (select t.*, case when t.run_state is null then 'plan run missing' when t.run_state = 'cancelled' then 'plan cancelled'
                         when t.step_status = 'timed_out' then 'step timed out, task carries on' when t.run_state in ('done', 'failed') then 'plan finished'
                         else 'not a running step of its plan' end cause from t)
  select jsonb_build_object('orphans', (select count(*) from c),
    'by_cause', (select coalesce(jsonb_object_agg(cause, n), '{}'::jsonb) from (select cause, count(*) n from c group by cause) z),
    'provider_ids', (select coalesce(jsonb_agg(distinct provider_id), '[]'::jsonb) from c where provider_id is not null),
    'tasks', (select coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'id', id, 'task', task, 'status', status, 'run', run_id, 'run_state', run_state,
                                                            'step_status', step_status, 'cause', cause) order by created_at), '[]'::jsonb)
                from (select * from c order by created_at limit 50) z))
$$;
comment on function security.enrich_plan_orphans_v1() is 'CF-247 3 Nov 2026 (Platform Admin P0 mandate 10:44 §3 Agent A "No orphaned work"): plan tasks still open without a live plan: admin_jobs carrying a plan_run, and provider onboarding a plan step started in plans.orphan_lookback_days, that no queued or running plan run has as a running step; by cause (plan cancelled, plan finished, step timed out, run missing). Read-only.';
revoke all on function security.enrich_plan_orphans_v1() from public, anon, authenticated;

create or replace function security.enrich_plan_orphans_issue_v1() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v jsonb := security.enrich_plan_orphans_v1(); r record;
begin
  if (v->>'orphans')::int > 0 then
    perform security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'enrich_plan_orphans',
      'title', 'Enrichment plan tasks running without a live plan', 'layer', 'Layer 2', 'subsystem', 'pipeline.enrich_plan_runs',
      'failure', (v->>'orphans') || ' task(s) started by plan steps are still open while no open plan run has them (' ||
                 (select string_agg(k || ' ' || n, ', ') from jsonb_each_text(v->'by_cause') e(k, n)) || ')',
      'expected', 'Every task a plan step started belongs to an open plan run, or ends with it (cancel, supersede)',
      'source', 'integration-validate (plan lifecycle)', 'validation_layer', 'V4', 'provider_ids', v->'provider_ids',
      'evidence', jsonb_build_object('orphans', v->'orphans', 'by_cause', v->'by_cause', 'sample', v->'tasks'),
      'severity', 'P1', 'root_cause_class', 'unclassified', 'workstream', 'A7'), 'integration-validate');
    for r in select i.id from pipeline.integration_issues i where i.fingerprint = 'enrich_plan_orphans' and i.status <> 'closed' loop
      perform security.integration_alert_sync_v1(r.id, true);
    end loop;
  else
    for r in select i.id, i.status, i.condition_cleared_at from pipeline.integration_issues i where i.fingerprint = 'enrich_plan_orphans' and i.status <> 'closed' loop
      if r.condition_cleared_at is null then
        update pipeline.integration_issues set condition_cleared_at = now() where id = r.id;
        insert into pipeline.integration_issue_events(issue_id, kind, from_status, to_status, actor, note)
        values (r.id, 'not_observed', r.status, r.status, 'integration-validate', 'condition no longer observed; close after production verification');
      end if;
      perform security.integration_alert_sync_v1(r.id, false);
    end loop;
  end if;
  return jsonb_build_object('enrich_plan_orphans', v->'orphans');
end $$;
comment on function security.enrich_plan_orphans_issue_v1() is 'CF-247 3 Nov 2026 (Platform Admin P0 mandate 10:44 §3 Agent A): job integration-validate raises the integration issue enrich_plan_orphans (P1, A7 Scheduling) while security.enrich_plan_orphans_v1 finds plan tasks without a live plan, and marks it cleared when it no longer does.';
revoke all on function security.enrich_plan_orphans_issue_v1() from public, anon, authenticated;

-- 7. job integration-validate runs the orphan check after its checks (G1: the catalogue says so; the job keeps its active state) ---------------
update pipeline.automation_catalogue set description = description || ' Then the enrichment-plan orphan check (security.enrich_plan_orphans_issue_v1): plan tasks still open without a live plan.'
 where jobname = 'integration-validate' and description not like '%enrich_plan_orphans_issue_v1%';
do $c$
declare v_cmd text := (select command from cron.job where jobname = 'integration-validate');
begin
  if v_cmd is null then raise exception 'job integration-validate not found'; end if;
  if v_cmd not like '%security.enrich_plan_orphans_issue_v1()%' then
    if v_cmd !~ '^select [a-z_.0-9(), ]+$' then raise exception 'integration-validate command is not the select list this change appends to: %', v_cmd; end if;
    perform cron.alter_job((select jobid from cron.job where jobname = 'integration-validate'), command := v_cmd || ', security.enrich_plan_orphans_issue_v1()');
  end if;
end $c$;

-- 8. housekeeping: the register ---------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.enrich_plan_noop', 'Layer 2/3', 'Enrichment', 'Universities whose early re-plan found nothing to do for their current inputs (not re-evaluated until the inputs change)', 'active', '{}', '20261103150000'),
 ('function', 'security.enrich_plan_inputs_v1', 'Layer 2/3', 'Enrichment', 'What an early re-plan depends on: new verified evidence and retryable steps since the latest plan', 'active', '{}', '20261103150000'),
 ('function', 'security.enrich_plan_orphans_v1', 'Layer 2/3', 'Enrichment', 'Plan tasks still open without a live plan (read-only)', 'active', '{}', '20261103150000'),
 ('function', 'security.enrich_plan_orphans_issue_v1', 'Platform', 'Integration queue', 'Raises or clears the integration issue enrich_plan_orphans (job integration-validate)', 'active', '{}', '20261103150000')
on conflict do nothing;
update pipeline.component_register set note = coalesce(note || '. ', '') || '3 Nov 2026 (20261103150000): plan lifecycle (evidence and retry re-plans, fingerprint, supersede, cancelled-run guard)', updated_at = now()
 where kind = 'function' and name in ('security.enrich_plan_auto_v1', 'public.admin_enrich_plan', 'security.enrich_plan_start_step_v1', 'security.enrich_plan_tick_v1',
                                       'security.enrich_plan_cancel_steps_v1')
   and coalesce(note, '') not like '%20261103150000%';

-- 9. post-check --------------------------------------------------------------------------------------------------------------------------------
do $$
begin
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline'
        and key in ('plans.replan_on_evidence', 'plans.replan_on_retry', 'plans.retry_after_hours', 'plans.step_retry_max', 'plans.fair_order',
                    'plans.run_now_supersedes_auto', 'plans.orphan_lookback_days', 'plans.retry_waits_for_change')) <> 8 then
    raise exception 'plan lifecycle post-check: settings missing'; end if;
  if (select command from cron.job where jobname = 'integration-validate') not like '%security.enrich_plan_orphans_issue_v1()%' then
    raise exception 'plan lifecycle post-check: integration-validate does not run the orphan check'; end if;
end $$;

select 'plan lifecycle: evidence and retry re-plans (off), input fingerprint, done steps kept, fair order (off), Run now supersedes automatic, cancelled runs start nothing, orphan check' ok;
