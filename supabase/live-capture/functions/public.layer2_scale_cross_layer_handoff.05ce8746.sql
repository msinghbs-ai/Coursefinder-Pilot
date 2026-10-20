CREATE OR REPLACE FUNCTION public.layer2_scale_cross_layer_handoff(p_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'catalogue', 'ref'
AS $function$
declare
  v_l3 integer:=0;
  v_l4 integer:=0;
  v_l3_profile uuid;
  v_l3_ready boolean:=false;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;
  if not exists(select 1 from pipeline.layer2_scale_qualification_runs where id=p_run_id) then
    raise exception 'qualification run not found' using errcode='22023';
  end if;

  select p.id into v_l3_profile
  from pipeline.layer3_model_profiles p
  where p.code='openrouter-source-pattern-v1'
    and p.enabled and not p.paused
    and coalesce((p.quality_benchmark->>'pass')::boolean,false)
  limit 1;
  v_l3_ready:=v_l3_profile is not null;

  with targets as (
    select distinct
      qi.provider_id,
      qi.evidence_id,
      nullif(qi.outcome->>'qualification_source_id','')::uuid source_id,
      nullif(qi.outcome->>'qualification_profile_id','')::uuid source_profile_id,
      co.iso_alpha2::text country_code,
      qr.requested_by,
      'A23-SOURCE-PATTERN:'||p_run_id::text||':'||qi.provider_id::text revalidation_ref
    from pipeline.layer2_scale_qualification_items qi
    join pipeline.layer2_scale_qualification_runs qr on qr.id=qi.run_id
    join ref.countries co on co.id=qr.country_id
    where qi.run_id=p_run_id
      and qi.status='layer3_required'
      and qi.evidence_id is not null
  ), ins as (
    insert into pipeline.refresh_requests(
      requested_layer,country_code,source_id,source_profile_id,entity_type,entity_id,
      evidence_id,layer3_profile_id,revalidation_ref,reason,trigger_type,status,
      requested_by,change_control_ref,schedule_error
    )
    select
      3,t.country_code,t.source_id,t.source_profile_id,'provider',t.provider_id,
      t.evidence_id,v_l3_profile,t.revalidation_ref,
      'Interpret first-party Course discovery/source pattern from governed Layer 2 Evidence. Do not infer or change Layer 1 identity. Return any candidate to Layer 2 strict identity control before promotion.',
      'manual_governed','cancelled',
      t.requested_by,'CF-CHG-20260830-048',
      'retired (Decision 213): course pages are found by the course-link search'
    from targets t
    where not exists(
      select 1 from pipeline.refresh_requests rr
      where rr.revalidation_ref=t.revalidation_ref
    )
    returning 1
  )
  select count(*) into v_l3 from ins;

  with targets as (
    select distinct
      qi.provider_id,
      co.iso_alpha2::text country_code,
      qr.requested_by,
      coalesce(qi.outcome->>'reason',
        case qi.status when 'blocked' then 'qualification_blocked'
                       when 'layer4_required' then 'layer4_resolution_required'
                       else 'missing_or_invalid_first_party_source_seed' end) reason,
      'A23-SOURCE-RESOLUTION:'||p_run_id::text||':'||qi.provider_id::text revalidation_ref
    from pipeline.layer2_scale_qualification_items qi
    join pipeline.layer2_scale_qualification_runs qr on qr.id=qi.run_id
    join ref.countries co on co.id=qr.country_id
    where qi.run_id=p_run_id
      and qi.status in ('source_limited','blocked','layer4_required')
  ), ins as (
    insert into pipeline.refresh_requests(
      requested_layer,country_code,entity_type,entity_id,revalidation_ref,
      reason,trigger_type,status,requested_by,change_control_ref,schedule_error
    )
    select
      4,t.country_code,'provider',t.provider_id,t.revalidation_ref,
      'Resolve/verify the first-party Provider Course source before Layer 2 qualification can continue. Reason: '||t.reason,
      'manual_governed','queued',t.requested_by,'CF-CHG-20260830-048',
      'provider_source_resolution_required'
    from targets t
    where not exists(
      select 1 from pipeline.refresh_requests rr
      where rr.revalidation_ref=t.revalidation_ref
    )
    returning 1
  )
  select count(*) into v_l4 from ins;

  update pipeline.layer2_scale_qualification_runs
  set result_summary=coalesce(result_summary,'{}'::jsonb)||jsonb_build_object(
    'cross_layer_handoff_at',now(),
    'layer3_source_pattern_requests_created',v_l3,
    'layer3_profile_id',v_l3_profile,
    'layer3_execution_state',case when v_l3_ready then 'queued_for_governed_operator_execution' else 'blocked_profile_not_executable' end,
    'layer4_source_resolution_requests_created',v_l4,
    'canonical_mutation_authorised',false,
    'search_mutation_authorised',false,
    'publication_mutation_authorised',false
  )
  where id=p_run_id;

  return jsonb_build_object(
    'ok',true,'run_id',p_run_id,
    'layer3_source_pattern_requests_created',v_l3,
    'layer3_profile_id',v_l3_profile,
    'layer3_execution_state',case when v_l3_ready then 'queued_for_governed_operator_execution' else 'blocked_profile_not_executable' end,
    'layer4_source_resolution_requests_created',v_l4,
    'canonical_mutation_authorised',false,
    'search_mutation_authorised',false,
    'publication_mutation_authorised',false
  );
end
$function$
