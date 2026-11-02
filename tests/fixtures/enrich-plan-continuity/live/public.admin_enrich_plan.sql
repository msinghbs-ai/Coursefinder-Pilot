CREATE OR REPLACE FUNCTION public.admin_enrich_plan(p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_pid uuid := nullif(p_args->>'provider', '')::uuid; v_reason text := btrim(coalesce(p_args->>'reason', ''));
        v_plan jsonb; v_steps jsonb; v_est_c numeric; v_est_u numeric; v_left_c numeric; v_left_u numeric; v_id uuid; v_cc text := upper(nullif(btrim(coalesce(p_args->>'country', '')), ''));
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  v_left_c := greatest(0, security.fc_setting_num_v1('ondemand_credits_per_day', 2000) - security.fc_on_demand_today_v1());
  v_left_u := greatest(0, coalesce((security.toolset_setting('openrouter', 'ondemand_usd_per_day'))::text::numeric, 0)
                          - coalesce((select sum(coalesce((r.actual->>'usd')::numeric, (r.estimate->>'usd')::numeric, 0)) from pipeline.enrich_plan_runs r
                                       where r.mode = 'manual' and r.created_at >= security.fc_day_start_v1()), 0));
  if p_action = 'overview' then
    return jsonb_build_object(
      'auto', (select jsonb_build_object('enabled', c.auto_enabled, 'reason', c.reason, 'at', c.updated_at) from pipeline.enrich_plan_control c where c.id = 1),
      'open', jsonb_build_object('auto', (select count(*) from pipeline.enrich_plan_runs where mode = 'auto' and state in ('queued', 'running')),
                                 'manual', (select count(*) from pipeline.enrich_plan_runs where mode = 'manual' and state in ('queued', 'running'))),
      'on_demand', jsonb_build_object('credits', security.fc_setting_num_v1('ondemand_credits_per_day', 2000), 'credits_used', security.fc_on_demand_today_v1(), 'credits_left', v_left_c,
                                      'usd', (security.toolset_setting('openrouter', 'ondemand_usd_per_day'))::text::numeric, 'usd_left', v_left_u),
      'shares', (select jsonb_object_agg(g, jsonb_build_object('share', security.fc_setting_num_v1('daily_share_' || g, 0), 'left', security.fc_budget_left_v1(pp)))
                   from (values ('course_search', 'course_link_search'), ('reads', 'scrape'), ('central', 'central_map'), ('scholarships', 'sch_scrape'), ('other', 'other')) v(g, pp)),
      'limits', jsonb_build_object('open_max', security.pipeline_num_v1('plans.auto_open_max', 20), 'per_run', security.pipeline_num_v1('plans.auto_per_run', 10),
                                   'redo_days', security.pipeline_num_v1('plans.redo_days', 14), 'wait_hours', security.pipeline_num_v1('plans.step_wait_hours', 48)),
      'needs_person', (select coalesce(jsonb_agg(jsonb_build_object('run', r.id, 'provider_id', r.provider_id, 'name', coalesce(p.display_name, p.canonical_name),
                                  'mode', r.mode, 'note', r.needs_person, 'finished_at', r.finished_at) order by r.finished_at desc), '[]'::jsonb)
                         from pipeline.enrich_plan_runs r join catalogue.providers p on p.id = r.provider_id
                        where r.state = 'done' and r.needs_person is not null
                          and not exists (select 1 from pipeline.enrich_plan_runs r2 where r2.provider_id = r.provider_id and r2.created_at > r.created_at)),
      'unit_costs', security.enrich_unit_costs_v1(), 'can_run', v_rank >= 4, 'can_manage', v_rank >= 6);
  elsif p_action = 'list' then
    return jsonb_build_object('items', (select coalesce(jsonb_agg(z order by z.missing desc, z.best_rank nulls last), '[]'::jsonb) from (
      select x.provider_id, x.name, x.country, x.courses, x.missing, x.best_rank,
             (select jsonb_build_object('id', r.id, 'mode', r.mode, 'state', r.state, 'created_at', r.created_at, 'finished_at', r.finished_at, 'needs_person', r.needs_person,
                       'step', (select e->>'label' from jsonb_array_elements(r.steps) e where e->>'status' in ('pending', 'waiting', 'running') limit 1))
                from pipeline.enrich_plan_runs r where r.provider_id = x.provider_id order by r.created_at desc limit 1) last_run
        from security.enrich_plan_priority_v1() x
       where (v_cc is null or x.country = v_cc) and (coalesce(p_args->>'query', '') = '' or x.name ilike '%' || (p_args->>'query') || '%')
       order by x.missing desc, x.best_rank nulls last
       limit least(greatest(coalesce((p_args->>'limit')::int, 50), 1), 200) offset greatest(coalesce((p_args->>'offset')::int, 0), 0)) z));
  elsif p_action = 'plan' then
    if v_pid is null then raise exception 'choose a university'; end if;
    return security.enrich_plan_v1(v_pid) || jsonb_build_object('on_demand', jsonb_build_object('credits_left', v_left_c, 'usd_left', v_left_u),
      'runs', (select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at desc), '[]'::jsonb) from (select * from pipeline.enrich_plan_runs where provider_id = v_pid order by created_at desc limit 10) r),
      'can_run', v_rank >= 4);
  elsif p_action = 'run' then
    if v_rank < 4 then raise exception 'Pipeline Operator role or above required' using errcode = '42501'; end if;
    if length(v_reason) < 4 then raise exception 'give a reason (kept with the run)'; end if;
    v_plan := security.enrich_plan_v1(v_pid);
    if v_plan is null then raise exception 'choose a university'; end if;
    if v_plan->'open_run' is not null and v_plan->>'open_run' <> 'null' then raise exception 'a plan is already running for this university'; end if;
    v_steps := (select coalesce(jsonb_agg(x || jsonb_build_object('status', 'pending')), '[]'::jsonb) from jsonb_array_elements(v_plan->'steps') x
                 where x->>'step' in (select jsonb_array_elements_text(coalesce(p_args->'steps', '[]'::jsonb))));
    if jsonb_array_length(v_steps) = 0 then raise exception 'choose at least one step'; end if;
    select coalesce(sum((x->>'est_credits')::numeric), 0), coalesce(sum((x->>'est_usd')::numeric), 0) into v_est_c, v_est_u from jsonb_array_elements(v_steps) x;
    if v_est_c > v_left_c then raise exception 'the estimate (% credits) is more than the on-demand allowance left today (% credits); lower the steps, or raise the allowance on Models & services › Toolsets & limits', round(v_est_c), round(v_left_c); end if;
    if v_est_u > v_left_u then raise exception 'the estimate (US$%) is more than the on-demand AI allowance left today (US$%)', round(v_est_u, 2), round(v_left_u, 2); end if;
    insert into pipeline.enrich_plan_runs(provider_id, mode, steps, estimate, requested_by, reason)
    values (v_pid, 'manual', v_steps, jsonb_build_object('credits', v_est_c, 'usd', v_est_u), auth.uid(), v_reason) returning id into v_id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('enrich_plan', 'run', v_pid::text, jsonb_build_object('run', v_id, 'steps', p_args->'steps', 'estimate_credits', v_est_c, 'estimate_usd', v_est_u, 'reason', v_reason), auth.uid());
    perform security.enrich_plan_tick_v1(v_id);  -- the first step starts now (this run only)
    return jsonb_build_object('run_id', v_id, 'estimate', jsonb_build_object('credits', v_est_c, 'usd', v_est_u));
  elsif p_action = 'cancel' then
    if v_rank < 4 then raise exception 'Pipeline Operator role or above required' using errcode = '42501'; end if;
    update pipeline.enrich_plan_runs set state = 'cancelled', finished_at = now(), updated_at = now(), reason = reason || ' · cancelled: ' || coalesce(nullif(v_reason, ''), 'by a person')
     where id = (p_args->>'run_id')::uuid and state in ('queued', 'running');
    return jsonb_build_object('cancelled', found);
  elsif p_action = 'control' then
    if v_rank < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
    if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
    update pipeline.enrich_plan_control set auto_enabled = coalesce((p_args->>'auto')::boolean, auto_enabled), owner = auth.uid(), reason = v_reason, updated_at = now() where id = 1;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('enrich_plan', case when (p_args->>'auto')::boolean then 'auto_on' else 'auto_off' end, 'enrich-plan-auto', jsonb_build_object('reason', v_reason), auth.uid());
    return public.admin_enrich_plan('overview', '{}'::jsonb);
  end if;
  raise exception 'unknown action %', p_action using errcode = '22023';
end $function$
