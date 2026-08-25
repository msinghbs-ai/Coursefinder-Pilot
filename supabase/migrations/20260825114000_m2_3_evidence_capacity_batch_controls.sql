-- M2.3 Layer 2 Scale Enrichment & L1/L2 UX Maturity
-- Change Control: CF-CHG-20260825-036

create unique index if not exists evidence_standard_group_hash_uq
on pipeline.evidence_artifacts (evidence_group_key, content_hash)
where retention_class = 'standard_365'
  and evidence_group_key is not null
  and content_hash is not null;

create index if not exists layer2_run_batches_status_created_idx
on pipeline.layer2_run_batches(status, created_at desc);

create index if not exists layer2_run_items_batch_status_idx
on pipeline.layer2_run_items(batch_id, status);

create table if not exists pipeline.evidence_capacity_policy (
  id boolean primary key default true check (id),
  planning_capacity_bytes bigint not null check (planning_capacity_bytes > 0),
  warn_pct numeric not null default 60 check (warn_pct > 0 and warn_pct < 100),
  high_pct numeric not null default 75 check (high_pct > warn_pct and high_pct < 100),
  critical_pct numeric not null default 90 check (critical_pct > high_pct and critical_pct <= 100),
  capacity_basis text not null,
  change_control_ref text not null,
  updated_at timestamptz not null default now()
);

insert into pipeline.evidence_capacity_policy(
  id, planning_capacity_bytes, warn_pct, high_pct, critical_pct,
  capacity_basis, change_control_ref
)
values (
  true, 64424509440, 60, 75, 90,
  'M2 planning envelope 60 GiB; operational planning threshold, not vendor hard quota',
  'CF-CHG-20260825-036'
)
on conflict (id) do update set
  planning_capacity_bytes = excluded.planning_capacity_bytes,
  warn_pct = excluded.warn_pct,
  high_pct = excluded.high_pct,
  critical_pct = excluded.critical_pct,
  capacity_basis = excluded.capacity_basis,
  change_control_ref = excluded.change_control_ref,
  updated_at = now();

create or replace function public.layer2_evidence_capacity_status()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, pipeline, storage
as $$
with usage as (
  select count(*)::bigint objects,
         coalesce(sum((metadata->>'size')::bigint),0)::bigint bytes
  from storage.objects
  where bucket_id='evidence'
), p as (
  select * from pipeline.evidence_capacity_policy where id=true
), x as (
  select u.objects,u.bytes,p.planning_capacity_bytes,p.warn_pct,p.high_pct,p.critical_pct,p.capacity_basis,
         case when p.planning_capacity_bytes=0 then 0
              else (u.bytes::numeric*100/p.planning_capacity_bytes) end pct
  from usage u cross join p
)
select jsonb_build_object(
  'objects',objects,
  'bytes',bytes,
  'planning_capacity_bytes',planning_capacity_bytes,
  'used_pct',round(pct,2),
  'warn_pct',warn_pct,
  'high_pct',high_pct,
  'critical_pct',critical_pct,
  'state',case when pct>=critical_pct then 'critical'
               when pct>=high_pct then 'high'
               when pct>=warn_pct then 'warn'
               else 'normal' end,
  'capacity_basis',capacity_basis
) from x;
$$;

revoke all on function public.layer2_evidence_capacity_status() from public, anon, authenticated;
grant execute on function public.layer2_evidence_capacity_status() to service_role;

create or replace function public.layer2_run_batch_create(
  p_profile_id uuid,
  p_trigger_type text,
  p_requested_by uuid,
  p_items jsonb
) returns uuid
language plpgsql
security definer
set search_path=pg_catalog,pipeline
as $$
declare
  v_profile pipeline.layer2_source_profiles%rowtype;
  v_policy pipeline.layer2_execution_policies%rowtype;
  v_batch uuid:=gen_random_uuid();
  v_count integer;
