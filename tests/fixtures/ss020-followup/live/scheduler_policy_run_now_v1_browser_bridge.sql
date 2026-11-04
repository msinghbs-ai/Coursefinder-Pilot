CREATE OR REPLACE FUNCTION security.scheduler_policy_run_now_v1_browser_bridge(p_policy_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid := auth.uid(); v_policy pipeline.refresh_policies%rowtype; v_request_id uuid; v_existing boolean := false;
begin
  if v_actor is null or security.current_role_rank() < 4 then raise exception 'pipeline operator role required' using errcode='42501'; end if;
  if length(trim(coalesce(p_reason,''))) < 5 then raise exception 'governance reason required' using errcode='22023'; end if;
  select * into v_policy from pipeline.refresh_policies where id=p_policy_id for update;
  if not found then raise exception 'refresh policy not found' using errcode='22023'; end if;
  if not v_policy.enabled then raise exception 'enable this schedule before running it on demand' using errcode='22023'; end if;
  if v_policy.layer not in (1,2) then raise exception 'Layer 3 on-demand execution requires Evidence/profile-specific control from the Layer 3 workspace' using errcode='22023'; end if;
  if v_policy.source_id is null and v_policy.source_profile_id is null and v_policy.entity_id is null then raise exception 'bounded target required' using errcode='22023'; end if;
  select r.id into v_request_id from pipeline.refresh_requests r where r.status in ('queued','running') and r.requested_layer=v_policy.layer and r.country_code is not distinct from v_policy.country_code and r.source_id is not distinct from v_policy.source_id and r.source_profile_id is not distinct from v_policy.source_profile_id and r.entity_type is not distinct from v_policy.entity_type and r.entity_id is not distinct from v_policy.entity_id order by r.created_at desc limit 1;
  if v_request_id is null then
    insert into pipeline.refresh_requests(requested_layer,country_code,source_id,source_profile_id,entity_type,entity_id,reason,trigger_type,status,requested_by,change_control_ref)
    values(v_policy.layer,v_policy.country_code,v_policy.source_id,v_policy.source_profile_id,v_policy.entity_type,v_policy.entity_id,trim(p_reason),'manual_governed','queued',v_actor,'CF-CHG-20260910-092') returning id into v_request_id;
  else v_existing:=true; end if;
  insert into pipeline.refresh_policy_action_events(policy_id,action,reason,actor_id,change_control_ref,before_state,after_state,refresh_request_id,outcome)
  values(v_policy.id,'run_on_demand',trim(p_reason),v_actor,'CF-CHG-20260910-092',jsonb_build_object('cadence_interval',v_policy.cadence_interval::text,'next_due_at',v_policy.next_due_at,'enabled',v_policy.enabled),jsonb_build_object('policy_unchanged',true,'request_id',v_request_id),v_request_id,case when v_existing then 'existing_active' else 'queued' end);
  return jsonb_build_object('ok',true,'policy_id',v_policy.id,'request_id',v_request_id,'existing_active',v_existing,'action','run_on_demand');
end $function$
;
