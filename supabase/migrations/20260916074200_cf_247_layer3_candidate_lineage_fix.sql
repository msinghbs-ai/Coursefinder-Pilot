-- CF-CHG-20260915-247
-- Forward fix: the deterministic candidate record is keyed to normalized extraction Evidence,
-- not the raw/html provider-attempt Evidence. Preserve that exact lineage at handoff.
begin;
create or replace function public.layer3_enqueue_eligible_layer2_service(p_limit integer default 25)
returns jsonb
language plpgsql security definer
set search_path='pg_catalog','pipeline'
as $$
declare v_caller text; v_result jsonb;
begin
  v_caller:=coalesce(nullif(current_setting('request.jwt.claim.role',true),''),nullif(current_setting('request.jwt.role',true),''),session_user);
  if v_caller not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  with profile as (
    select id from pipeline.layer3_model_profiles
    where 'provider_current_tuition_validation'=any(allowed_task_classes) and enabled and not paused
      and coalesce((quality_benchmark->>'pass')::boolean,false)
    order by updated_at desc,id limit 1
  ), candidates as (
    select i.id layer2_run_item_id,a.evidence_id,p.id profile_id,
      case when i.blocker ilike '%multiple_equal_rank_fee_candidates%' then 'multiple_equal_rank_fee_candidates'
           when i.blocker ilike '%low_confidence_international_fee_candidate%' then 'low_confidence_international_fee_candidate'
           when i.blocker ilike '%no_fee_candidate%' then 'no_fee_candidate' end reason,
      jsonb_build_object('provider_current_tuition',sr.parsed_payload->'provider_current_tuition','fee_candidates',coalesce(sr.parsed_payload->'fee_candidates','[]'::jsonb),'fee_ambiguous',coalesce((sr.parsed_payload->>'fee_ambiguous')::boolean,false),'identity_match',coalesce((sr.parsed_payload->>'identity_match')::boolean,false),'expected_course_code',sr.parsed_payload->'expected_course_code','extraction_worker',sr.parsed_payload->'extraction_worker','source_record_id',sr.source_record_id) candidate_context
    from pipeline.layer2_run_items i
    join lateral (
      select coalesce(nullif(pa.metrics->>'normalised_evidence_id','')::uuid,pa.html_evidence_id,pa.raw_evidence_id) evidence_id
      from pipeline.layer2_provider_attempts pa
      where pa.job_id=i.job_id and coalesce(nullif(pa.metrics->>'normalised_evidence_id','')::uuid,pa.html_evidence_id,pa.raw_evidence_id) is not null
      order by pa.attempt_no desc limit 1
    ) a on true
    join lateral (
      select r.source_record_id,r.parsed_payload from pipeline.course_fact_source_records r
      where r.evidence_id=a.evidence_id and r.parsed_payload->>'course_id'=i.entity_id::text
      order by r.observed_at desc,r.id desc limit 1
    ) sr on true
    cross join profile p
    where i.status='layer3_required'
      and (i.blocker ilike '%multiple_equal_rank_fee_candidates%' or i.blocker ilike '%low_confidence_international_fee_candidate%' or i.blocker ilike '%no_fee_candidate%')
      and exists(select 1 from pipeline.evidence_artifacts e where e.id=a.evidence_id and e.storage_path is not null and e.content_hash is not null)
      and (sr.parsed_payload->'provider_current_tuition' is not null or jsonb_array_length(coalesce(sr.parsed_payload->'fee_candidates','[]'::jsonb))>0)
      and not exists(select 1 from pipeline.layer3_work_items w where w.layer2_run_item_id=i.id and w.evidence_id=a.evidence_id and w.task_class='provider_current_tuition_validation' and w.policy_version='cf247-v1')
    order by i.completed_at nulls last,i.id limit least(greatest(coalesce(p_limit,25),1),100)
  ), inserted as (
    insert into pipeline.layer3_work_items(layer2_run_item_id,evidence_id,entity_type,entity_id,task_class,profile_id,reason,candidate_context)
    select c.layer2_run_item_id,c.evidence_id,lower(i.entity_type),i.entity_id,'provider_current_tuition_validation',c.profile_id,c.reason,c.candidate_context
    from candidates c join pipeline.layer2_run_items i on i.id=c.layer2_run_item_id
    on conflict(layer2_run_item_id,evidence_id,task_class,policy_version) do nothing returning id
  )
  select jsonb_build_object('queued',count(*),'task_class','provider_current_tuition_validation','reason',case when exists(select 1 from profile) then 'eligible_candidate_validation_handoffs_enqueued' else 'no_benchmark_passed_executable_profile' end) into v_result from inserted;
  return v_result;
end $$;
revoke all on function public.layer3_enqueue_eligible_layer2_service(integer) from public,anon,authenticated;
grant execute on function public.layer3_enqueue_eligible_layer2_service(integer) to service_role;
commit;
