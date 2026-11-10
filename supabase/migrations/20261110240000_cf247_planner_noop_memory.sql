-- CF-247 F-OPS (IQ-00355, Platform Admin 10 Nov 2026 "Restore autonomous operation"): the hourly automatic enrichment planner (job enrich-plan-auto, security.enrich_plan_auto_v1) looks at the same universities every hour and never reaches the ones it can plan.
--
-- Evidence (project fxcwkweaxjtknorudmwp, SELECT only, 10 Nov 2026). The planner takes up to plans.auto_per_run x 3 candidates (60) in order: never planned or due again first, priority country, most missing values. For each it asks security.enrich_plan_v1 for the plan; when the plan has no step to run (or only steps a person
-- must do) it moves on, and it wrote the memory row pipeline.enrich_plan_noop only for an early re-plan. A never-planned or due university with no step was therefore looked at again EVERY hour, stayed at the head of the order (providers 28828d80 with 97 missing values, 98e29f72 with 64 and four more have steps = []) and filled the 60-place window, so the
-- universities behind them were never reached. Cycle 09:41 UTC created 3 plans (considered 60); cycle 10:41 UTC created 0 (considered 60, open 17, room 20) while 507 universities were eligible (13 never planned).
--
-- What this changes: security.enrich_plan_auto_v1 only. (1) A university whose plan has no step to run is remembered in pipeline.enrich_plan_noop for every candidate, not only for an early re-plan, and counted in nothing_to_do. (2) A candidate that is not an early re-plan (never planned, or due again) and has a memory row newer than the new setting plans.noop_wait_hours
-- (default 24 hours, 1 to 168, Settings > Pipeline settings) is left out of the candidate list; after the wait it is looked at again, so new gaps or evidence are picked up. The meaning of the memory row for an early re-plan (same inputs fingerprint: not planned again until the inputs change) is unchanged: the original test is kept as it was and the new test applies only
-- where the candidate has no inputs fingerprint (i.fp is null). The order, the window (plans.auto_per_run x 3), plans.redo_days, the re-plan cap and every other setting are unchanged.
-- Live definition this change edits (pg_proc.prosrc md5, read 10 Nov 2026), before -> after (the migration stops, and applies nothing, if the live body is neither):
--   security.enrich_plan_auto_v1()   5a3874e777ae649916d61575e2692609 -> f0c95d0bbef3ccac550585185c9784c9
-- Replaces: the body of security.enrich_plan_auto_v1 is replaced in place (md5-guarded); the hourly re-reading of a university that needs nothing is replaced by remembering it for plans.noop_wait_hours
-- Retires: nothing
-- Nothing is dropped or deleted by this migration. One setting is added (plans.noop_wait_hours, idempotent); no plan, existing setting or row is changed by applying it. Forward recovery (restores the previous body byte for byte; the added setting and the memory rows stay): supabase/held/planner_noop_memory_forward_recovery.sql

-- 1 the setting (G2): shown on Settings > Pipeline settings, changed there with a reason
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'plans.noop_wait_hours', 'Plans: wait before a university that needs nothing is looked at again',
  'The hourly planner remembers a university whose plan has no step to run and does not look at it again for this many hours, so it does not hold a place among the universities it looks at each hour while others wait. After the wait it is looked at again and picks up new gaps or new evidence. An early re-plan of unchanged inputs is still held until its inputs change (plans.replan_min_new_gaps, plans.replan_on_evidence).',
  'number', '24'::jsonb, 1, 168, 'hours', 138, 'Onboarding', 'security.enrich_plan_auto_v1 (job enrich-plan-auto)',
  'CF-247 F-OPS IQ-00355, Platform Admin 10 Nov 2026: 24 hours (6 universities with no step held 60 places every hour and no new plan was created)')
on conflict (toolset_key, key) do nothing;
do $cc$ begin
  if exists (select 1 from information_schema.columns where table_schema = 'pipeline' and table_name = 'platform_toolset_settings' and column_name = 'control_class') then
    execute $q$update pipeline.platform_toolset_settings set control_class = 'human' where toolset_key = 'pipeline' and key = 'plans.noop_wait_hours' and control_class is null$q$;
  end if;
