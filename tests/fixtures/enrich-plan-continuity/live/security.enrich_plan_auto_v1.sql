CREATE OR REPLACE FUNCTION security.enrich_plan_auto_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c pipeline.enrich_plan_control%rowtype; v_open int; v_room int; v_n int := 0; q record; v_plan jsonb; v_steps jsonb;
begin
  select * into c from pipeline.enrich_plan_control where id = 1;
  if not coalesce(c.auto_enabled, false) then return jsonb_build_object('auto', 'off'); end if;
  select count(*) into v_open from pipeline.enrich_plan_runs where mode = 'auto' and state in ('queued', 'running');
  v_room := least(security.pipeline_num_v1('plans.auto_open_max', 20)::int - v_open, security.pipeline_num_v1('plans.auto_per_run', 10)::int);
  if v_room <= 0 then return jsonb_build_object('auto', 'full', 'open', v_open); end if;
  for q in select x.* from security.enrich_plan_priority_v1() x
            where not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = x.provider_id)  -- 22 Oct 2026 (Platform Admin 11:42): unpublished providers wait; publishing them again brings them back
              and not exists (select 1 from pipeline.enrich_plan_runs r where r.provider_id = x.provider_id
                               and (r.state in ('queued', 'running') or (r.mode = 'auto' and r.created_at > now() - make_interval(days => security.pipeline_num_v1('plans.redo_days', 14)::int))))
            order by (x.country in (select jsonb_array_elements_text(coalesce(s.value, '[]'::jsonb)) from pipeline.platform_toolset_settings s
                                     where s.toolset_key = 'pipeline' and s.key = 'plans.priority_countries')) desc,
                     x.missing desc, x.best_rank nulls last limit v_room * 3 loop
    exit when v_n >= v_room;
    v_plan := security.enrich_plan_v1(q.provider_id);
    v_steps := (select coalesce(jsonb_agg(x || jsonb_build_object('status', 'pending')), '[]'::jsonb) from jsonb_array_elements(v_plan->'steps') x where not coalesce((x->>'running')::boolean, false));
    continue when jsonb_array_length(v_steps) = 0 or (select bool_and(coalesce((x->>'person')::boolean, false)) from jsonb_array_elements(v_steps) x);
    insert into pipeline.enrich_plan_runs(provider_id, mode, steps, estimate, requested_by, reason)
    values (q.provider_id, 'auto', v_steps, jsonb_build_object('credits', v_plan->'est_credits', 'usd', v_plan->'est_usd', 'missing', q.missing), c.owner,
            'Automatic enrichment plan (most missing first): ' || c.reason)
    on conflict do nothing;
    if found then v_n := v_n + 1; end if;
  end loop;
  return jsonb_build_object('auto', 'on', 'started', v_n, 'open', v_open + v_n);
end $function$
