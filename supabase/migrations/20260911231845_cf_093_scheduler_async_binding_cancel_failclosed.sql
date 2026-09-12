begin;

-- Recovery hardening: an async continuation must never fall back to the legacy path after
-- a scheduler binding is cancelled or has handed off. Match the exact actor/profile/full
-- sync set regardless of binding state, then fail closed unless it is active.
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
  end if;

  v_req:=pipeline.svc_pilot_submit_nonce('layer2-scope-discover-scheduled',jsonb_build_object('profile_id',p_profile_id,'limit',least(greatest(coalesce(p_limit,50),1),50),'course_ids',to_jsonb(p_course_ids),'auto_sync_actor',p_actor,'sync_course_ids',to_jsonb(coalesce(p_sync_course_ids,p_course_ids))));
  return jsonb_build_object('ok',true,'profile_id',p_profile_id,'request_id',v_req,'course_count',array_length(p_course_ids,1),'scheduler_preview_token',case when v_bound then v_binding.preview_token else null end);
end
$function$;
revoke all on function security.layer2_discovery_scope_dispatch_v2(uuid,uuid[],integer,uuid,uuid[]) from public,anon,authenticated;
grant execute on function security.layer2_discovery_scope_dispatch_v2(uuid,uuid[],integer,uuid,uuid[]) to service_role;

commit;
