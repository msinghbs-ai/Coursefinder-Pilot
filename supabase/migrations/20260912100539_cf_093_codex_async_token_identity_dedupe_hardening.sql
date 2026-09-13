create or replace function public.layer2_discovery_context_scope_bound_v1(
  p_preview_token uuid,
  p_actor uuid,
  p_profile_id uuid,
  p_course_ids uuid[] default '{}'::uuid[],
  p_limit integer default 50
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','pipeline','catalogue','public','security'
as $$
declare
  v_ctx jsonb;
  v_provider uuid;
  v_courses jsonb;
  v_binding pipeline.scheduler_workflow_async_bindings%rowtype;
  v_requested uuid[];
  v_snapshot jsonb;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  if p_preview_token is null or p_actor is null or p_profile_id is null then raise exception 'preview token, actor and profile required' using errcode='22023'; end if;
  select coalesce(array_agg(distinct x order by x),'{}'::uuid[]) into v_requested from unnest(coalesce(p_course_ids,'{}'::uuid[])) x;
  if cardinality(v_requested)=0 then raise exception 'scheduler bound discovery requires explicit course_ids' using errcode='22023'; end if;

  select * into v_binding
  from pipeline.scheduler_workflow_async_bindings b
  where b.preview_token=p_preview_token and b.actor_id=p_actor and b.profile_id=p_profile_id
  for update;
  if not found then raise exception 'exact scheduler async binding not found' using errcode='22023'; end if;
  if v_binding.status<>'active' then raise exception 'scheduler async binding is not active' using errcode='22023'; end if;
  if v_binding.execution_expires_at is null or v_binding.execution_expires_at<=now() then raise exception 'scheduler async execution binding expired' using errcode='22023'; end if;
  if not (v_binding.discovery_course_ids @> v_requested) then raise exception 'discovery chunk is outside exact scheduler binding' using errcode='22023'; end if;

  v_snapshot:=security.scheduler_workflow_profile_binding_snapshot_v1(p_profile_id,v_binding.sync_course_ids,v_binding.discovery_course_ids);
  if v_snapshot is null
     or (v_snapshot->>'profile_version_id')::uuid<>v_binding.profile_version_id
     or v_snapshot->>'identity_fingerprint'<>v_binding.identity_fingerprint
     or v_snapshot->>'queueable_fingerprint'<>v_binding.queueable_fingerprint
     or coalesce((v_snapshot->>'all_ids_valid')::boolean,false)=false
     or coalesce((v_snapshot->>'discovery_subset_valid')::boolean,false)=false
  then raise exception 'scheduler async bound profile/course identity changed before discovery Evidence write' using errcode='22023'; end if;

  select public.layer2_runtime_context(p_profile_id) into v_ctx;
  if v_ctx is null or v_ctx->>'domain'<>'course_facts' then raise exception 'course_facts profile required' using errcode='22023'; end if;
  if nullif(v_ctx->>'version_id','')::uuid<>v_binding.profile_version_id then raise exception 'scheduler bound profile version changed' using errcode='22023'; end if;
  select s.provider_id into v_provider from pipeline.sources s where s.id=(v_ctx->>'source_id')::uuid;
  if v_provider is null then raise exception 'profile source is not bound to a canonical provider' using errcode='22023'; end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.canonical_title,x.id),'[]'::jsonb) into v_courses
  from (
    select c.id,c.canonical_title,c.display_title,c.course_code
    from catalogue.courses c
    where c.provider_id=v_provider and c.id=any(v_requested)
      and not exists(
        select 1 from pipeline.layer2_course_discovery_candidates dc
        where dc.course_id=c.id and dc.source_profile_version_id=v_binding.profile_version_id
          and dc.selected=true and nullif(dc.discovered_url,'') is not null and dc.created_at>=v_binding.activated_at
      )
    order by c.canonical_title,c.id
    limit least(greatest(coalesce(p_limit,50),1),50)
  ) x;

  return jsonb_build_object(
    'runtime',v_ctx,'canonical_provider_id',v_provider,'courses',v_courses,
    'scheduler_preview_token',v_binding.preview_token,'scheduler_bound_retry',true,
    'identity_revalidated',true,'historical_dispositions_preserved',true
  );
end $$;

revoke all on function public.layer2_discovery_context_scope_bound_v1(uuid,uuid,uuid,uuid[],integer) from public,anon,authenticated;
grant execute on function public.layer2_discovery_context_scope_bound_v1(uuid,uuid,uuid,uuid[],integer) to service_role;

