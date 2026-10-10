-- CF-CHG-20260830-048
-- M2.4.4 A26: reuse the existing qualification/wave/batch/job/Evidence model
-- and project one stable parent identity across scheduler/retry boundaries.

create or replace function security.layer2_qualification_root(p_run_id uuid)
returns uuid
language sql
stable
security definer
set search_path='pg_catalog','pipeline','security'
as $$
  with recursive chain(id,depth) as (
    select p_run_id,0
    union all
    select p.id,chain.depth+1
    from chain
    join pipeline.layer2_scale_qualification_runs p
      on nullif(p.result_summary->>'next_qualification_run_id','')::uuid=chain.id
    where chain.depth<100
  )
  select id from chain order by depth desc limit 1
$$;
revoke all on function security.layer2_qualification_root(uuid) from public,anon,authenticated;
grant execute on function security.layer2_qualification_root(uuid) to service_role;

create or replace function security.layer2_wave_parent_stamp()
returns trigger
language plpgsql
security definer
set search_path='pg_catalog','pipeline','ref','security'
as $$
declare
  v_terminal uuid;
  v_root uuid;
begin
  select q.id into v_terminal
  from pipeline.layer2_scale_qualification_runs q
  join ref.countries c on c.id=q.country_id
  where q.requested_by=new.requested_by
    and c.iso_alpha2::text=upper(new.country_code)
    and q.scope_type=new.scope_type
    and q.scope_id is not distinct from new.scope_id
    and q.status in('completed','partial')
    and coalesce((q.result_summary->>'auto_progress_scope')::boolean,false)
  order by
    case when not coalesce((q.result_summary->>'auto_progress_processed')::boolean,false) then 0 else 1 end,
    q.completed_at desc nulls last,q.created_at desc
  limit 1;

  if v_terminal is not null then
    v_root:=security.layer2_qualification_root(v_terminal);
  end if;

  update pipeline.layer2_scope_wave_requests
  set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
    'parent_run_id',coalesce(v_root,new.id),
    'parent_run_kind',case when v_root is null then 'scope_wave_request' else 'qualification_root' end,
    'qualification_terminal_run_id',v_terminal,
    'scope_wave_request_id',new.id,
    'lineage_version','a26-v1'
  )
  where id=new.id;
  return new;
end $$;
revoke all on function security.layer2_wave_parent_stamp() from public,anon,authenticated;

drop trigger if exists trg_layer2_wave_parent_stamp on pipeline.layer2_scope_wave_requests;
create trigger trg_layer2_wave_parent_stamp
after insert on pipeline.layer2_scope_wave_requests
for each row execute function security.layer2_wave_parent_stamp();

create or replace function security.layer2_batch_lineage_stamp()
returns trigger
language plpgsql
security definer
set search_path='pg_catalog','pipeline','security'
as $$
begin
  if new.batch_id is not null and (old.batch_id is distinct from new.batch_id) then
    update pipeline.layer2_run_batches b
    set policy_snapshot=coalesce(b.policy_snapshot,'{}'::jsonb)||jsonb_build_object(
      'parent_run_id',coalesce(r.metadata->>'parent_run_id',r.id::text),
      'scope_wave_request_id',r.id,
      'scope_type',r.scope_type,
      'scope_id',r.scope_id,
      'country_code',r.country_code,
      'route_mode',r.route_mode,
      'lineage_version','a26-v1'
    ),
    updated_at=now()
    from pipeline.layer2_scope_wave_requests r
    where r.id=new.request_id and b.id=new.batch_id;
  end if;
  return new;
end $$;
revoke all on function security.layer2_batch_lineage_stamp() from public,anon,authenticated;

drop trigger if exists trg_layer2_batch_lineage_stamp on pipeline.layer2_scope_wave_items;
create trigger trg_layer2_batch_lineage_stamp
after update of batch_id on pipeline.layer2_scope_wave_items
for each row execute function security.layer2_batch_lineage_stamp();

