-- CF-CHG-20260915-247
-- Durable, service-owned Layer 2 -> Layer 3 work queue foundation.
-- This migration does not execute AI or mutate canonical data. It creates the
-- idempotent handoff/reservation substrate required by the automatic dispatcher.
begin;

create table if not exists pipeline.layer3_work_items (
  id uuid primary key default gen_random_uuid(),
  layer2_run_item_id uuid not null references pipeline.layer2_run_items(id) on delete cascade,
  evidence_id uuid not null references pipeline.evidence_artifacts(id),
  entity_type text not null,
  entity_id uuid not null,
  task_class text not null,
  profile_id uuid references pipeline.layer3_model_profiles(id),
  interpretation_id uuid references pipeline.layer3_interpretations(id),
  status text not null default 'pending' check (status in ('pending','reserved','interpreting','validated','no_candidate','rejected','admission_pending','layer4_required','admitted','parked','failed')),
  reason text not null default 'layer2_unresolved',
  attempt_count integer not null default 0 check (attempt_count>=0),
  available_at timestamptz not null default now(),
  reserved_at timestamptz,
  reserved_by text,
  completed_at timestamptz,
  last_error text,
  policy_version text not null default 'cf247-v1',
  change_control_ref text not null default 'CF-CHG-20260915-247',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(layer2_run_item_id,evidence_id,task_class,policy_version)
);

create index if not exists layer3_work_items_dispatch_idx
  on pipeline.layer3_work_items(status,available_at,created_at)
  where status in ('pending','failed');
create index if not exists layer3_work_items_entity_idx
  on pipeline.layer3_work_items(entity_type,entity_id,task_class,status);
create index if not exists layer3_work_items_interpretation_idx
  on pipeline.layer3_work_items(interpretation_id)
  where interpretation_id is not null;

alter table pipeline.layer3_work_items enable row level security;
revoke all on pipeline.layer3_work_items from public,anon,authenticated;
grant select,insert,update on pipeline.layer3_work_items to service_role;

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
declare v_item pipeline.layer2_run_items%rowtype; v_id uuid; v_created boolean:=false; v_caller text;
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
  insert into pipeline.layer3_work_items(layer2_run_item_id,evidence_id,entity_type,entity_id,task_class,profile_id,reason)
  values(p_layer2_run_item_id,p_evidence_id,lower(v_item.entity_type),v_item.entity_id,trim(p_task_class),p_profile_id,coalesce(nullif(trim(p_reason),''),'layer2_unresolved'))
  on conflict(layer2_run_item_id,evidence_id,task_class,policy_version) do nothing
  returning id into v_id;
  if v_id is not null then v_created:=true;
  else
    select id into v_id from pipeline.layer3_work_items
    where layer2_run_item_id=p_layer2_run_item_id and evidence_id=p_evidence_id and task_class=trim(p_task_class) and policy_version='cf247-v1';
  end if;
  return jsonb_build_object('queued',true,'created',v_created,'work_item_id',v_id);
end $$;

