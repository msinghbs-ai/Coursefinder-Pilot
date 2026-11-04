CREATE OR REPLACE FUNCTION security.scheduler_policy_edit_v1_browser_bridge(p_policy_id uuid, p_expected_updated_at timestamp with time zone, p_cadence_days integer, p_next_due_at timestamp with time zone, p_enabled boolean, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid();
  v_policy pipeline.refresh_policies%rowtype;
  v_before jsonb;
begin
  if v_actor is null or security.current_role_rank() < 4 then raise exception 'pipeline operator role required' using errcode='42501'; end if;
  if length(trim(coalesce(p_reason,''))) < 5 then raise exception 'governance reason required' using errcode='22023'; end if;
  if p_expected_updated_at is null then raise exception 'expected policy version required' using errcode='22023'; end if;
  if p_cadence_days is null or p_cadence_days < 1 or p_cadence_days > 3650 then raise exception 'cadence days must be 1..3650' using errcode='22023'; end if;
  if p_next_due_at is null then raise exception 'next run required' using errcode='22023'; end if;
  select * into v_policy from pipeline.refresh_policies where id=p_policy_id for update;
  if not found then raise exception 'refresh policy not found' using errcode='22023'; end if;
  if v_policy.updated_at is distinct from p_expected_updated_at then raise exception 'schedule changed since it was opened; refresh and try again' using errcode='40001'; end if;
  if v_policy.layer not in (1,2,3) then raise exception 'only Layer 1..3 schedules are editable here' using errcode='22023'; end if;
  if v_policy.freshness_class='event-driven' then raise exception 'event-driven policy has no recurring schedule' using errcode='22023'; end if;
  if v_policy.source_id is null and v_policy.source_profile_id is null and v_policy.entity_id is null then raise exception 'bounded target required' using errcode='22023'; end if;
  v_before:=jsonb_build_object('cadence_interval',v_policy.cadence_interval::text,'next_due_at',v_policy.next_due_at,'enabled',v_policy.enabled,'updated_at',v_policy.updated_at,'change_control_ref',v_policy.change_control_ref);
  update pipeline.refresh_policies set cadence_interval=make_interval(days=>p_cadence_days),next_due_at=p_next_due_at,enabled=p_enabled,change_control_ref='CF-CHG-20260910-092',updated_at=now() where id=v_policy.id;
  insert into pipeline.refresh_policy_action_events(policy_id,action,reason,actor_id,change_control_ref,before_state,after_state,outcome)
  values(v_policy.id,'edit_schedule',trim(p_reason),v_actor,'CF-CHG-20260910-092',v_before,jsonb_build_object('cadence_days',p_cadence_days,'next_due_at',p_next_due_at,'enabled',p_enabled,'change_control_ref','CF-CHG-20260910-092'),'applied');
  return jsonb_build_object('ok',true,'policy_id',v_policy.id,'action','edit_schedule');
end
$function$
;