create or replace function security.layer2_lineage_for_job(p_job_id uuid)
returns jsonb
language sql
stable
security definer
set search_path='pg_catalog','pipeline','security'
as $$
  select jsonb_build_object(
    'parent_run_id',coalesce(r.metadata->>'parent_run_id',r.id::text),
    'scope_wave_request_id',r.id,
    'batch_id',i.batch_id,
    'scope_type',r.scope_type,
    'scope_id',r.scope_id,
    'country_code',r.country_code,
    'route_mode',r.route_mode,
    'lineage_version','a26-v1'
  )
  from pipeline.layer2_run_items i
  join pipeline.layer2_scope_wave_items wi on wi.batch_id=i.batch_id and wi.course_id=i.entity_id
  join pipeline.layer2_scope_wave_requests r on r.id=wi.request_id
  where i.job_id=p_job_id
  order by wi.ordinal
  limit 1
$$;
revoke all on function security.layer2_lineage_for_job(uuid) from public,anon,authenticated;
grant execute on function security.layer2_lineage_for_job(uuid) to service_role;

create or replace function security.layer2_run_item_job_lineage_stamp()
returns trigger
language plpgsql
security definer
set search_path='pg_catalog','pipeline','security'
as $$
declare v_lineage jsonb;
begin
  if new.job_id is null then return new; end if;
  v_lineage:=security.layer2_lineage_for_job(new.job_id);
  if v_lineage is null then return new; end if;

  update pipeline.jobs
  set payload=coalesce(payload,'{}'::jsonb)||jsonb_build_object('layer2_lineage',v_lineage)
  where id=new.job_id;

  update pipeline.evidence_artifacts
  set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('layer2_lineage',v_lineage)
  where job_id=new.job_id;

  return new;
end $$;
revoke all on function security.layer2_run_item_job_lineage_stamp() from public,anon,authenticated;

drop trigger if exists trg_layer2_run_item_job_lineage_stamp on pipeline.layer2_run_items;
create trigger trg_layer2_run_item_job_lineage_stamp
after insert or update of job_id on pipeline.layer2_run_items
for each row execute function security.layer2_run_item_job_lineage_stamp();

create or replace function security.layer2_evidence_lineage_stamp()
returns trigger
language plpgsql
security definer
set search_path='pg_catalog','pipeline','security'
as $$
declare v_lineage jsonb;
begin
  if new.job_id is null then return new; end if;
  v_lineage:=security.layer2_lineage_for_job(new.job_id);
  if v_lineage is not null then
    new.metadata:=coalesce(new.metadata,'{}'::jsonb)||jsonb_build_object('layer2_lineage',v_lineage);
  end if;
  return new;
end $$;
revoke all on function security.layer2_evidence_lineage_stamp() from public,anon,authenticated;

drop trigger if exists trg_layer2_evidence_lineage_stamp on pipeline.evidence_artifacts;
create trigger trg_layer2_evidence_lineage_stamp
before insert on pipeline.evidence_artifacts
for each row execute function security.layer2_evidence_lineage_stamp();

create or replace function security.admin_layer2_parent_runs(p_limit integer default 10)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','security','pipeline','auth'
as $$
declare v_rank integer:=0; v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb)
  into v_result
  from (
    select
      coalesce(r.metadata->>'parent_run_id',r.id::text) parent_run_id,
      r.id scope_wave_request_id,
      r.status,r.country_code,r.scope_type,r.scope_id,r.route_mode,
      r.total_items,r.dispatched_items,r.completed_items,r.failed_items,
      greatest(r.total_items-r.dispatched_items,0) scheduled_remainder,
      r.last_wave_at,r.next_wave_not_before,r.created_at,r.updated_at,
      count(distinct wi.batch_id) filter(where wi.batch_id is not null)::int child_batches,
      count(distinct i.job_id) filter(where i.job_id is not null)::int child_jobs,
      count(distinct e.id)::int evidence_count,
      coalesce(sum(b.processed_count) filter(where b.id is not null),0)::int processed_items,
      coalesce(sum(b.resolved_l2_count) filter(where b.id is not null),0)::int resolved_l2,
      coalesce(sum(b.escalated_l3_count) filter(where b.id is not null),0)::int escalated_l3,
      coalesce(sum(b.blocked_count) filter(where b.id is not null),0)::int blocked
    from pipeline.layer2_scope_wave_requests r
    left join pipeline.layer2_scope_wave_items wi on wi.request_id=r.id
    left join pipeline.layer2_run_batches b on b.id=wi.batch_id
    left join pipeline.layer2_run_items i on i.batch_id=b.id and i.entity_id=wi.course_id
    left join pipeline.evidence_artifacts e on e.job_id=i.job_id
    group by r.id
    order by r.created_at desc
    limit greatest(1,least(coalesce(p_limit,10),50))
  ) x;
  return v_result;
