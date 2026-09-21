-- CF-247 forward-only slice 2A: task/profile-scoped Layer 3 work reservation.
-- Adds a canonical scoped reservation RPC that only reserves rows matching the
-- exact requested task class and profile ID, and revalidates that exact
-- profile (enabled, not paused, benchmark PASS, task allowed) inside the same
-- transaction as the lease-recovery/selection/reservation. The existing
-- two-argument layer3_reserve_work_service(text,integer) is made fail-closed
-- (raises, reserves nothing) instead of globally reserving arbitrary work, so
-- there is no default-argument/overload ambiguity between the two RPCs.
begin;

create or replace function public.layer3_reserve_scoped_work_service(
  p_worker text,
  p_task_class text,
  p_profile_id uuid,
  p_limit integer default 10
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','pipeline'
as $$
declare v_result jsonb; v_caller text; v_p pipeline.layer3_model_profiles%rowtype;
begin
  v_caller:=coalesce(
    nullif(current_setting('request.jwt.claim.role',true),''),
    nullif(current_setting('request.jwt.role',true),''),
    nullif((nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role'),''),
    session_user
  );
  if v_caller not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;
  if nullif(trim(p_worker),'') is null then raise exception 'worker required'; end if;
  if nullif(trim(p_task_class),'') is null then raise exception 'task class required'; end if;
  if p_profile_id is null then raise exception 'profile id required'; end if;

  select * into v_p from pipeline.layer3_model_profiles where id=p_profile_id for update;
  if not found then raise exception 'model profile not found'; end if;
  if not v_p.enabled or v_p.paused then raise exception 'model profile not executable'; end if;
  if coalesce((v_p.quality_benchmark->>'pass')::boolean,false) is not true then
    raise exception 'model profile quality benchmark not passed';
  end if;
  if not (trim(p_task_class)=any(v_p.allowed_task_classes)) then
    raise exception 'task class not allowed by profile';
  end if;

  -- Reclaim abandoned leases, scoped to this exact task class/profile only,
  -- so one dispatcher cannot park/requeue another handler's work.
  update pipeline.layer3_work_items
  set status=case when attempt_count>=5 and corrective_retry_authorized_at is null then 'parked' else 'pending' end,
      available_at=case when attempt_count>=5 and corrective_retry_authorized_at is null then available_at else now() end,
      completed_at=case when attempt_count>=5 and corrective_retry_authorized_at is null then now() else null end,
      last_error=case when attempt_count>=5 and corrective_retry_authorized_at is null then 'reservation lease expired after maximum attempts' else 'reservation lease expired; requeued' end,
      reserved_at=null,reserved_by=null,updated_at=now()
  where status='reserved' and reserved_at < now()-interval '15 minutes'
    and task_class=trim(p_task_class) and profile_id=p_profile_id;

  with picked as (
    select w.id
    from pipeline.layer3_work_items w
    where w.status in ('pending','failed') and w.available_at<=now()
      and w.task_class=trim(p_task_class) and w.profile_id=p_profile_id
      and (w.attempt_count<5 or (w.corrective_retry_count=1 and w.corrective_retry_authorized_at is not null))
    order by w.created_at,w.id
    for update of w skip locked
    limit least(greatest(coalesce(p_limit,10),1),50)
  ), reserved as (
    update pipeline.layer3_work_items w set status='reserved',reserved_at=now(),reserved_by=trim(p_worker),attempt_count=w.attempt_count+1,
      corrective_retry_authorized_at=null,updated_at=now()
    from picked where w.id=picked.id
    returning w.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',id,'layer2_run_item_id',layer2_run_item_id,'evidence_id',evidence_id,'entity_type',entity_type,'entity_id',entity_id,
    'task_class',task_class,'profile_id',profile_id,'attempt_count',attempt_count,'reason',reason,'policy_version',policy_version,
    'corrective_retry_count',corrective_retry_count,'corrective_retry_reason',corrective_retry_reason
  ) order by created_at,id),'[]'::jsonb) into v_result from reserved;
  return v_result;
end $$;

-- Fail closed: the legacy global two-argument reservation RPC must no longer
-- reserve arbitrary work across task classes/profiles. Keep the signature
-- (so no default-argument/overload ambiguity is introduced against the new
-- scoped RPC's distinct arity) but always raise instead of executing.
create or replace function public.layer3_reserve_work_service(p_worker text, p_limit integer default 10)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','pipeline'
as $$
begin
  raise exception 'layer3_reserve_work_service is retired; use layer3_reserve_scoped_work_service(worker,task_class,profile_id,limit)' using errcode='42501';
end $$;

revoke all on function public.layer3_reserve_scoped_work_service(text,text,uuid,integer) from public,anon,authenticated;
grant execute on function public.layer3_reserve_scoped_work_service(text,text,uuid,integer) to service_role;
revoke all on function public.layer3_reserve_work_service(text,integer) from public,anon,authenticated;
grant execute on function public.layer3_reserve_work_service(text,integer) to service_role;

commit;