create or replace function public.layer2_discovery_scope_dispatch_bound_v1(
  p_preview_token uuid,
  p_actor uuid,
  p_profile_id uuid,
  p_course_ids uuid[],
  p_limit integer,
  p_sync_course_ids uuid[]
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','security'
as $$
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  if p_preview_token is null or p_actor is null then raise exception 'exact preview token and actor required' using errcode='22023'; end if;
  perform set_config('coursefinder.scheduler_preview_token',p_preview_token::text,true);
  return security.layer2_discovery_scope_dispatch_v2(p_profile_id,p_course_ids,p_limit,p_actor,p_sync_course_ids);
end $$;
revoke all on function public.layer2_discovery_scope_dispatch_bound_v1(uuid,uuid,uuid,uuid[],integer,uuid[]) from public,anon,authenticated;
grant execute on function public.layer2_discovery_scope_dispatch_bound_v1(uuid,uuid,uuid,uuid[],integer,uuid[]) to service_role;

create or replace function public.layer2_scope_profile_batch_bound_v1(
  p_preview_token uuid,
  p_actor uuid,
  p_profile_id uuid,
  p_course_ids uuid[]
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','pipeline'
as $$
declare v_result jsonb;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  if p_preview_token is null or p_actor is null then raise exception 'exact preview token and actor required' using errcode='22023'; end if;
  perform set_config('coursefinder.scheduler_preview_token',p_preview_token::text,true);
  v_result:=public.layer2_scope_profile_batch_service(p_actor,p_profile_id,p_course_ids);
  if coalesce(v_result->>'status','')='started' and nullif(v_result->>'batch_id','') is not null then
    update pipeline.jobs j
    set result=coalesce(j.result,'{}'::jsonb)||jsonb_build_object(
      'async_handoffs',coalesce(j.result->'async_handoffs','[]'::jsonb)||jsonb_build_array(jsonb_build_object(
        'profile_id',p_profile_id,'batch_id',(v_result->>'batch_id')::uuid,
        'dispatch_request_id',nullif(v_result->>'dispatch_request_id','')::bigint,'recorded_at',now()
      ))
    )
    where j.id=p_preview_token and j.job_type='scheduler_workflow_preview' and j.requested_by=p_actor;
  end if;
  return v_result;
end $$;
revoke all on function public.layer2_scope_profile_batch_bound_v1(uuid,uuid,uuid,uuid[]) from public,anon,authenticated;
grant execute on function public.layer2_scope_profile_batch_bound_v1(uuid,uuid,uuid,uuid[]) to service_role;

create or replace function security.scheduler_workflow_dispatch_dedupe_anchor_v1(
  p_dispatch_result jsonb,
  p_consumed_at timestamptz
) returns timestamptz
language sql
stable
security definer
set search_path to ''
as $$
with preview_job as (
  select j.id,j.result
  from pipeline.jobs j
  where j.job_type='scheduler_workflow_preview'
    and j.payload->'dispatch_result'=p_dispatch_result
    and nullif(j.payload->>'consumed_at','') is not null
    and (j.payload->>'consumed_at')::timestamptz=p_consumed_at
  order by j.created_at desc limit 1
), direct_ids as (
  select distinct nullif(e->>'batch_id','')::uuid batch_id
  from jsonb_array_elements(coalesce(p_dispatch_result->'profiles','[]'::jsonb)) e
  where nullif(e->>'batch_id','') is not null
), async_ids as (
  select distinct nullif(e->>'batch_id','')::uuid batch_id
  from preview_job j
  cross join lateral jsonb_array_elements(coalesce(j.result->'async_handoffs','[]'::jsonb)) e
  where nullif(e->>'batch_id','') is not null
  union
  select nullif(j.result->'async_handoff'->>'batch_id','')::uuid
  from preview_job j where nullif(j.result->'async_handoff'->>'batch_id','') is not null
), batch_ids as (
  select batch_id from direct_ids union select batch_id from async_ids
), stats as (
  select count(*)::integer referenced_count,
         count(b.id)::integer found_count,
         count(*) filter(where b.status in ('completed','partial') and b.completed_at is not null)::integer reusable_count,
         max(b.completed_at) as latest_completed_at
  from batch_ids x left join pipeline.layer2_run_batches b on b.id=x.batch_id
)
select case
  when referenced_count=0 then p_consumed_at
  when found_count=referenced_count and reusable_count=referenced_count then latest_completed_at
  else null
end from stats
$$;
revoke all on function security.scheduler_workflow_dispatch_dedupe_anchor_v1(jsonb,timestamptz) from public,anon,authenticated;
grant execute on function security.scheduler_workflow_dispatch_dedupe_anchor_v1(jsonb,timestamptz) to authenticated,service_role;

create or replace function security.scheduler_workflow_async_binding_cancel_v1(
  p_actor uuid,
  p_preview_token uuid,
  p_reason text
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_reason text:=trim(coalesce(p_reason,''));
  v_total integer:=0; v_changed integer:=0; v_blocked integer:=0; v_profiles jsonb;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  if p_actor is null or p_preview_token is null then raise exception 'actor and preview token required' using errcode='22023'; end if;
  if length(v_reason)<5 then raise exception 'cancellation reason required' using errcode='22023'; end if;

  perform 1 from pipeline.scheduler_workflow_async_bindings b where b.preview_token=p_preview_token and b.actor_id=p_actor for update;
  select count(*),count(*) filter(where status not in ('prepared','active','cancelled')),
         coalesce(jsonb_agg(jsonb_build_object('profile_id',profile_id,'status',status) order by profile_id),'[]'::jsonb)
  into v_total,v_blocked,v_profiles
  from pipeline.scheduler_workflow_async_bindings b where b.preview_token=p_preview_token and b.actor_id=p_actor;
  if v_total=0 then raise exception 'scheduler async binding not found for actor' using errcode='22023'; end if;
  if v_blocked>0 then raise exception 'one or more scheduler async bindings cannot be cancelled from current status' using errcode='22023'; end if;

  update pipeline.scheduler_workflow_async_bindings
  set status='cancelled',execution_expires_at=least(coalesce(execution_expires_at,now()),now())
  where preview_token=p_preview_token and actor_id=p_actor and status in ('prepared','active');
  get diagnostics v_changed=row_count;

  update pipeline.jobs
  set payload=coalesce(payload,'{}'::jsonb)||jsonb_build_object(
    'async_binding_cancelled_at',now(),'async_binding_cancelled_by',p_actor,
    'async_binding_cancellation_reason',v_reason,'change_control_ref','CF-CHG-20260910-093'
  )
  where id=p_preview_token and job_type='scheduler_workflow_preview' and requested_by=p_actor;

  return jsonb_build_object('ok',true,'preview_token',p_preview_token,'binding_count',v_total,
    'cancelled_count',v_changed,'profiles',v_profiles,'status','cancelled','idempotent_replay',v_changed=0);
end $$;

create or replace function security.scheduler_workflow_preview_v1_browser_bridge_guarded(
  p_workflow_key text,
  p_country_code text,
  p_scope_type text,
  p_scope_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare v_result jsonb; v_token uuid; v_actionable integer;
begin
  v_result:=security.scheduler_workflow_preview_v1_browser_bridge(p_workflow_key,p_country_code,p_scope_type,p_scope_id);
  v_actionable:=coalesce((v_result->>'queueable_count')::integer,0)+coalesce((v_result->>'needs_discovery_count')::integer,0);
  if coalesce((v_result->>'executable')::boolean,false)=true and v_actionable<=0 then
    v_token:=nullif(v_result->>'preview_token','')::uuid;
    v_result:=v_result||jsonb_build_object('executable',false,'execution_block_reason','No actionable Layer 2 work remains; the scope contains only current governed terminal outcomes.','preview_token',null,'preview_expires_at',null,'async_discovery_preview_bound',false);
    if v_token is not null then
      update pipeline.jobs set result=v_result,payload=payload||jsonb_build_object('superseded_non_actionable_preview',true,'superseded_at',now())
      where id=v_token and job_type='scheduler_workflow_preview' and requested_by=auth.uid();
    end if;
  end if;
  return v_result;
end $$;
revoke all on function security.scheduler_workflow_preview_v1_browser_bridge_guarded(text,text,text,uuid) from public,anon;
grant execute on function security.scheduler_workflow_preview_v1_browser_bridge_guarded(text,text,text,uuid) to authenticated,service_role;

create or replace function public.scheduler_workflow_preview_v1(
  p_workflow_key text,
  p_country_code text,
  p_scope_type text,
  p_scope_id uuid default null
) returns jsonb
language sql
set search_path to ''
as $$
  select security.scheduler_workflow_preview_v1_browser_bridge_guarded(p_workflow_key,p_country_code,p_scope_type,p_scope_id)
$$;