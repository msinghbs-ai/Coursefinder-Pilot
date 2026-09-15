-- CF-CHG-20260915-247
-- Derive only explicit, evidence-backed Layer 3 work from Layer 2 fall-out.
-- This does not execute AI and does not mutate canonical/Search data.
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

  -- Current Course fall-out is predominantly provider-current tuition. Do not guess
  -- task classes from a generic layer3_required marker. Only explicit fee blockers
  -- are mapped here, and only when the matching benchmark-passed profile is executable.
  with profile as (
    select id
    from pipeline.layer3_model_profiles
    where 'provider_current_tuition_validation'=any(allowed_task_classes)
      and enabled and not paused
      and coalesce((quality_benchmark->>'pass')::boolean,false)
    order by updated_at desc,id
    limit 1
  ), candidates as (
    select i.id as layer2_run_item_id,
           coalesce(a.html_evidence_id,a.raw_evidence_id) as evidence_id,
           p.id as profile_id,
           case
             when i.blocker ilike '%multiple_equal_rank_fee_candidates%' then 'multiple_equal_rank_fee_candidates'
             when i.blocker ilike '%low_confidence_international_fee_candidate%' then 'low_confidence_international_fee_candidate'
             when i.blocker ilike '%no_fee_candidate%' then 'no_fee_candidate'
             else null
           end as reason
    from pipeline.layer2_run_items i
    join pipeline.layer2_provider_attempts a on a.job_id=i.job_id
    cross join profile p
    where i.status='layer3_required'
      and (i.blocker ilike '%fee_candidate%' or i.blocker ilike '%no_fee_candidate%')
      and coalesce(a.html_evidence_id,a.raw_evidence_id) is not null
      and exists (
        select 1 from pipeline.evidence_artifacts e
        where e.id=coalesce(a.html_evidence_id,a.raw_evidence_id)
          and e.storage_path is not null and e.content_hash is not null
      )
      and not exists (
        select 1 from pipeline.layer3_work_items w
        where w.layer2_run_item_id=i.id
          and w.evidence_id=coalesce(a.html_evidence_id,a.raw_evidence_id)
          and w.task_class='provider_current_tuition_validation'
          and w.policy_version='cf247-v1'
      )
    order by i.completed_at nulls last,i.id
    limit least(greatest(coalesce(p_limit,25),1),100)
  ), inserted as (
    insert into pipeline.layer3_work_items(layer2_run_item_id,evidence_id,entity_type,entity_id,task_class,profile_id,reason)
    select c.layer2_run_item_id,c.evidence_id,lower(i.entity_type),i.entity_id,
           'provider_current_tuition_validation',c.profile_id,c.reason
    from candidates c join pipeline.layer2_run_items i on i.id=c.layer2_run_item_id
    on conflict(layer2_run_item_id,evidence_id,task_class,policy_version) do nothing
    returning id
  )
  select jsonb_build_object(
    'queued',count(*),
    'task_class','provider_current_tuition_validation',
    'reason',case when exists(select 1 from profile) then 'eligible_handoffs_enqueued' else 'no_benchmark_passed_executable_profile' end
  ) into v_result from inserted;

  return v_result;
end $$;

revoke all on function public.layer3_enqueue_eligible_layer2_service(integer) from public,anon,authenticated;
grant execute on function public.layer3_enqueue_eligible_layer2_service(integer) to service_role;

commit;
