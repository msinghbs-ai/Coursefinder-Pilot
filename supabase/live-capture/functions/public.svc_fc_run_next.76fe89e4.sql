CREATE OR REPLACE FUNCTION public.svc_fc_run_next(p_run_id uuid, p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_r pipeline.firecrawl_runs%rowtype; v_items jsonb; v_left int; v_budget jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into v_r from pipeline.firecrawl_runs where id = p_run_id for update;
  if v_r.id is null or v_r.status <> 'running' then return jsonb_build_object('run', to_jsonb(v_r) - 'settings', 'items', '[]'::jsonb); end if;
  if v_r.credits_used >= v_r.credits_cap then
    update pipeline.firecrawl_runs set status = 'stopped_credit_cap', finished_at = now() where id = v_r.id;
    return jsonb_build_object('run', jsonb_build_object('id', v_r.id, 'status', 'stopped_credit_cap'), 'items', '[]'::jsonb);
  end if;
  v_budget := security.layer2_provider_budget_status((select p.id from pipeline.layer2_acquisition_providers p where p.provider_key = 'firecrawl'), 5);
  if not coalesce((v_budget->>'allowed')::boolean, false) then
    update pipeline.firecrawl_runs set status = 'stopped_plan_reserve', finished_at = now() where id = v_r.id;
    return jsonb_build_object('run', jsonb_build_object('id', v_r.id, 'status', 'stopped_plan_reserve'), 'items', '[]'::jsonb);
  end if;
  if coalesce(p_limit, 0) <= 0 then
    return jsonb_build_object('run', jsonb_build_object('id', v_r.id, 'use_case', v_r.use_case, 'status', v_r.status, 'settings', v_r.settings, 'credits_left', v_r.credits_cap - v_r.credits_used), 'items', '[]'::jsonb);
  end if;
  with picked as (
    select i.id from pipeline.firecrawl_run_items i
    where i.run_id = v_r.id and (i.state = 'queued' or (i.state = 'leased' and i.leased_until < now()))
    order by i.state desc, i.provider_id, i.id limit greatest(1, least(coalesce(p_limit, 40), 200)) for update skip locked
  ), upd as (
    update pipeline.firecrawl_run_items i set state = 'leased', leased_until = now() + interval '5 minutes' from picked where i.id = picked.id
    returning i.id, i.course_id, i.provider_id, i.country, i.url, i.input, i.result
  )
  select coalesce(jsonb_agg(to_jsonb(upd)), '[]'::jsonb) into v_items from upd;
  if v_r.use_case = 'read_page' then
    update pipeline.coverage_course_pages pg set leased_until = now() + interval '5 minutes' where pg.course_id in (select (e->>'course_id')::uuid from jsonb_array_elements(v_items) e);
  end if;
  if jsonb_array_length(v_items) = 0 then
    select count(*) into v_left from pipeline.firecrawl_run_items i where i.run_id = v_r.id and i.state <> 'done';
    if v_left = 0 then update pipeline.firecrawl_runs set status = 'done', finished_at = now() where id = v_r.id; end if;
  end if;
  update pipeline.firecrawl_runs set last_call_at = now() where id = v_r.id;
  return jsonb_build_object('run', jsonb_build_object('id', v_r.id, 'use_case', v_r.use_case, 'status', v_r.status, 'settings', v_r.settings, 'credits_left', v_r.credits_cap - v_r.credits_used), 'items', v_items);
end $function$
