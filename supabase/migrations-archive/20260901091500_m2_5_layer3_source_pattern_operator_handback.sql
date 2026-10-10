-- CF-CHG-20260901-054
-- M2.5 source-pattern operator execution and deterministic Layer 2 hand-back.
-- Source-pattern remains manual_governed. No autonomous Layer 3 execution.
-- Validated Layer 3 URL candidates cannot qualify a Provider directly and cannot write canonical/Search/Publication data.

create or replace function security.layer3_source_pattern_queue_impl(p_limit integer default 100)
returns jsonb
language plpgsql
stable security definer
set search_path='pg_catalog','security','pipeline','catalogue','auth'
as $function$
begin
  if auth.uid() is null or security.current_role_rank()<3 then
    raise exception 'curator role required' using errcode='42501';
  end if;
  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.created_at)
    from (
      select rr.id request_id,rr.status,rr.country_code,rr.entity_type,rr.entity_id,
             p.display_name provider_name,rr.source_id,rr.source_profile_id,
             rr.evidence_id,e.evidence_type,e.source_url,e.mime_type,e.content_hash,e.captured_at,
             rr.layer3_profile_id,mp.code layer3_profile_code,mp.model_identifier,
             rr.revalidation_ref,rr.reason,rr.trigger_type,rr.schedule_error,
             rr.created_at,rr.dispatched_at
      from pipeline.refresh_requests rr
      join catalogue.providers p on p.id=rr.entity_id and rr.entity_type='provider'
      join pipeline.evidence_artifacts e on e.id=rr.evidence_id
      join pipeline.layer3_model_profiles mp on mp.id=rr.layer3_profile_id
      where rr.requested_layer=3
        and rr.revalidation_ref like 'A23-SOURCE-PATTERN:%'
        and rr.status in('queued','failed','blocked')
      order by rr.created_at
      limit least(greatest(coalesce(p_limit,100),1),250)
    ) x
  ),'[]'::jsonb);
end
$function$;

create or replace function public.layer3_source_pattern_queue(p_limit integer default 100)
returns jsonb
language sql
stable
set search_path='pg_catalog','security'
as $function$
  select security.layer3_source_pattern_queue_impl(p_limit)
$function$;

revoke all on function public.layer3_source_pattern_queue(integer) from public,anon;
grant execute on function public.layer3_source_pattern_queue(integer) to authenticated,service_role;