end $cc$;

comment on table pipeline.enrich_plan_noop is 'CF-247 3 Nov 2026, widened 10 Nov 2026 (IQ-00355): one row per university whose latest evaluation by the hourly planner found no step to run, with the input fingerprint it was evaluated on. security.enrich_plan_auto_v1 does not evaluate an early re-plan of that university again until its fingerprint (missing values, verified evidence, central pages, retryable steps) changes, and does not evaluate any other candidate (never planned, or due again) for plans.noop_wait_hours, so universities with nothing to do do not hold the hourly places. Written only by security.enrich_plan_auto_v1; never read by the consumer API.';

-- 2 the planner
do $g$
declare v_src text := (select p.prosrc from pg_proc p where p.oid = 'security.enrich_plan_auto_v1()'::regprocedure);
begin
  -- fixed: the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = 'f0c95d0bbef3ccac550585185c9784c9' then raise notice 'security.enrich_plan_auto_v1(): already applied'; return; end if;
  if md5(v_src) <> '5a3874e777ae649916d61575e2692609' then raise exception 'live security.enrich_plan_auto_v1() differs from the definition this change replaces (body md5 %)', md5(v_src); end if;
  execute $ddl$
create or replace function security.enrich_plan_auto_v1()
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
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
        -- 10 Nov 2026 (IQ-00355): a university whose plan has no step to run is remembered (enrich_plan_noop) and not looked at again for this many hours
        v_noop_wait int := security.pipeline_num_v1('plans.noop_wait_hours', 24)::int;
        v_re_used int; v_re int := 0; v_is_re boolean; v_in jsonb; v_why text[]; v_fp text; v_same int := 0; v_gaps boolean; v_ev boolean; v_rt jsonb; v_seen int := 0; v_capped int := 0;
