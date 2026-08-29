begin;
create unique index if not exists layer3_interpretations_one_active_entity_task_profile_idx
on pipeline.layer3_interpretations(entity_type,entity_id,task_class,profile_id)
where status in ('reserved','calling');

CREATE OR REPLACE FUNCTION public.layer3_reserve_interpretation_service(p_actor uuid, p_evidence_id uuid, p_entity_type text, p_entity_id uuid, p_task_class text, p_profile_id uuid, p_layer2_state jsonb DEFAULT '{}'::jsonb, p_revalidation_ref text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline'
AS $function$
declare
  v_rank int:=0; v_ev pipeline.evidence_artifacts%rowtype; v_p pipeline.layer3_model_profiles%rowtype;
  v_prev pipeline.layer3_interpretations%rowtype; v_active pipeline.layer3_interpretations%rowtype; v_reason text; v_id uuid; v_selection text;
begin
  if p_actor is null then raise exception 'actor required' using errcode='42501'; end if;
  select coalesce(max(r.rank),0) into v_rank
  from security.user_roles ur join security.roles r on r.code=ur.role_code
  where ur.user_id=p_actor and r.status='active' and (ur.expires_at is null or ur.expires_at>now());
  if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;

  select * into v_ev from pipeline.evidence_artifacts where id=p_evidence_id;
  if not found or v_ev.content_hash is null then raise exception 'governed evidence with content hash required'; end if;

  select * into v_p from pipeline.layer3_model_profiles where id=p_profile_id;
  if not found then raise exception 'model profile not found'; end if;
  if not v_p.enabled or v_p.paused then raise exception 'model profile not executable'; end if;
  if coalesce((v_p.quality_benchmark->>'pass')::boolean,false) is not true then
    raise exception 'model profile quality benchmark not passed';
  end if;
  if not (p_task_class=any(v_p.allowed_task_classes)) then raise exception 'task class not allowed by profile'; end if;

  if coalesce(p_layer2_state->>'status','')='resolved_l2' then
    return jsonb_build_object('call_required',false,'reason','layer2_resolved','evidence_hash',v_ev.content_hash);
  end if;

  perform pg_advisory_xact_lock(hashtext(lower(p_entity_type)||':'||p_entity_id::text||':'||p_task_class||':'||p_profile_id::text));
  select * into v_active
  from pipeline.layer3_interpretations
  where entity_type=lower(p_entity_type) and entity_id=p_entity_id and task_class=p_task_class
    and profile_id=p_profile_id and status in ('reserved','calling')
  order by created_at desc limit 1;
  if found then
    return jsonb_build_object('call_required',false,'reason','in_flight','prior_interpretation_id',v_active.id,'evidence_hash',v_active.evidence_hash);
  end if;

  select * into v_prev
  from pipeline.layer3_interpretations
  where entity_type=lower(p_entity_type) and entity_id=p_entity_id and task_class=p_task_class
    and profile_id=p_profile_id and status in ('validated','low_confidence','no_candidate')
  order by created_at desc limit 1;

  if p_revalidation_ref is not null then
    if length(trim(p_revalidation_ref))<5 then raise exception 'governed revalidation reference required'; end if;
    v_reason:='governed_revalidation';
  elsif found and v_prev.evidence_hash=v_ev.content_hash
        and (v_prev.interpretation_expires_at is null or v_prev.interpretation_expires_at>now()) then
    return jsonb_build_object(
      'call_required',false,'reason','unchanged_evidence',
      'prior_interpretation_id',v_prev.id,'evidence_hash',v_ev.content_hash
    );
  elsif found and v_prev.evidence_hash<>v_ev.content_hash then v_reason:='changed_evidence';
  elsif found and v_prev.interpretation_expires_at is not null and v_prev.interpretation_expires_at<=now() then v_reason:='freshness_expired';
  elsif coalesce(p_layer2_state->>'status','') in ('unresolved','blocked','partial','escalated_l3','layer3_required') then v_reason:='layer2_unresolved';
  else v_reason:='new_evidence';
  end if;

  v_selection:=nullif(p_layer2_state->>'evidence_selection_reason','');

  insert into pipeline.layer3_interpretations(
    evidence_id,evidence_hash,entity_type,entity_id,task_class,profile_id,prompt_profile_version,
    eligibility_reason,revalidation_ref,layer2_state,requested_by,selected_evidence_reason,
    change_control_ref,uat_ref
  ) values(
    p_evidence_id,v_ev.content_hash,lower(p_entity_type),p_entity_id,p_task_class,p_profile_id,
    v_p.prompt_profile_version,v_reason,p_revalidation_ref,coalesce(p_layer2_state,'{}'::jsonb),
    p_actor,v_selection,'CF-CHG-20260829-047','M2.4.3-layer3-operations'
  ) returning id into v_id;

  return jsonb_build_object(
    'call_required',true,'interpretation_id',v_id,'eligibility_reason',v_reason,
    'evidence_hash',v_ev.content_hash,'selected_evidence_reason',v_selection,
    'profile',jsonb_build_object(
      'id',v_p.id,'aggregator_provider',v_p.aggregator_provider,'base_url',v_p.base_url,
      'model_identifier',v_p.model_identifier,'secret_env_key',v_p.secret_env_key,
      'prompt_profile_version',v_p.prompt_profile_version,'prompt_system',v_p.prompt_system,
      'schema',v_p.structured_output_schema,'validators',v_p.deterministic_validators,
      'max_input_tokens',v_p.max_input_tokens,'max_output_tokens',v_p.max_output_tokens,
      'requests_per_minute',v_p.requests_per_minute,'requests_per_day',v_p.requests_per_day,
      'retry_ceiling',v_p.retry_ceiling,'timeout_ms',v_p.timeout_ms,
      'cost_ceiling_usd',v_p.cost_ceiling_usd,'fallback_profile_id',v_p.fallback_profile_id
    )
  );
end $function$;

CREATE OR REPLACE FUNCTION public.layer3_housekeeping_service()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline'
AS $function$
declare v_recovered integer:=0;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  update pipeline.layer3_interpretations
  set status='provider_error',
      validator_result=coalesce(validator_result,'{}'::jsonb)||jsonb_build_object(
        'recovery_state','stale_execution_recovered','recovered_at',now(),
        'reason','Layer 3 reservation/call exceeded the governed 20-minute recovery window'
      ),
      call_completed_at=coalesce(call_completed_at,now())
  where status in ('reserved','calling') and created_at<now()-interval '20 minutes';
  get diagnostics v_recovered=row_count;
  return jsonb_build_object('ok',true,'recovered_stale_executions',v_recovered,'history_deleted',false,'ran_at',now());
end $function$;
revoke all on function public.layer3_housekeeping_service() from public,anon,authenticated;
grant execute on function public.layer3_housekeeping_service() to service_role;

do $$
declare j record;
begin
  for j in select jobid from cron.job where jobname='layer3-operations-housekeeping' loop
    perform cron.unschedule(j.jobid);
  end loop;
  perform cron.schedule('layer3-operations-housekeeping','*/15 * * * *','select public.layer3_housekeeping_service();');
end $$;
commit;
