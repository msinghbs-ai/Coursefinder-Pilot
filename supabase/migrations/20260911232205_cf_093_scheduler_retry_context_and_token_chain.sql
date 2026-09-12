begin;

-- CF-CHG-20260910-093 forward-only recovery correction.
-- Historical discovery dispositions are Evidence/history, not proof that a currently
-- missing Course URL is resolved. Scheduler-bound retries may therefore revisit the exact
-- Preview-bound missing set without deleting prior candidates. The exact Preview token is
-- carried through every nonce continuation and validated server-side.

create or replace function security.layer2_scheduler_discovery_context_v1(
  p_preview_token uuid,
  p_profile_id uuid,
  p_course_ids uuid[],
  p_limit integer default 50
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_binding pipeline.scheduler_workflow_async_bindings%rowtype;
  v_ctx jsonb;
  v_courses jsonb;
  v_resolved jsonb;
  v_requested uuid[];
  v_requested_count integer:=0;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  if p_preview_token is null or p_profile_id is null then raise exception 'scheduler preview/profile binding required' using errcode='22023'; end if;
  select coalesce(array_agg(distinct x order by x),'{}'::uuid[]) into v_requested from unnest(coalesce(p_course_ids,'{}'::uuid[])) x;
  v_requested_count:=cardinality(v_requested);
  if v_requested_count=0 or v_requested_count>1000 then raise exception 'bounded course_ids required' using errcode='22023'; end if;

  select * into v_binding
  from pipeline.scheduler_workflow_async_bindings b
  where b.preview_token=p_preview_token and b.profile_id=p_profile_id
  for update;
  if not found then raise exception 'scheduler async binding not found' using errcode='22023'; end if;
  if v_binding.status<>'active' then raise exception 'scheduler async binding is not active' using errcode='22023'; end if;
  if v_binding.execution_expires_at is null or v_binding.execution_expires_at<=now() then raise exception 'scheduler async execution binding expired' using errcode='22023'; end if;
  if not (v_binding.discovery_course_ids @> v_requested) then raise exception 'requested discovery chunk is outside the exact Preview-bound set' using errcode='22023'; end if;

  select public.layer2_runtime_context(p_profile_id) into v_ctx;
  if v_ctx is null or v_ctx->>'domain'<>'course_facts' then raise exception 'course_facts profile required' using errcode='22023'; end if;
  if nullif(v_ctx->>'version_id','')::uuid<>v_binding.profile_version_id then raise exception 'profile version changed after Preview' using errcode='22023'; end if;

  -- A post-activation selected URL is already resolved for this exact run and is consumed
  -- without reacquisition. Historical non-selected dispositions remain retryable.
  with requested as (
    select unnest(v_requested) course_id
  ), resolved as (
    select r.course_id
    from requested r
    where exists(
      select 1 from pipeline.layer2_course_discovery_candidates d
      where d.course_id=r.course_id
        and d.source_profile_version_id=v_binding.profile_version_id
        and d.selected=true
        and nullif(d.discovered_url,'') is not null
        and d.created_at>=v_binding.activated_at
    )
  ), unresolved as (
    select r.course_id from requested r
    where not exists(select 1 from resolved x where x.course_id=r.course_id)
  ), bounded as (
    select c.id,c.canonical_title,c.display_title,c.course_code
    from unresolved u
    join catalogue.courses c on c.id=u.course_id
    join pipeline.sources s on s.provider_id=c.provider_id
    join pipeline.layer2_source_profiles lp on lp.source_id=s.id and lp.id=p_profile_id
    order by c.canonical_title,c.id
    limit least(greatest(coalesce(p_limit,50),1),50)
  )
  select coalesce((select jsonb_agg(to_jsonb(b) order by b.canonical_title,b.id) from bounded b),'[]'::jsonb),
         coalesce((select jsonb_agg(r.course_id order by r.course_id) from resolved r),'[]'::jsonb)
    into v_courses,v_resolved;

  return jsonb_build_object(
    'runtime',v_ctx,
    'courses',v_courses,
    'scheduler_preview_token',p_preview_token,
    'requested_count',v_requested_count,
    'resolved_course_ids',v_resolved,
    'resolved_count',jsonb_array_length(v_resolved),
    'historical_dispositions_are_retryable',true
  );
end
$function$;
revoke all on function security.layer2_scheduler_discovery_context_v1(uuid,uuid,uuid[],integer) from public,anon,authenticated;
grant execute on function security.layer2_scheduler_discovery_context_v1(uuid,uuid,uuid[],integer) to service_role;

-- Preserve the established signature used by the worker. When the call belongs to a
-- scheduler-bound run, include the exact Preview token in the nonce payload. Every later
-- continuation re-resolves the same durable binding and carries the same token.
create or replace function security.layer2_discovery_scope_dispatch_v2(
  p_profile_id uuid,
  p_course_ids uuid[],
  p_limit integer,
  p_actor uuid,
  p_sync_course_ids uuid[]
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','pipeline','security'
as $function$
declare
  v_req bigint;
  v_preview_token uuid;
  v_binding pipeline.scheduler_workflow_async_bindings%rowtype;
  v_snapshot jsonb;
  v_sync uuid[];
  v_requested uuid[];
  v_bound boolean:=false;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  if p_course_ids is null or coalesce(array_length(p_course_ids,1),0)=0 then raise exception 'course_ids required' using errcode='22023'; end if;
  if array_length(p_course_ids,1)>1000 or coalesce(array_length(p_sync_course_ids,1),0)>1000 then raise exception 'course_ids exceeds 1000' using errcode='22023'; end if;
  if not exists(select 1 from pipeline.layer2_source_profiles where id=p_profile_id and domain='course_facts' and enabled and not paused) then raise exception 'enabled course_facts profile required' using errcode='22023'; end if;
  select coalesce(array_agg(distinct x order by x),'{}'::uuid[]) into v_requested from unnest(p_course_ids) x;
  select coalesce(array_agg(distinct x order by x),'{}'::uuid[]) into v_sync from unnest(coalesce(p_sync_course_ids,p_course_ids)) x;
  begin v_preview_token:=nullif(current_setting('coursefinder.scheduler_preview_token',true),'')::uuid; exception when others then v_preview_token:=null; end;

  if v_preview_token is not null then
    select * into v_binding from pipeline.scheduler_workflow_async_bindings b
    where b.preview_token=v_preview_token and b.actor_id=p_actor and b.profile_id=p_profile_id
    for update;
    v_bound:=found;
  elsif p_actor is not null then
    select * into v_binding from pipeline.scheduler_workflow_async_bindings b
    where b.actor_id=p_actor and b.profile_id=p_profile_id and b.sync_course_ids=v_sync
      and b.discovery_course_ids @> v_requested
    order by b.created_at desc limit 1 for update;
    v_bound:=found;
  end if;

  if v_bound then
    if v_binding.sync_course_ids<>v_sync then raise exception 'scheduler async binding sync scope mismatch' using errcode='22023'; end if;
    if not (v_binding.discovery_course_ids @> v_requested) then raise exception 'scheduler async binding discovery scope mismatch' using errcode='22023'; end if;
    if v_binding.status='prepared' then
      if v_preview_token is null or v_binding.preview_token<>v_preview_token then raise exception 'exact scheduler preview token required to activate async discovery' using errcode='22023'; end if;
      if v_binding.preview_expires_at<=now() then raise exception 'scheduler async preview binding expired; preview again' using errcode='22023'; end if;
      if v_requested<>v_binding.discovery_course_ids then raise exception 'initial scheduler discovery dispatch must match the exact preview-bound discovery set' using errcode='22023'; end if;
      perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('cf093-async|'||p_profile_id::text,0));
      if exists(select 1 from pipeline.scheduler_workflow_async_bindings x where x.profile_id=p_profile_id and x.status='active' and x.preview_token<>v_binding.preview_token) then raise exception 'another scheduler async binding is active for this Layer 2 profile' using errcode='55000'; end if;
      v_snapshot:=security.scheduler_workflow_profile_binding_snapshot_v1(p_profile_id,v_binding.sync_course_ids,v_binding.discovery_course_ids);
      if v_snapshot is null or (v_snapshot->>'profile_version_id')::uuid<>v_binding.profile_version_id or v_snapshot->>'identity_fingerprint'<>v_binding.identity_fingerprint or v_snapshot->>'queueable_fingerprint'<>v_binding.queueable_fingerprint or coalesce((v_snapshot->>'all_ids_valid')::boolean,false)=false or coalesce((v_snapshot->>'all_discovery_missing')::boolean,false)=false then raise exception 'scheduler async discovery inputs changed after Preview; preview again' using errcode='22023'; end if;
      update pipeline.scheduler_workflow_async_bindings set status='active',activated_at=now(),execution_expires_at=now()+interval '6 hours' where preview_token=v_binding.preview_token and profile_id=v_binding.profile_id returning * into v_binding;
    elsif v_binding.status<>'active' then
      raise exception 'scheduler async binding is not active; continuation rejected' using errcode='22023';
    end if;
    if v_binding.execution_expires_at is null or v_binding.execution_expires_at<=now() then raise exception 'scheduler async execution binding expired; operator review required' using errcode='22023'; end if;
    v_snapshot:=security.scheduler_workflow_profile_binding_snapshot_v1(p_profile_id,v_binding.sync_course_ids,v_binding.discovery_course_ids);
    if v_snapshot is null or (v_snapshot->>'profile_version_id')::uuid<>v_binding.profile_version_id or v_snapshot->>'identity_fingerprint'<>v_binding.identity_fingerprint or v_snapshot->>'queueable_fingerprint'<>v_binding.queueable_fingerprint or coalesce((v_snapshot->>'all_ids_valid')::boolean,false)=false then raise exception 'scheduler async bound profile/course identity changed during discovery; stop and preview again' using errcode='22023'; end if;
    v_preview_token:=v_binding.preview_token;
  end if;

  v_req:=pipeline.svc_pilot_submit_nonce(
    'layer2-scope-discover-scheduled',
    jsonb_build_object(
      'profile_id',p_profile_id,
      'limit',least(greatest(coalesce(p_limit,50),1),50),
      'course_ids',to_jsonb(p_course_ids),
      'auto_sync_actor',p_actor,
      'sync_course_ids',to_jsonb(coalesce(p_sync_course_ids,p_course_ids)),
      'scheduler_preview_token',case when v_bound then v_preview_token else null end
    )
  );
  return jsonb_build_object('ok',true,'profile_id',p_profile_id,'request_id',v_req,'course_count',array_length(p_course_ids,1),'scheduler_preview_token',case when v_bound then v_preview_token else null end);
end
$function$;
revoke all on function security.layer2_discovery_scope_dispatch_v2(uuid,uuid[],integer,uuid,uuid[]) from public,anon,authenticated;
grant execute on function security.layer2_discovery_scope_dispatch_v2(uuid,uuid[],integer,uuid,uuid[]) to service_role;

commit;
