-- CF-CHG-20260915-247
-- Forward-only persistence correction: when a bounded single-item enqueue encounters
-- an existing cf247-v1 work item created before server-owned candidate_context was
-- added, repair only the missing context from the same retained Evidence/source record.
begin;
create or replace function public.layer3_enqueue_from_layer2_service(
  p_layer2_run_item_id uuid,
  p_evidence_id uuid,
  p_task_class text,
  p_profile_id uuid default null,
  p_reason text default 'layer2_unresolved'
) returns jsonb
language plpgsql security definer
set search_path='pg_catalog','pipeline'
as $$
declare
  v_item pipeline.layer2_run_items%rowtype;
  v_id uuid;
  v_created boolean:=false;
  v_repaired boolean:=false;
  v_caller text;
  v_candidate_context jsonb;
begin
  v_caller:=coalesce(nullif(current_setting('request.jwt.claim.role',true),''),nullif(current_setting('request.jwt.role',true),''),session_user);
  if v_caller not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  select * into v_item from pipeline.layer2_run_items where id=p_layer2_run_item_id;
  if not found then raise exception 'layer2 run item not found'; end if;
  if v_item.status<>'layer3_required' then
    return jsonb_build_object('queued',false,'reason','layer2_not_layer3_required','layer2_status',v_item.status);
  end if;
  if not exists(select 1 from pipeline.evidence_artifacts where id=p_evidence_id and content_hash is not null and storage_path is not null) then
    raise exception 'retained governed Evidence required';
  end if;
  if nullif(trim(p_task_class),'') is null then raise exception 'task class required'; end if;

  if trim(p_task_class)='provider_current_tuition_validation' then
    select jsonb_build_object(
      'provider_current_tuition',r.parsed_payload->'provider_current_tuition',
      'fee_candidates',coalesce(r.parsed_payload->'fee_candidates','[]'::jsonb),
      'fee_ambiguous',coalesce((r.parsed_payload->>'fee_ambiguous')::boolean,false),
      'identity_match',coalesce((r.parsed_payload->>'identity_match')::boolean,false),
      'expected_course_code',r.parsed_payload->'expected_course_code',
      'extraction_worker',r.parsed_payload->'extraction_worker',
      'source_record_id',r.source_record_id
    ) into v_candidate_context
    from pipeline.course_fact_source_records r
    where r.evidence_id=p_evidence_id
      and r.parsed_payload->>'course_id'=v_item.entity_id::text
    order by r.observed_at desc,r.id desc limit 1;
    if v_candidate_context is null
       or (v_candidate_context->'provider_current_tuition' is null
           and jsonb_array_length(coalesce(v_candidate_context->'fee_candidates','[]'::jsonb))=0) then
      raise exception 'server-owned candidate context required for tuition validation';
    end if;
  end if;

  insert into pipeline.layer3_work_items(
    layer2_run_item_id,evidence_id,entity_type,entity_id,task_class,profile_id,reason,candidate_context
  ) values(
    p_layer2_run_item_id,p_evidence_id,lower(v_item.entity_type),v_item.entity_id,trim(p_task_class),p_profile_id,
    coalesce(nullif(trim(p_reason),''),'layer2_unresolved'),v_candidate_context
  )
  on conflict(layer2_run_item_id,evidence_id,task_class,policy_version) do nothing returning id into v_id;
  if v_id is not null then
    v_created:=true;
  else
    update pipeline.layer3_work_items
       set candidate_context=v_candidate_context,
           updated_at=now()
     where layer2_run_item_id=p_layer2_run_item_id
       and evidence_id=p_evidence_id
       and task_class=trim(p_task_class)
       and policy_version='cf247-v1'
       and candidate_context is null
       and v_candidate_context is not null
    returning id into v_id;
    if v_id is not null then v_repaired:=true; end if;
    if v_id is null then
      select id into v_id from pipeline.layer3_work_items
       where layer2_run_item_id=p_layer2_run_item_id and evidence_id=p_evidence_id
         and task_class=trim(p_task_class) and policy_version='cf247-v1';
    end if;
  end if;
  return jsonb_build_object('queued',true,'created',v_created,'repaired_context',v_repaired,'work_item_id',v_id);
end $$;
revoke all on function public.layer3_enqueue_from_layer2_service(uuid,uuid,text,uuid,text) from public,anon,authenticated;
grant execute on function public.layer3_enqueue_from_layer2_service(uuid,uuid,text,uuid,text) to service_role;
commit;