create or replace function public.layer3_source_pattern_request_context_service(p_actor uuid,p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','pipeline','security','catalogue'
as $function$
declare
  v_rank integer:=0;
  r pipeline.refresh_requests%rowtype;
  e pipeline.evidence_artifacts%rowtype;
  mp pipeline.layer3_model_profiles%rowtype;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  if p_actor is null then raise exception 'actor required' using errcode='42501'; end if;
  select coalesce(max(ro.rank),0) into v_rank
  from security.user_roles ur join security.roles ro on ro.code=ur.role_code
  where ur.user_id=p_actor and ro.status='active' and (ur.expires_at is null or ur.expires_at>now());
  if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;

  select * into r from pipeline.refresh_requests where id=p_request_id for update;
  if not found then raise exception 'source-pattern request not found' using errcode='22023'; end if;
  if r.requested_layer<>3 or r.entity_type<>'provider' or r.revalidation_ref not like 'A23-SOURCE-PATTERN:%' then
    raise exception 'source-pattern request contract mismatch' using errcode='22023';
  end if;
  if r.status='completed' then
    return jsonb_build_object('ok',true,'executable',false,'reason','request_completed','request_id',r.id);
  end if;
  if r.status not in('queued','failed','blocked') then
    return jsonb_build_object('ok',true,'executable',false,'reason','request_'||r.status,'request_id',r.id);
  end if;
  if r.evidence_id is null or r.layer3_profile_id is null or r.source_profile_id is null then
    raise exception 'source-pattern request lineage incomplete' using errcode='22023';
  end if;

  select * into e from pipeline.evidence_artifacts where id=r.evidence_id;
  if not found or e.content_hash is null or e.storage_path is null then raise exception 'governed retained Evidence required' using errcode='22023'; end if;
  select * into mp from pipeline.layer3_model_profiles where id=r.layer3_profile_id;
  if not found or not mp.enabled or mp.paused or coalesce((mp.quality_benchmark->>'pass')::boolean,false) is not true
     or not ('source_pattern'=any(mp.allowed_task_classes)) then
    raise exception 'source-pattern model profile not executable' using errcode='22023';
  end if;
  if not exists(
    select 1 from pipeline.layer2_source_profiles lp
    join pipeline.sources s on s.id=lp.source_id
    where lp.id=r.source_profile_id and s.provider_id=r.entity_id
      and lp.domain='course_facts' and lp.enabled and not lp.paused
  ) then raise exception 'source-pattern Layer 2 profile mismatch' using errcode='22023'; end if;

  update pipeline.refresh_requests set status='queued',schedule_error=null where id=r.id and status in('failed','blocked');

  return jsonb_build_object(
    'ok',true,'executable',true,'request_id',r.id,
    'evidence_id',r.evidence_id,'entity_type','provider','entity_id',r.entity_id,
    'task_class','source_pattern','profile_id',r.layer3_profile_id,
    'revalidation_ref',r.revalidation_ref,'source_profile_id',r.source_profile_id,
    'source_id',r.source_id,'evidence_source_url',e.source_url,'evidence_hash',e.content_hash,
    'layer2_state',jsonb_build_object(
      'status','layer3_required',
      'evidence_selection_reason','governed_source_pattern_refresh_request',
      'source_pattern_request_id',r.id,
      'source_profile_id',r.source_profile_id
    )
  );
end
$function$;

revoke all on function public.layer3_source_pattern_request_context_service(uuid,uuid) from public,anon,authenticated;
grant execute on function public.layer3_source_pattern_request_context_service(uuid,uuid) to service_role;

create or replace function public.layer3_source_pattern_request_error_service(p_request_id uuid,p_error text)
returns void
language plpgsql
security definer
set search_path='pg_catalog','pipeline'
as $function$
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  update pipeline.refresh_requests
  set status='queued',schedule_error=left(coalesce(p_error,'source_pattern_execution_failed'),1200),dispatched_at=now()
  where id=p_request_id and requested_layer=3 and revalidation_ref like 'A23-SOURCE-PATTERN:%' and status<>'completed';
end
$function$;

revoke all on function public.layer3_source_pattern_request_error_service(uuid,text) from public,anon,authenticated;
grant execute on function public.layer3_source_pattern_request_error_service(uuid,text) to service_role;

CREATE OR REPLACE FUNCTION public.layer3_complete_interpretation_service(p_interpretation_id uuid, p_raw_result jsonb, p_candidate_value jsonb, p_confidence numeric, p_rationale text, p_evidence_quotes jsonb, p_validator_result jsonb, p_valid boolean, p_response_model text, p_input_tokens integer, p_output_tokens integer, p_estimated_cost_usd numeric, p_expiry timestamp with time zone, p_external_call_count integer, p_call_latency_ms integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'catalogue'
AS $function$
declare
  v_i pipeline.layer3_interpretations%rowtype; v_review uuid; v_before jsonb;
  v_threshold numeric:=0; v_low_confidence boolean:=false; v_status text; v_trace jsonb:='[]'::jsonb;
  v_fallback uuid;
begin
  select * into v_i from pipeline.layer3_interpretations where id=p_interpretation_id for update;
  if not found then raise exception 'interpretation not found'; end if;
  if v_i.status not in ('reserved','calling') then raise exception 'interpretation is not completable'; end if;
  if coalesce(p_estimated_cost_usd,0)<0 then raise exception 'invalid cost'; end if;
  if p_external_call_count is not null and p_external_call_count<0 then raise exception 'invalid external call count'; end if;
  if p_call_latency_ms is not null and p_call_latency_ms<0 then raise exception 'invalid call latency'; end if;

  select coalesce((deterministic_validators->>'review_confidence_min')::numeric,0)
    into v_threshold from pipeline.layer3_model_profiles where id=v_i.profile_id;
  v_low_confidence:=p_valid and p_candidate_value is not null and p_candidate_value<>'null'::jsonb
                    and coalesce(p_confidence,0)<v_threshold;
  v_status:=case
    when not p_valid then 'rejected_validation'
    when p_candidate_value is null or p_candidate_value='null'::jsonb then 'no_candidate'
    when v_low_confidence then 'low_confidence'
    else 'validated'
  end;
  v_trace:=coalesce(p_raw_result->'_coursefinder_trace','[]'::jsonb);
  begin
    v_fallback:=nullif(p_raw_result->'_coursefinder_meta'->>'fallback_profile_id','')::uuid;
  exception when others then v_fallback:=null;
  end;

  update pipeline.layer3_interpretations set
    raw_result=p_raw_result,candidate_value=p_candidate_value,confidence=p_confidence,rationale=p_rationale,
    evidence_quotes=coalesce(p_evidence_quotes,'[]'::jsonb),
    validator_result=coalesce(p_validator_result,'{}'::jsonb)
      || jsonb_build_object('review_confidence_min',v_threshold,'low_confidence',v_low_confidence),
    status=v_status,aggregator_response_model=p_response_model,
    input_tokens=p_input_tokens,output_tokens=p_output_tokens,
    estimated_cost_usd=coalesce(p_estimated_cost_usd,0),
    external_call_count=coalesce(p_external_call_count,0),
    retry_count=greatest(coalesce(p_external_call_count,0)-1,0),
    fallback_profile_id_used=v_fallback,
    execution_trace=v_trace,
    call_latency_ms=p_call_latency_ms,call_completed_at=now(),
    interpretation_expires_at=case when v_status='validated' then p_expiry else null end
  where id=p_interpretation_id;

  if p_valid and v_i.task_class<>'source_pattern' then
    if v_i.entity_type='course' then
      if v_i.task_class='course_description' then select to_jsonb(description) into v_before from catalogue.courses where id=v_i.entity_id;
      elsif v_i.task_class='delivery_mode' then select to_jsonb(delivery_mode) into v_before from catalogue.courses where id=v_i.entity_id;
      elsif v_i.task_class='duration' then select jsonb_build_object('value',duration_value,'unit',duration_unit) into v_before from catalogue.courses where id=v_i.entity_id;
      elsif v_i.task_class='official_course_url' then
        select to_jsonb(url) into v_before from catalogue.course_links
        where course_id=v_i.entity_id and link_type='official_course' and coalesce(status,'active')='active'
        order by last_verified_at desc nulls last,created_at desc limit 1;
      end if;
    end if;

    insert into pipeline.layer4_review_items(
      entity_type,entity_id,field_code,evidence_id,layer3_interpretation_id,before_value,
      proposed_value,layer2_state,layer3_state,escalation_reason,change_control_ref
    ) values(
      v_i.entity_type,v_i.entity_id,v_i.task_class,v_i.evidence_id,v_i.id,v_before,p_candidate_value,v_i.layer2_state,
      jsonb_build_object(
        'profile_id',v_i.profile_id,'prompt_profile_version',v_i.prompt_profile_version,
        'candidate_value',p_candidate_value,'confidence',p_confidence,'rationale',p_rationale,
        'validator_result',coalesce(p_validator_result,'{}'::jsonb),
        'response_model',p_response_model,'external_call_count',p_external_call_count,
        'retry_count',greatest(coalesce(p_external_call_count,0)-1,0),
        'call_latency_ms',p_call_latency_ms,'input_tokens',p_input_tokens,'output_tokens',p_output_tokens,
        'estimated_cost_usd',p_estimated_cost_usd,'selected_evidence_reason',v_i.selected_evidence_reason,
        'low_confidence',v_low_confidence,'review_confidence_min',v_threshold
      ),
      case
        when p_candidate_value is null or p_candidate_value='null'::jsonb
          then 'Layer 3 produced no candidate; human resolution or more Evidence required'
        when v_low_confidence
          then 'Layer 3 candidate is below the governed confidence threshold'
        else 'validated Layer 3 candidate requires human decision'
      end,
      'CF-CHG-20260829-047'
    ) returning id into v_review;
  end if;

  return jsonb_build_object(
    'ok',true,'interpretation_id',p_interpretation_id,'validated',p_valid,
    'status',v_status,'review_item_id',v_review,'external_call_count',p_external_call_count,
    'retry_count',greatest(coalesce(p_external_call_count,0)-1,0),
    'call_latency_ms',p_call_latency_ms,'review_confidence_min',v_threshold
  );
end $function$;


revoke all on function public.layer3_complete_interpretation_service(uuid,jsonb,jsonb,numeric,text,jsonb,jsonb,boolean,text,integer,integer,numeric,timestamptz,integer,integer) from public,anon,authenticated;
grant execute on function public.layer3_complete_interpretation_service(uuid,jsonb,jsonb,numeric,text,jsonb,jsonb,boolean,text,integer,integer,numeric,timestamptz,integer,integer) to service_role;

create or replace function public.layer3_source_pattern_handoff_service(p_refresh_request_id uuid,p_interpretation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','pipeline','catalogue','security','extensions'
as $function$
declare
  rr pipeline.refresh_requests%rowtype;
  i pipeline.layer3_interpretations%rowtype;
  lp pipeline.layer2_source_profiles%rowtype;
  ev pipeline.evidence_artifacts%rowtype;
  v_run_id uuid;
  v_provider_id uuid;
  v_candidate text;
  v_candidate_host text;
  v_evidence_host text;
  v_source_host text;
  v_cfg jsonb;
  v_cfg_hash text;
  v_validation jsonb;
  v_new_version uuid;
  v_version_no integer;
  v_ids uuid[];
  v_dispatch jsonb;
  v_layer4 jsonb;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;

  select * into rr from pipeline.refresh_requests where id=p_refresh_request_id for update;
  if not found or rr.requested_layer<>3 or rr.revalidation_ref not like 'A23-SOURCE-PATTERN:%' then
    raise exception 'source-pattern refresh request required' using errcode='22023';
  end if;
  if rr.status='completed' then
    return jsonb_build_object('ok',true,'idempotent',true,'request_id',rr.id,'status','completed','dispatch_request_id',rr.dispatch_request_id);
  end if;

  select * into i from pipeline.layer3_interpretations where id=p_interpretation_id;
  if not found then raise exception 'source-pattern interpretation not found' using errcode='22023'; end if;
  if i.task_class<>'source_pattern' or i.entity_type<>'provider' or i.entity_id<>rr.entity_id or i.evidence_id<>rr.evidence_id
     or i.profile_id<>rr.layer3_profile_id or coalesce(i.revalidation_ref,'')<>coalesce(rr.revalidation_ref,'') then
    raise exception 'source-pattern interpretation lineage mismatch' using errcode='22023';
  end if;
  if i.status not in('validated','low_confidence','no_candidate') then
    raise exception 'source-pattern interpretation is not handoff-ready' using errcode='22023';
  end if;

  v_provider_id:=rr.entity_id;
  begin v_run_id:=split_part(rr.revalidation_ref,':',2)::uuid;
  exception when others then raise exception 'invalid source-pattern revalidation reference' using errcode='22023'; end;
  if split_part(rr.revalidation_ref,':',3)<>v_provider_id::text then raise exception 'source-pattern provider reference mismatch' using errcode='22023'; end if;

  if i.status='validated' then
    v_candidate:=i.candidate_value #>> '{}';
    if v_candidate is null or v_candidate!~'^https://[^[:space:]]+$' then raise exception 'validated source-pattern HTTPS candidate required' using errcode='22023'; end if;
    if coalesce((i.validator_result->>'source_pattern_same_host')::boolean,false) is not true
       or coalesce((i.validator_result->>'source_pattern_evidence_link_match')::boolean,false) is not true then
      raise exception 'source-pattern deterministic URL controls not passed' using errcode='22023';
    end if;

    select * into ev from pipeline.evidence_artifacts where id=rr.evidence_id;
    select * into lp from pipeline.layer2_source_profiles where id=rr.source_profile_id for update;
    if not found or lp.authority_class<>'qualification_candidate' or lp.domain<>'course_facts' or not lp.enabled or lp.paused then
      raise exception 'qualification-candidate Layer 2 profile required' using errcode='22023';
    end if;
    if not exists(select 1 from pipeline.sources s where s.id=lp.source_id and s.provider_id=v_provider_id) then
      raise exception 'Layer 2 source/provider mismatch' using errcode='22023';
    end if;

    v_candidate_host:=lower(substring(v_candidate from '^https://([^/:?#]+)'));
    v_evidence_host:=lower(substring(coalesce(ev.source_url,'') from '^https://([^/:?#]+)'));
    select lower(substring(coalesce(s.url,'') from '^https://([^/:?#]+)')) into v_source_host from pipeline.sources s where s.id=lp.source_id;
    if v_candidate_host is null or v_evidence_host is null or v_candidate_host<>v_evidence_host
       or (v_source_host is not null and v_source_host<>'' and v_candidate_host<>v_source_host) then
      raise exception 'source-pattern candidate host mismatch' using errcode='22023';
    end if;

    select configuration into v_cfg from pipeline.layer2_source_profile_versions where id=lp.current_version_id;
    if v_cfg is null then raise exception 'current Layer 2 profile configuration required' using errcode='22023'; end if;
    v_cfg:=jsonb_set(
      jsonb_set(v_cfg,'{discovery_strategy}',jsonb_build_object(
        'type','catalogue_link_scan','catalogue_url',v_candidate,
        'course_acquisition_budget_ms',60000,'qualification_control_sample_size',3
      ),true),
      '{url_patterns}',coalesce(v_cfg->'url_patterns','[]'::jsonb)||jsonb_build_array(v_candidate),true
    );
    v_cfg:=jsonb_set(v_cfg,'{source_authority}',to_jsonb('first_party_candidate_under_layer3_pattern_control'::text),true);
    v_cfg:=jsonb_set(v_cfg,'{change_control_ref}',to_jsonb('CF-CHG-20260901-054'::text),true);
    v_cfg_hash:=encode(extensions.digest(v_cfg::text,'sha256'),'hex');
    v_validation:=security.layer2_validate_profile_config(v_cfg);
    if not coalesce((v_validation->>'valid')::boolean,false) then raise exception 'Layer 3 source-pattern generated invalid Layer 2 profile' using errcode='22023'; end if;

    select coalesce(max(v.version_no),0)+1 into v_version_no from pipeline.layer2_source_profile_versions v where v.profile_id=lp.id;
    insert into pipeline.layer2_source_profile_versions(
      profile_id,version_no,configuration,configuration_hash,validation_status,validation_result,
      change_control_ref,uat_ref,created_by
    ) values(
      lp.id,v_version_no,v_cfg,v_cfg_hash,'valid',v_validation,
      'CF-CHG-20260901-054','M2.5-CF054-source-pattern-handback',i.requested_by
    ) returning id into v_new_version;
    update pipeline.layer2_source_profiles set current_version_id=v_new_version,updated_at=now() where id=lp.id;

    select array_agg(x.course_id order by x.sample_rank) into v_ids
    from (
      select qi.course_id,qi.sample_rank
      from pipeline.layer2_scale_qualification_items qi
      where qi.run_id=v_run_id and qi.provider_id=v_provider_id
      order by qi.sample_rank limit 3
    ) x;
    if coalesce(array_length(v_ids,1),0)<>3 then raise exception 'three Layer 2 identity-control Courses required' using errcode='22023'; end if;

    update pipeline.layer2_scale_qualification_items qi
    set status='source_pattern_candidate',
        outcome=coalesce(qi.outcome,'{}'::jsonb)||jsonb_build_object(
          'stage','course_page_source_pattern_validation',
          'source_pattern_origin','layer3_governed_interpretation',
          'layer3_interpretation_id',i.id,'layer3_refresh_request_id',rr.id,
          'catalogue_candidate_url',v_candidate,'pattern_dispatch_version_id',v_new_version,
          'control_course_ids',to_jsonb(v_ids),'identity_control_required','3_of_3',
          'canonical_mutation_authorised',false,'search_mutation_authorised',false,'publication_mutation_authorised',false
        )
    where qi.run_id=v_run_id and qi.provider_id=v_provider_id and qi.status='layer3_required';
    if not found then raise exception 'Layer 2 qualification items are not awaiting Layer 3 pattern hand-back' using errcode='22023'; end if;

    v_dispatch:=security.layer2_discovery_scope_dispatch_v2(lp.id,v_ids,3,null,v_ids);
    update pipeline.refresh_requests set status='completed',completed_at=now(),dispatched_at=now(),
      dispatch_request_id=nullif(v_dispatch->>'request_id','')::bigint,schedule_error=null where id=rr.id;
    update pipeline.layer2_scale_qualification_runs set result_summary=coalesce(result_summary,'{}'::jsonb)||jsonb_build_object(
      'layer3_source_pattern_handback_at',now(),'layer3_source_pattern_provider_id',v_provider_id,
      'layer3_source_pattern_interpretation_id',i.id,'layer3_source_pattern_profile_version_id',v_new_version,
      'canonical_mutation_authorised',false,'search_mutation_authorised',false,'publication_mutation_authorised',false
    ) where id=v_run_id;

    return jsonb_build_object(
      'ok',true,'path','layer2_identity_control','request_id',rr.id,'run_id',v_run_id,'provider_id',v_provider_id,
      'candidate_url',v_candidate,'profile_version_id',v_new_version,'control_course_ids',to_jsonb(v_ids),'dispatch',v_dispatch,
      'provider_qualified',false,'canonical_mutation_authorised',false,'search_mutation_authorised',false,'publication_mutation_authorised',false
    );
  end if;

  update pipeline.layer2_scale_qualification_items qi
  set status='layer4_required',outcome=coalesce(qi.outcome,'{}'::jsonb)||jsonb_build_object(
    'stage','course_page_source_pattern_validation',
    'reason',case when i.status='low_confidence' then 'layer3_source_pattern_low_confidence' else 'layer3_source_pattern_no_candidate' end,
    'layer3_interpretation_id',i.id,'layer3_refresh_request_id',rr.id,'handoff','layer4_source_resolution',
    'canonical_mutation_authorised',false,'search_mutation_authorised',false,'publication_mutation_authorised',false
  )
  where qi.run_id=v_run_id and qi.provider_id=v_provider_id and qi.status='layer3_required';
  if not found then raise exception 'Layer 2 qualification items are not awaiting Layer 3 pattern resolution' using errcode='22023'; end if;

  v_layer4:=public.layer2_scale_cross_layer_handoff(v_run_id);
  update pipeline.refresh_requests set status='completed',completed_at=now(),dispatched_at=now(),dispatch_request_id=null,schedule_error=null where id=rr.id;
  return jsonb_build_object(
    'ok',true,'path','layer4_source_resolution','request_id',rr.id,'run_id',v_run_id,'provider_id',v_provider_id,
    'interpretation_status',i.status,'layer4_handoff',v_layer4,'provider_qualified',false,
    'canonical_mutation_authorised',false,'search_mutation_authorised',false,'publication_mutation_authorised',false
  );
end
$function$;

revoke all on function public.layer3_source_pattern_handoff_service(uuid,uuid) from public,anon,authenticated;
grant execute on function public.layer3_source_pattern_handoff_service(uuid,uuid) to service_role;
