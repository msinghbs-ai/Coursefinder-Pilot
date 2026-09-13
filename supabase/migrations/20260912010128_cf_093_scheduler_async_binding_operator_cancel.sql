begin;

create or replace function security.scheduler_workflow_async_binding_cancel_v1(
  p_actor uuid,
  p_preview_token uuid,
  p_reason text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_binding pipeline.scheduler_workflow_async_bindings%rowtype;
  v_reason text:=trim(coalesce(p_reason,''));
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;
  if p_actor is null or p_preview_token is null then
    raise exception 'actor and preview token required' using errcode='22023';
  end if;
  if length(v_reason)<5 then
    raise exception 'cancellation reason required' using errcode='22023';
  end if;

  select * into v_binding
  from pipeline.scheduler_workflow_async_bindings b
  where b.preview_token=p_preview_token
    and b.actor_id=p_actor
  for update;

  if not found then
    raise exception 'scheduler async binding not found for actor' using errcode='22023';
  end if;

  if v_binding.status='cancelled' then
    return jsonb_build_object(
      'ok',true,
      'preview_token',p_preview_token,
      'profile_id',v_binding.profile_id,
      'status','cancelled',
      'idempotent_replay',true
    );
  end if;

  if v_binding.status not in ('prepared','active') then
    raise exception 'scheduler async binding cannot be cancelled from status %',v_binding.status using errcode='22023';
  end if;

  update pipeline.scheduler_workflow_async_bindings
  set status='cancelled',
      execution_expires_at=least(coalesce(execution_expires_at,now()),now())
  where preview_token=p_preview_token
    and profile_id=v_binding.profile_id;

  update pipeline.jobs
  set payload=coalesce(payload,'{}'::jsonb)||jsonb_build_object(
    'async_binding_cancelled_at',now(),
    'async_binding_cancelled_by',p_actor,
    'async_binding_cancellation_reason',v_reason,
    'change_control_ref','CF-CHG-20260910-093'
  )
  where id=p_preview_token
    and job_type='scheduler_workflow_preview';

  return jsonb_build_object(
    'ok',true,
    'preview_token',p_preview_token,
    'profile_id',v_binding.profile_id,
    'status','cancelled',
    'idempotent_replay',false
  );
end
$function$;

revoke all on function security.scheduler_workflow_async_binding_cancel_v1(uuid,uuid,text) from public,anon,authenticated;
grant execute on function security.scheduler_workflow_async_binding_cancel_v1(uuid,uuid,text) to service_role;

commit;
