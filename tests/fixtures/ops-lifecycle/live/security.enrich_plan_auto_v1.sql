CREATE OR REPLACE FUNCTION security.enrich_plan_auto_v1()
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
