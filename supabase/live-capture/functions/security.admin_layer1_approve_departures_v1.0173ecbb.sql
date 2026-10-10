CREATE OR REPLACE FUNCTION security.admin_layer1_approve_departures_v1(p_run_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline'
AS $function$
declare v_rank int; v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank; if coalesce(v_rank,0)<6 then raise exception 'platform_admin role required' using errcode='42501'; end if;
  if length(trim(coalesce(p_reason,'')))<5 then raise exception 'reason required' using errcode='22023'; end if;
  if not exists (select 1 from pipeline.layer1_run_plans where run_id=p_run_id and departures_status='held') then raise exception 'no held departures for this run' using errcode='55000'; end if;
  v_result:=security.layer1_plan_finish_v1(p_run_id,true,auth.uid());
  update pipeline.layer1_run_queue set result=coalesce(result,'{}'::jsonb)||jsonb_build_object('departures',v_result||jsonb_build_object('reason',left(p_reason,300))),updated_at=now() where id=p_run_id;
  return v_result;
end $function$
