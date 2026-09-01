-- CF-CHG-20260901-054
-- Scheme-tolerant host reconciliation for legacy first-party Evidence/source URLs.
-- Layer 3 source-pattern candidates remain HTTPS-only and exact Evidence-link bound.
-- This only allows HTTP-origin historical Evidence to hand back an HTTPS candidate on the exact same hostname.

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

    v_candidate_host:=lower(substring(v_candidate from '^https?://([^/:?#]+)'));
    v_evidence_host:=lower(substring(coalesce(ev.source_url,'') from '^https?://([^/:?#]+)'));
    select lower(substring(coalesce(s.url,'') from '^https?://([^/:?#]+)')) into v_source_host from pipeline.sources s where s.id=lp.source_id;
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