end $$;
revoke all on function security.admin_layer2_parent_runs(integer) from public,anon;
grant execute on function security.admin_layer2_parent_runs(integer) to authenticated,service_role;

-- Backfill existing production requests from the terminal qualification run that recorded them.
with terminal as (
  select q.id terminal_id,
         nullif(q.result_summary->'production_result'->>'request_id','')::uuid request_id,
         security.layer2_qualification_root(q.id) root_id
  from pipeline.layer2_scale_qualification_runs q
  where nullif(q.result_summary->'production_result'->>'request_id','') is not null
)
update pipeline.layer2_scope_wave_requests r
set metadata=coalesce(r.metadata,'{}'::jsonb)||jsonb_build_object(
  'parent_run_id',t.root_id,
  'parent_run_kind','qualification_root',
  'qualification_terminal_run_id',t.terminal_id,
  'scope_wave_request_id',r.id,
  'lineage_version','a26-v1'
)
from terminal t
where t.request_id=r.id;

-- Backfill batch lineage for any existing wave-linked batches.
update pipeline.layer2_run_batches b
set policy_snapshot=coalesce(b.policy_snapshot,'{}'::jsonb)||jsonb_build_object(
  'parent_run_id',coalesce(r.metadata->>'parent_run_id',r.id::text),
  'scope_wave_request_id',r.id,
  'scope_type',r.scope_type,
  'scope_id',r.scope_id,
  'country_code',r.country_code,
  'route_mode',r.route_mode,
  'lineage_version','a26-v1'
),
updated_at=now()
from pipeline.layer2_scope_wave_items wi
join pipeline.layer2_scope_wave_requests r on r.id=wi.request_id
where wi.batch_id=b.id;

-- Backfill Jobs/Evidence after batch lineage is known.
update pipeline.jobs j
set payload=coalesce(j.payload,'{}'::jsonb)||jsonb_build_object('layer2_lineage',security.layer2_lineage_for_job(j.id))
where exists(select 1 from pipeline.layer2_run_items i where i.job_id=j.id)
  and security.layer2_lineage_for_job(j.id) is not null;

update pipeline.evidence_artifacts e
set metadata=coalesce(e.metadata,'{}'::jsonb)||jsonb_build_object('layer2_lineage',security.layer2_lineage_for_job(e.job_id))
where e.job_id is not null
  and security.layer2_lineage_for_job(e.job_id) is not null;

-- Extend public admin dispatcher with the bounded parent-run projection.
do $$
declare v_oid oid; v_def text;
begin
  select p.oid into v_oid
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='admin_read'
    and pg_get_function_identity_arguments(p.oid)='p_operation text, p_args jsonb'
  limit 1;
  select pg_get_functiondef(v_oid) into v_def;
  if position('layer2_parent_runs' in v_def)=0 then
    v_def:=replace(
      v_def,
      'if p_operation=''layer2_ops_alerts'' then return security.layer2_operational_alerts_read(); end if;',
      'if p_operation=''layer2_ops_alerts'' then return security.layer2_operational_alerts_read(); end if;
 if p_operation=''layer2_parent_runs'' then return security.admin_layer2_parent_runs(coalesce(nullif(p_args->>''limit'','''')::integer,10)); end if;'
    );
    execute v_def;
  end if;
end $$;