begin
  if p_trigger_type not in ('manual','schedule','trial','resume') then
    raise exception 'invalid trigger_type';
  end if;
  if jsonb_typeof(p_items)<>'array' then
    raise exception 'items must be array';
  end if;
  v_count:=jsonb_array_length(p_items);
  if v_count<1 or v_count>100 then
    raise exception 'batch item count must be 1..100';
  end if;

  select * into v_profile from pipeline.layer2_source_profiles where id=p_profile_id;
  if not found then raise exception 'profile not found'; end if;
  if not v_profile.enabled or v_profile.paused then raise exception 'profile not executable'; end if;
  if v_profile.current_version_id is null then raise exception 'profile has no current version'; end if;

  select * into v_policy from pipeline.layer2_execution_policies where profile_id=p_profile_id;
  if not found then raise exception 'execution policy missing'; end if;

  insert into pipeline.layer2_run_batches(
    id,profile_id,profile_version_id,trigger_type,status,requested_by,policy_snapshot,target_count
  ) values(
    v_batch,p_profile_id,v_profile.current_version_id,p_trigger_type,'queued',p_requested_by,
    jsonb_build_object(
      'schedule_mode',v_policy.schedule_mode,
      'batch_size',v_policy.batch_size,
      'routing_strategy',v_policy.routing_strategy,
      'max_paid_attempts_per_entity',v_policy.max_paid_attempts_per_entity,
      'max_vendor_units_per_entity',v_policy.max_vendor_units_per_entity,
      'max_cost_usd_per_entity',v_policy.max_cost_usd_per_entity,
      'auto_handoff_layer3',v_policy.auto_handoff_layer3,
      'stop_on_identity_mismatch',v_policy.stop_on_identity_mismatch
    ),v_count
  );

  insert into pipeline.layer2_run_items(id,batch_id,entity_type,entity_id,source_url,status)
  select gen_random_uuid(),v_batch,lower(x->>'entity_type'),(x->>'entity_id')::uuid,x->>'source_url','queued'
  from jsonb_array_elements(p_items) x;

  if exists(
    select 1 from pipeline.layer2_run_items
    where batch_id=v_batch
      and (entity_type not in ('course','scholarship') or entity_id is null or nullif(source_url,'') is null)
  ) then
    raise exception 'each item requires valid entity_type, entity_id and source_url';
  end if;

  return v_batch;
end
$$;

revoke all on function public.layer2_run_batch_create(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.layer2_run_batch_create(uuid,text,uuid,jsonb) to service_role;

create or replace function public.layer2_run_batch_summary(p_batch_id uuid)
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog,pipeline
as $$
select jsonb_build_object(
  'batch_id',b.id,
  'status',b.status,
  'trigger_type',b.trigger_type,
  'profile_id',b.profile_id,
  'profile_version_id',b.profile_version_id,
  'target_count',b.target_count,
  'processed_count',b.processed_count,
  'resolved_l2_count',b.resolved_l2_count,
  'escalated_l3_count',b.escalated_l3_count,
  'blocked_count',b.blocked_count,
  'vendor_units',b.vendor_units,
  'vendor_cost_usd',b.vendor_cost_usd,
  'policy_snapshot',b.policy_snapshot,
  'items',coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',i.id,
      'entity_type',i.entity_type,
      'entity_id',i.entity_id,
      'source_url',i.source_url,
      'status',i.status,
      'provider_id',i.selected_provider_id,
      'evidence_count',i.evidence_count,
      'fields_targeted',i.fields_targeted,
      'fields_resolved',i.fields_resolved,
      'vendor_units',i.vendor_units,
      'vendor_cost_usd',i.vendor_cost_usd,
      'blocker',i.blocker
    ) order by i.created_at)
    from pipeline.layer2_run_items i where i.batch_id=b.id
  ),'[]'::jsonb)
)
from pipeline.layer2_run_batches b
where b.id=p_batch_id;
$$;

revoke all on function public.layer2_run_batch_summary(uuid) from public,anon,authenticated;
grant execute on function public.layer2_run_batch_summary(uuid) to service_role;