begin
  select * into c from pipeline.enrich_plan_control where id = 1;
  if not coalesce(c.auto_enabled, false) then return security.enrich_plan_auto_note_v1(jsonb_build_object('auto', 'off')); end if;  -- CF-247 ops D: every run recorded
  select count(*) into v_open from pipeline.enrich_plan_runs where mode = 'auto' and state in ('queued', 'running');
  v_room := least(security.pipeline_num_v1('plans.auto_open_max', 20)::int - v_open, security.pipeline_num_v1('plans.auto_per_run', 10)::int);
  if v_room <= 0 then return security.enrich_plan_auto_note_v1(jsonb_build_object('auto', 'full', 'open', v_open), v_room); end if;
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
                                   -- CF-247 ops D (IQ-00064, plans.retry_ignores_min_days): also read once the latest plan has a step that can run
                                   -- again; its own plans.retry_after_hours wait (security.enrich_plan_inputs_v1), the fingerprint and the cap still apply
                                   and (a.created_at <= now() - make_interval(days => v_re_days)
                                        or (v_on_rt and security.pipeline_num_v1('plans.retry_ignores_min_days', 0) >= 1
                                            and exists (select 1 from jsonb_array_elements(coalesce(a.steps, '[]'::jsonb)) s0
                                                         where s0->>'status' in ('failed', 'stopped', 'cancelled', 'timed_out', 'skipped'))))) i on true
            where not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = x.provider_id)  -- 22 Oct 2026 (Platform Admin 11:42): unpublished providers wait; publishing them again brings them back
              and not exists (select 1 from pipeline.enrich_plan_runs r where r.provider_id = x.provider_id and r.state in ('queued', 'running'))
              and (l.id is null
                   or (l.created_at <= now() - make_interval(days => v_redo) and not (v_defer and a.created_at > now() - make_interval(days => v_re_days)))
                   or (v_re_max > 0 and l.created_at <= now() - make_interval(days => v_re_days) and a.created_at <= now() - make_interval(days => v_re_days)
                       and x.missing >= l.missing_then + v_re_rise)
                   or (v_on_ev and ((i.v->>'evidence_new')::int > 0 or (i.v->>'central_new')::boolean)
                       and a.created_at <= now() - make_interval(days => v_re_days))  -- CF-247 ops D: evidence re-plans keep plans.replan_min_days
                   or (v_on_rt and jsonb_array_length(i.v->'retry_steps') > 0))
              -- an early re-plan of unchanged inputs: not the inputs of the latest run, nor inputs already found to need nothing
              and (i.fp is null or (i.fp is distinct from a.estimate->>'fingerprint'
                                    and not exists (select 1 from pipeline.enrich_plan_noop n where n.provider_id = x.provider_id and n.fingerprint = i.fp)))
              -- 10 Nov 2026 (IQ-00355): a university that is not an early re-plan (never planned, or due again) and was found to need nothing is not looked at again
              -- for plans.noop_wait_hours; it must not hold a place in the candidate window every hour while universities that can be planned wait behind it
              and (i.fp is not null or not exists (select 1 from pipeline.enrich_plan_noop n where n.provider_id = x.provider_id and n.at > now() - make_interval(hours => v_noop_wait)))) z
            order by case when v_fair then z.tier else 0 end,
                     (z.last_id is null or z.last_at <= now() - make_interval(days => v_redo)) desc,
                     (z.country in (select jsonb_array_elements_text(coalesce(s.value, '[]'::jsonb)) from pipeline.platform_toolset_settings s
                                     where s.toolset_key = 'pipeline' and s.key = 'plans.priority_countries')) desc,
                     case when v_fair then z.any_at end asc nulls first,
                     z.missing desc, z.best_rank nulls last limit v_room * 3 loop
    exit when v_n >= v_room;
    v_seen := v_seen + 1;
    v_is_re := q.last_id is not null and q.last_at > now() - make_interval(days => v_redo);
    if v_is_re and v_re_used + v_re >= v_re_max then v_capped := v_capped + 1; continue; end if;
    v_plan := security.enrich_plan_v1(q.provider_id);
    v_steps := (select coalesce(jsonb_agg(x || jsonb_build_object('status', 'pending')), '[]'::jsonb) from jsonb_array_elements(v_plan->'steps') x where not coalesce((x->>'running')::boolean, false));
    v_in := coalesce(q.inputs, security.enrich_plan_inputs_v1(q.provider_id));
    v_why := '{}';
    if v_is_re then
      v_gaps := q.last_at <= now() - make_interval(days => v_re_days) and q.missing >= q.missing_then + v_re_rise;
      v_ev := v_on_ev and ((v_in->>'evidence_new')::int > 0 or (v_in->>'central_new')::boolean) and q.any_at <= now() - make_interval(days => v_re_days);
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
      -- nothing to do for these inputs: an early re-plan is not looked at again until they change; any other university not for plans.noop_wait_hours
      -- (10 Nov 2026, IQ-00355: recorded for every university, not only for a re-plan)
      insert into pipeline.enrich_plan_noop as n(provider_id, fingerprint, at) values (q.provider_id, v_fp, now())
      on conflict (provider_id) do update set fingerprint = excluded.fingerprint, at = excluded.at;
      v_same := v_same + 1;
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
  return security.enrich_plan_auto_note_v1(jsonb_build_object('auto', 'on', 'started', v_n, 'replanned', v_re, 'nothing_to_do', v_same, 'open', v_open + v_n,
                                                         'considered', v_seen, 'replan_capped', v_capped), v_room);
end $function$
$ddl$;
  v_src := (select p.prosrc from pg_proc p where p.oid = 'security.enrich_plan_auto_v1()'::regprocedure);
  if md5(v_src) <> 'f0c95d0bbef3ccac550585185c9784c9' then raise exception 'security.enrich_plan_auto_v1() after the replacement has body md5 %, expected f0c95d0bbef3ccac550585185c9784c9', md5(v_src); end if;
end $g$;