create or replace function public.layer3_reserve_work_service(p_worker text,p_limit integer default 10)
returns jsonb
language plpgsql security definer
set search_path='pg_catalog','pipeline'
as $$
declare v_result jsonb; v_caller text;
begin
  v_caller:=coalesce(nullif(current_setting('request.jwt.claim.role',true),''),nullif(current_setting('request.jwt.role',true),''),session_user);
  if v_caller not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  if nullif(trim(p_worker),'') is null then raise exception 'worker required'; end if;

  -- Reclaim abandoned leases. Poison work is parked after five reservations.
  update pipeline.layer3_work_items
  set status=case when attempt_count>=5 then 'parked' else 'pending' end,
      available_at=case when attempt_count>=5 then available_at else now() end,
      completed_at=case when attempt_count>=5 then now() else null end,
      last_error=case when attempt_count>=5 then 'reservation lease expired after maximum attempts' else 'reservation lease expired; requeued' end,
      reserved_at=null,reserved_by=null,updated_at=now()
  where status='reserved' and reserved_at < now()-interval '15 minutes';

  with picked as (
    select w.id
    from pipeline.layer3_work_items w
    left join pipeline.layer3_model_profiles p on p.id=w.profile_id
    where w.status in ('pending','failed') and w.available_at<=now() and w.attempt_count<5
      and (w.profile_id is null or (p.enabled and not p.paused and coalesce((p.quality_benchmark->>'pass')::boolean,false)))
    order by w.created_at,w.id
    for update of w skip locked
    limit least(greatest(coalesce(p_limit,10),1),50)
  ), reserved as (
    update pipeline.layer3_work_items w set status='reserved',reserved_at=now(),reserved_by=trim(p_worker),attempt_count=w.attempt_count+1,updated_at=now()
    from picked where w.id=picked.id
    returning w.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',id,'layer2_run_item_id',layer2_run_item_id,'evidence_id',evidence_id,'entity_type',entity_type,'entity_id',entity_id,
    'task_class',task_class,'profile_id',profile_id,'attempt_count',attempt_count,'reason',reason,'policy_version',policy_version
  ) order by created_at,id),'[]'::jsonb) into v_result from reserved;
  return v_result;
end $$;

create or replace function public.layer3_work_item_transition_service(
  p_work_item_id uuid,p_from_status text,p_to_status text,p_interpretation_id uuid default null,p_error text default null,p_retry_after_seconds integer default null
) returns jsonb
language plpgsql security definer
set search_path='pg_catalog','pipeline'
as $$
declare v_ok boolean; v_caller text;
begin
  v_caller:=coalesce(nullif(current_setting('request.jwt.claim.role',true),''),nullif(current_setting('request.jwt.role',true),''),session_user);
  if v_caller not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  if p_to_status not in ('pending','reserved','interpreting','validated','no_candidate','rejected','admission_pending','layer4_required','admitted','parked','failed') then raise exception 'invalid target status'; end if;
  update pipeline.layer3_work_items set
    status=case when p_to_status='failed' and attempt_count>=5 then 'parked' else p_to_status end,
    interpretation_id=coalesce(p_interpretation_id,interpretation_id),
    last_error=case when p_to_status in ('failed','parked','rejected') then nullif(left(coalesce(p_error,''),2000),'') else null end,
    available_at=case when p_to_status='failed' and attempt_count<5 then now()+make_interval(secs=>least(greatest(coalesce(p_retry_after_seconds,60),1),86400)) else available_at end,
    completed_at=case when p_to_status in ('validated','no_candidate','rejected','layer4_required','admitted','parked') or (p_to_status='failed' and attempt_count>=5) then now() else null end,
    reserved_at=case when p_to_status in ('reserved','interpreting') then reserved_at else null end,
    reserved_by=case when p_to_status in ('reserved','interpreting') then reserved_by else null end,
    updated_at=now()
  where id=p_work_item_id and status=p_from_status;
  v_ok:=found;
  return jsonb_build_object('ok',v_ok,'work_item_id',p_work_item_id,'status',case when v_ok then (select status from pipeline.layer3_work_items where id=p_work_item_id) else null end);
end $$;

revoke all on function public.layer3_enqueue_from_layer2_service(uuid,uuid,text,uuid,text) from public,anon,authenticated;
revoke all on function public.layer3_reserve_work_service(text,integer) from public,anon,authenticated;
revoke all on function public.layer3_work_item_transition_service(uuid,text,text,uuid,text,integer) from public,anon,authenticated;
grant execute on function public.layer3_enqueue_from_layer2_service(uuid,uuid,text,uuid,text) to service_role;
grant execute on function public.layer3_reserve_work_service(text,integer) to service_role;
grant execute on function public.layer3_work_item_transition_service(uuid,text,text,uuid,text,integer) to service_role;

commit;
