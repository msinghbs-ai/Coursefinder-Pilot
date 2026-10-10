begin;

-- CF-CHG-20260910-093 forward-only capability completion.
-- Permit discovery-backed AU Course Facts Scheduled Tasks only when every asynchronous
-- continuation is bound to the exact actor/profile/version/course identity set created
-- by the server Preview. This does not create execution policies, broaden Layer 3/4,
-- or authorise Search/Publication effects.

create table pipeline.scheduler_workflow_async_bindings (
  preview_token uuid not null references pipeline.jobs(id) on delete cascade,
  actor_id uuid not null,
  profile_id uuid not null references pipeline.layer2_source_profiles(id),
  profile_version_id uuid not null references pipeline.layer2_source_profile_versions(id),
  country_code text not null,
  scope_type text not null,
  scope_id uuid,
  scope_fingerprint text not null,
  identity_fingerprint text not null,
  queueable_fingerprint text not null,
  sync_course_ids uuid[] not null,
  discovery_course_ids uuid[] not null,
  status text not null default 'prepared',
  created_at timestamptz not null default now(),
  preview_expires_at timestamptz not null,
  activated_at timestamptz,
  execution_expires_at timestamptz,
  handoff_started_at timestamptz,
  primary key (preview_token,profile_id),
  constraint scheduler_workflow_async_bindings_status_ck
    check (status in ('prepared','active','handoff_started','cancelled')),
  constraint scheduler_workflow_async_bindings_scope_ck
    check (country_code='AU' and scope_type in ('country','state','university')),
  constraint scheduler_workflow_async_bindings_course_sets_ck
    check (cardinality(sync_course_ids)>0 and discovery_course_ids <@ sync_course_ids)
);

alter table pipeline.scheduler_workflow_async_bindings enable row level security;
revoke all on table pipeline.scheduler_workflow_async_bindings from public,anon,authenticated;
create unique index scheduler_workflow_async_bindings_one_active_profile_idx
  on pipeline.scheduler_workflow_async_bindings(profile_id)
  where status='active';
create index scheduler_workflow_async_bindings_actor_profile_idx
  on pipeline.scheduler_workflow_async_bindings(actor_id,profile_id,created_at desc);

create or replace function security.scheduler_workflow_profile_binding_snapshot_v1(
  p_profile_id uuid,
  p_sync_course_ids uuid[],
  p_discovery_course_ids uuid[] default '{}'::uuid[]
) returns jsonb
language sql
stable
security definer
set search_path=''
as $function$
  with profile_ctx as (
    select lp.id profile_id,lp.current_version_id,s.provider_id
    from pipeline.layer2_source_profiles lp
    join pipeline.sources s on s.id=lp.source_id
    where lp.id=p_profile_id
      and lp.domain='course_facts'
      and lp.enabled
      and not lp.paused
  ), sync_ids as (
    select coalesce(array_agg(distinct x order by x),'{}'::uuid[]) ids
    from unnest(coalesce(p_sync_course_ids,'{}'::uuid[])) x
  ), discovery_ids as (
    select coalesce(array_agg(distinct x order by x),'{}'::uuid[]) ids
    from unnest(coalesce(p_discovery_course_ids,'{}'::uuid[])) x
  ), rows as materialized (
    select c.id course_id,c.course_code,c.canonical_title,c.display_title,
           coalesce(nullif(dc.discovered_url,''),nullif(c.course_url,'')) source_url
    from profile_ctx p
    cross join sync_ids si
    join catalogue.courses c on c.provider_id=p.provider_id and c.id=any(si.ids)
    left join lateral (
      select d.discovered_url
      from pipeline.layer2_course_discovery_candidates d
      where d.course_id=c.id
        and d.source_profile_version_id=p.current_version_id
        and d.selected=true
        and nullif(d.discovered_url,'') is not null
      order by d.created_at desc
      limit 1
    ) dc on true
  ), valueset as (
    select p.profile_id,p.current_version_id,si.ids sync_ids,di.ids discovery_ids,
           count(r.course_id)::integer course_count,
           md5(coalesce(jsonb_agg(
             jsonb_build_array(
               p.profile_id::text,p.current_version_id::text,r.course_id::text,
               coalesce(r.course_code,''),coalesce(r.canonical_title,''),coalesce(r.display_title,'')
             ) order by r.course_id
           ),'[]'::jsonb)::text) identity_fingerprint,
           md5(coalesce(jsonb_agg(
             jsonb_build_array(r.course_id::text,coalesce(r.source_url,'<missing>'))
             order by r.course_id
           ) filter (where not (r.course_id=any(di.ids))),'[]'::jsonb)::text) queueable_fingerprint,
           count(*) filter(where r.course_id=any(di.ids) and r.source_url is null)::integer discovery_missing_count
    from profile_ctx p cross join sync_ids si cross join discovery_ids di
    left join rows r on true
    group by p.profile_id,p.current_version_id,si.ids,di.ids
  )
  select jsonb_build_object(
    'profile_id',v.profile_id,
    'profile_version_id',v.current_version_id,
    'sync_course_ids',to_jsonb(v.sync_ids),
    'discovery_course_ids',to_jsonb(v.discovery_ids),
    'course_count',v.course_count,
    'identity_fingerprint',v.identity_fingerprint,
    'queueable_fingerprint',v.queueable_fingerprint,
    'all_ids_valid',v.course_count=cardinality(v.sync_ids),
    'discovery_subset_valid',v.discovery_ids <@ v.sync_ids,
    'all_discovery_missing',v.discovery_missing_count=cardinality(v.discovery_ids)
  )
  from valueset v
$function$;
revoke all on function security.scheduler_workflow_profile_binding_snapshot_v1(uuid,uuid[],uuid[]) from public,anon,authenticated;

-- With Preview-bound async inputs available, this function once again distinguishes
-- malformed discovery configuration from supported discovery work. Queueable URL checks
-- retain the literal allowlist semantics of layer2-acquire-v2.
create or replace function security.scheduler_workflow_discovery_config_gap_count_v1(
  p_country_code text,
  p_scope_type text,
  p_scope_id uuid default null
) returns integer
language sql
stable
security definer
set search_path=''
as $function$
  with scoped as materialized (
    select sc.profile_id,sc.course_id,sc.source_url
    from public.layer2_scope_courses(upper(p_country_code),lower(p_scope_type),p_scope_id) sc
  ), discovery_profiles as (
    select distinct s.profile_id
    from scoped s
    where s.source_url is null
  ), discovery_targets as (
    select d.profile_id,
      case
        when lower(coalesce(pv.configuration#>>'{discovery_strategy,type}',''))='first_party_search'
             and nullif(trim(coalesce(pv.configuration#>>'{discovery_strategy,search_url_template}','')),'') is not null
          then trim(pv.configuration#>>'{discovery_strategy,search_url_template}')
        when nullif(trim(coalesce(pv.configuration#>>'{discovery_strategy,catalogue_url}','')),'') is not null
          then trim(pv.configuration#>>'{discovery_strategy,catalogue_url}')
        else nullif(trim(coalesce(pv.configuration->>'discovery_url','')),'')
      end target_url
    from discovery_profiles d
    join pipeline.layer2_source_profiles lp on lp.id=d.profile_id
    join pipeline.layer2_source_profile_versions pv on pv.id=lp.current_version_id
  ), invalid_discovery as (
    select profile_id::text||':discovery_target' gap_key
    from discovery_targets
    where security.scheduler_workflow_https_host_v1(replace(coalesce(target_url,''),'{query}','x')) is null
  ), invalid_queueable as (
    select s.profile_id::text||':'||s.course_id::text gap_key
    from scoped s
    where s.source_url is not null
      and not security.scheduler_workflow_queueable_url_allowed_v1(s.profile_id,s.source_url)
  )
  select count(*)::integer
  from (
    select gap_key from invalid_discovery
    union all
    select gap_key from invalid_queueable
  ) gaps
$function$;
revoke all on function security.scheduler_workflow_discovery_config_gap_count_v1(text,text,uuid) from public,anon,authenticated;

create or replace function security.scheduler_workflow_preview_v1_browser_bridge(
  p_workflow_key text,
  p_country_code text,
  p_scope_type text,
  p_scope_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_actor uuid:=auth.uid();
  v_workflow text:=lower(coalesce(trim(p_workflow_key),''));
  v_scope text:=lower(coalesce(trim(p_scope_type),''));
  v_result jsonb; v_snapshot jsonb; v_confirm jsonb; v_preview_id uuid; v_binding jsonb;
  v_invalid_profiles integer:=0; v_policy_gaps integer:=0; v_oversized_profiles integer:=0; v_route_gaps integer:=0; v_discovery_config_gaps integer:=0; v_discovery_count integer:=0;
  v_profile_ids uuid[]:='{}'::uuid[];
  v_preview_expires timestamptz:=now()+interval '15 minutes';
  r record;
begin
  if v_actor is null or security.current_role_rank() < 4 then raise exception 'pipeline operator role required' using errcode='42501'; end if;
  if v_workflow <> 'course_facts_l2' then raise exception 'workflow is not executable from Scheduled Tasks' using errcode='22023'; end if;
  if upper(coalesce(trim(p_country_code),'')) <> 'AU' then raise exception 'only AU Layer 2 Course Facts is currently authorised for this builder' using errcode='22023'; end if;
  if v_scope not in ('country','state','university') then raise exception 'unsupported scope type' using errcode='22023'; end if;
  if v_scope in ('state','university') and p_scope_id is null then raise exception 'scope id required' using errcode='22023'; end if;
  if v_scope='country' and p_scope_id is not null then raise exception 'country scope must not include a scope id' using errcode='22023'; end if;

  v_snapshot:=security.scheduler_workflow_scope_snapshot_v2(upper(p_country_code),v_scope,p_scope_id);
  select coalesce(array_agg((x)::uuid order by (x)::uuid),'{}'::uuid[]) into v_profile_ids
  from jsonb_array_elements_text(coalesce(v_snapshot->'profile_ids','[]'::jsonb)) x;
  v_discovery_count:=coalesce((v_snapshot->>'needs_discovery_count')::integer,0);
  v_result:=coalesce(public.layer2_operator_scope_service(v_actor,'preview',upper(p_country_code),v_scope,p_scope_id),'{}'::jsonb)
    ||jsonb_build_object(
      'queueable_count',coalesce((v_snapshot->>'queueable_count')::integer,0),
      'needs_discovery_count',v_discovery_count,
      'scoped_course_count',coalesce((v_snapshot->>'scoped_course_count')::integer,0),
      'scope_fingerprint',v_snapshot->>'scope_fingerprint'
    );

  select count(distinct sc.profile_id)::integer into v_invalid_profiles
  from public.layer2_scope_courses(upper(p_country_code),v_scope,p_scope_id) sc
  join pipeline.layer2_source_profiles lp on lp.id=sc.profile_id
  left join pipeline.layer2_source_profile_versions pv on pv.id=lp.current_version_id
  where lp.current_version_id is null or pv.id is null or pv.validation_status<>'valid';
  v_policy_gaps:=security.scheduler_workflow_execution_policy_gap_count_v1(upper(p_country_code),v_scope,p_scope_id);
  v_oversized_profiles:=security.scheduler_workflow_oversized_profile_count_v1(upper(p_country_code),v_scope,p_scope_id);
  v_route_gaps:=security.scheduler_workflow_route_gap_count_v1(upper(p_country_code),v_scope,p_scope_id);
  v_discovery_config_gaps:=security.scheduler_workflow_discovery_config_gap_count_v1(upper(p_country_code),v_scope,p_scope_id);

  v_confirm:=security.scheduler_workflow_scope_snapshot_v2(upper(p_country_code),v_scope,p_scope_id);
  if coalesce(v_confirm->>'scope_fingerprint','')<>coalesce(v_snapshot->>'scope_fingerprint','')
     or coalesce(v_confirm->'profile_ids','[]'::jsonb)<>coalesce(v_snapshot->'profile_ids','[]'::jsonb)
  then raise exception 'Layer 2 scope changed while preview was being constructed; preview again' using errcode='40001'; end if;

  v_result:=v_result||jsonb_build_object(
    'workflow_key','course_facts_l2','workflow_label','Course Facts enrichment',
    'processing_modes',jsonb_build_array(
      jsonb_build_object('key','acquisition_only','label','Acquisition + deterministic Layer 2','enabled',true),
      jsonb_build_object('key','automatic_governed_pipeline','label','Automatic governed pipeline','enabled',false,'reason','Conditional Layer 3/L4 orchestration is not yet qualified for generic Scheduled Tasks execution.'),
      jsonb_build_object('key','reprocess_governed_evidence','label','Reprocess governed Evidence','enabled',false,'reason','Use the governed Layer 3 workspace until an Evidence/profile-specific scheduler contract is accepted.')
    ),
    'schedule_supported',v_scope='university',
    'schedule_reason',case when v_scope='university' then 'University scope can resolve to an existing qualified Layer 2 source profile; schedule creation remains a separate governed action.' else 'Country/state schedules are not advertised because the current Layer 2 scheduler dispatches profile-wide and cannot enforce a multi-profile scope policy.' end,
    'invalid_profile_count',v_invalid_profiles,
    'missing_execution_policy_count',v_policy_gaps,
    'oversized_profile_count',v_oversized_profiles,
    'missing_acquisition_route_count',v_route_gaps,
    'unsupported_discovery_count',0,
    'preview_bound_discovery_count',v_discovery_count,
    'missing_discovery_config_count',v_discovery_config_gaps,
    'profile_ids',to_jsonb(v_profile_ids)
  );

  if v_invalid_profiles>0 then return v_result||jsonb_build_object('executable',false,'execution_block_reason','One or more Layer 2 Course Facts profiles in this scope do not have a valid current profile version. Requalify the affected profile before dispatch.','preview_token',null,'preview_expires_at',null); end if;
  if v_policy_gaps>0 then return v_result||jsonb_build_object('executable',false,'execution_block_reason','One or more Layer 2 profiles in this scope do not have the execution policy required by deterministic Layer 2 processing. Configure the execution policy through the normal governed lifecycle before acquisition or dispatch.','preview_token',null,'preview_expires_at',null); end if;
  if v_oversized_profiles>0 then return v_result||jsonb_build_object('executable',false,'execution_block_reason','One or more Layer 2 profiles in this scope exceed the current 1,000-course dispatch contract. Narrow the target scope before dispatch.','preview_token',null,'preview_expires_at',null); end if;
  if v_route_gaps>0 then return v_result||jsonb_build_object('executable',false,'execution_block_reason','One or more Layer 2 profiles in this scope have no runtime-usable acquisition route under the configured route order and fallback policy. Correct the blocking route/fallback or restore a usable governed route before dispatch.','preview_token',null,'preview_expires_at',null); end if;
  if v_discovery_config_gaps>0 then return v_result||jsonb_build_object('executable',false,'execution_block_reason','One or more Layer 2 discovery targets or queueable Course Facts URLs are not worker-valid under the governed profile configuration. Correct the governed profile before dispatch.','preview_token',null,'preview_expires_at',null); end if;
  if coalesce((v_result->>'active_run_count')::integer,0)>0 then return v_result||jsonb_build_object('executable',false,'execution_block_reason','One or more target profiles already have queued/running Layer 2 work. Wait for the existing governed work to finish before dispatch.','preview_token',null,'preview_expires_at',null); end if;
  if cardinality(v_profile_ids)=0 or coalesce((v_snapshot->>'scoped_course_count')::integer,0)<=0 then return v_result||jsonb_build_object('executable',false,'execution_block_reason','No executable Layer 2 work is available for this governed scope.','preview_token',null,'preview_expires_at',null); end if;

  v_result:=v_result||jsonb_build_object('executable',true,'async_discovery_preview_bound',v_discovery_count>0);
  insert into pipeline.jobs(job_type,domain,status,requested_by,started_at,completed_at,payload,result)
  values(
    'scheduler_workflow_preview','course_facts','completed',v_actor,now(),now(),
    jsonb_build_object('workflow_key',v_workflow,'country_code',upper(p_country_code),'scope_type',v_scope,'scope_id',p_scope_id,'processing_mode','acquisition_only','change_control_ref','CF-CHG-20260910-093','expires_at',v_preview_expires),
    v_result
  ) returning id into v_preview_id;

  for r in
    select sc.profile_id,
           array_agg(distinct sc.course_id order by sc.course_id) sync_ids,
           array_agg(distinct sc.course_id order by sc.course_id) filter(where sc.source_url is null) discovery_ids
    from public.layer2_scope_courses(upper(p_country_code),v_scope,p_scope_id) sc
    group by sc.profile_id
    having count(*) filter(where sc.source_url is null)>0
  loop
    v_binding:=security.scheduler_workflow_profile_binding_snapshot_v1(r.profile_id,r.sync_ids,r.discovery_ids);
    if v_binding is null
       or coalesce((v_binding->>'all_ids_valid')::boolean,false)=false
       or coalesce((v_binding->>'discovery_subset_valid')::boolean,false)=false
       or coalesce((v_binding->>'all_discovery_missing')::boolean,false)=false
    then raise exception 'Layer 2 async discovery inputs changed while preview was being bound; preview again' using errcode='40001'; end if;

    insert into pipeline.scheduler_workflow_async_bindings(
      preview_token,actor_id,profile_id,profile_version_id,country_code,scope_type,scope_id,
      scope_fingerprint,identity_fingerprint,queueable_fingerprint,sync_course_ids,discovery_course_ids,
      status,preview_expires_at
    ) values(
      v_preview_id,v_actor,r.profile_id,(v_binding->>'profile_version_id')::uuid,'AU',v_scope,p_scope_id,
      v_snapshot->>'scope_fingerprint',v_binding->>'identity_fingerprint',v_binding->>'queueable_fingerprint',
      r.sync_ids,r.discovery_ids,'prepared',v_preview_expires
    );
  end loop;

  return v_result||jsonb_build_object(
    'preview_token',v_preview_id,
    'preview_expires_at',v_preview_expires,
    'async_binding_profile_count',(select count(*) from pipeline.scheduler_workflow_async_bindings b where b.preview_token=v_preview_id)
  );
end
$function$;

revoke all on function security.scheduler_workflow_preview_v1_browser_bridge(text,text,text,uuid) from public,anon;
grant execute on function security.scheduler_workflow_preview_v1_browser_bridge(text,text,text,uuid) to authenticated;

-- The existing worker already carries actor + exact full sync_course_ids through every
-- continuation. Bind those carried inputs to the exact Preview token on initial dispatch,
-- then require the same active server binding for every continuation.
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
  v_discovery uuid[];
  v_requested uuid[];
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  if p_course_ids is null or coalesce(array_length(p_course_ids,1),0)=0 then raise exception 'course_ids required' using errcode='22023'; end if;
  if array_length(p_course_ids,1)>1000 or coalesce(array_length(p_sync_course_ids,1),0)>1000 then raise exception 'course_ids exceeds 1000' using errcode='22023'; end if;
  if not exists(select 1 from pipeline.layer2_source_profiles where id=p_profile_id and domain='course_facts' and enabled and not paused) then raise exception 'enabled course_facts profile required' using errcode='22023'; end if;

  select coalesce(array_agg(distinct x order by x),'{}'::uuid[]) into v_requested from unnest(p_course_ids) x;
  select coalesce(array_agg(distinct x order by x),'{}'::uuid[]) into v_sync from unnest(coalesce(p_sync_course_ids,p_course_ids)) x;

  begin
    v_preview_token:=nullif(current_setting('coursefinder.scheduler_preview_token',true),'')::uuid;
  exception when others then
    v_preview_token:=null;
  end;

  if v_preview_token is not null then
    select * into v_binding
    from pipeline.scheduler_workflow_async_bindings b
    where b.preview_token=v_preview_token
      and b.actor_id=p_actor
      and b.profile_id=p_profile_id
    for update;
  elsif p_actor is not null then
    select * into v_binding
    from pipeline.scheduler_workflow_async_bindings b
    where b.actor_id=p_actor
      and b.profile_id=p_profile_id
      and b.sync_course_ids=v_sync
      and b.discovery_course_ids @> v_requested
      and b.status in ('active','handoff_started')
    order by b.created_at desc
    limit 1
    for update;
  end if;

  if found then
    if v_binding.sync_course_ids<>v_sync then raise exception 'scheduler async binding sync scope mismatch' using errcode='22023'; end if;
    if not (v_binding.discovery_course_ids @> v_requested) then raise exception 'scheduler async binding discovery scope mismatch' using errcode='22023'; end if;

    if v_binding.status='prepared' then
      if v_preview_token is null or v_binding.preview_token<>v_preview_token then raise exception 'exact scheduler preview token required to activate async discovery' using errcode='22023'; end if;
      if v_binding.preview_expires_at<=now() then raise exception 'scheduler async preview binding expired; preview again' using errcode='22023'; end if;
      if v_requested<>v_binding.discovery_course_ids then raise exception 'initial scheduler discovery dispatch must match the exact preview-bound discovery set' using errcode='22023'; end if;
      perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('cf093-async|'||p_profile_id::text,0));
      if exists(select 1 from pipeline.scheduler_workflow_async_bindings x where x.profile_id=p_profile_id and x.status='active' and x.preview_token<>v_binding.preview_token) then raise exception 'another scheduler async binding is active for this Layer 2 profile' using errcode='55000'; end if;
      v_snapshot:=security.scheduler_workflow_profile_binding_snapshot_v1(p_profile_id,v_binding.sync_course_ids,v_binding.discovery_course_ids);
      if v_snapshot is null
         or (v_snapshot->>'profile_version_id')::uuid<>v_binding.profile_version_id
         or v_snapshot->>'identity_fingerprint'<>v_binding.identity_fingerprint
         or v_snapshot->>'queueable_fingerprint'<>v_binding.queueable_fingerprint
         or coalesce((v_snapshot->>'all_ids_valid')::boolean,false)=false
         or coalesce((v_snapshot->>'all_discovery_missing')::boolean,false)=false
      then raise exception 'scheduler async discovery inputs changed after Preview; preview again' using errcode='22023'; end if;
      update pipeline.scheduler_workflow_async_bindings
      set status='active',activated_at=now(),execution_expires_at=now()+interval '6 hours'
      where preview_token=v_binding.preview_token and profile_id=v_binding.profile_id
      returning * into v_binding;
    elsif v_binding.status<>'active' then
      raise exception 'scheduler async binding is no longer active' using errcode='22023';
    end if;

    if v_binding.execution_expires_at is null or v_binding.execution_expires_at<=now() then raise exception 'scheduler async execution binding expired; operator review required' using errcode='22023'; end if;
    v_snapshot:=security.scheduler_workflow_profile_binding_snapshot_v1(p_profile_id,v_binding.sync_course_ids,v_binding.discovery_course_ids);
    if v_snapshot is null
       or (v_snapshot->>'profile_version_id')::uuid<>v_binding.profile_version_id
       or v_snapshot->>'identity_fingerprint'<>v_binding.identity_fingerprint
       or v_snapshot->>'queueable_fingerprint'<>v_binding.queueable_fingerprint
       or coalesce((v_snapshot->>'all_ids_valid')::boolean,false)=false
    then raise exception 'scheduler async bound profile/course identity changed during discovery; stop and preview again' using errcode='22023'; end if;
  end if;

  v_req:=pipeline.svc_pilot_submit_nonce(
    'layer2-scope-discover-scheduled',
    jsonb_build_object(
      'profile_id',p_profile_id,
      'limit',least(greatest(coalesce(p_limit,50),1),50),
      'course_ids',to_jsonb(p_course_ids),
      'auto_sync_actor',p_actor,
      'sync_course_ids',to_jsonb(coalesce(p_sync_course_ids,p_course_ids))
    )
  );

  return jsonb_build_object(
    'ok',true,'profile_id',p_profile_id,'request_id',v_req,
    'course_count',array_length(p_course_ids,1),
    'scheduler_preview_token',case when found then v_binding.preview_token else null end
  );
end
$function$;
revoke all on function security.layer2_discovery_scope_dispatch_v2(uuid,uuid[],integer,uuid,uuid[]) from public,anon,authenticated;
grant execute on function security.layer2_discovery_scope_dispatch_v2(uuid,uuid[],integer,uuid,uuid[]) to service_role;

-- Final deterministic handoff must consume the exact full course set bound by Preview.
-- For discovery IDs, require a selected current-version candidate created after binding activation.
create or replace function public.layer2_scope_profile_batch_service(
  p_actor uuid,
  p_profile_id uuid,
  p_course_ids uuid[]
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','pipeline','catalogue','security'
as $function$
declare
  v_rank integer:=0;
  v_active uuid;
  v_items jsonb;
  v_batch uuid;
  v_req bigint;
  v_count integer:=0;
  v_profile pipeline.layer2_source_profiles%rowtype;
  v_provider uuid;
  v_binding pipeline.scheduler_workflow_async_bindings%rowtype;
  v_snapshot jsonb;
  v_sync uuid[];
  v_bound boolean:=false;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  if p_actor is null then raise exception 'actor required' using errcode='42501'; end if;

  select coalesce(max(r.rank),0) into v_rank
  from security.user_roles ur join security.roles r on r.code=ur.role_code
  where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and r.status='active';
  if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;

  select * into v_profile
  from pipeline.layer2_source_profiles
  where id=p_profile_id and domain='course_facts' and enabled and not paused;
  if not found then raise exception 'profile not executable' using errcode='22023'; end if;

  select coalesce(array_agg(distinct x order by x),'{}'::uuid[]) into v_sync from unnest(coalesce(p_course_ids,'{}'::uuid[])) x;
  select * into v_binding
  from pipeline.scheduler_workflow_async_bindings b
  where b.actor_id=p_actor and b.profile_id=p_profile_id and b.sync_course_ids=v_sync
    and b.status in ('active','handoff_started')
  order by b.created_at desc limit 1 for update;

  if found then
    v_bound:=true;
    if v_binding.status<>'active' then raise exception 'scheduler async binding has already handed off this exact scope' using errcode='22023'; end if;
    if v_binding.execution_expires_at is null or v_binding.execution_expires_at<=now() then raise exception 'scheduler async execution binding expired before Layer 2 handoff' using errcode='22023'; end if;
    v_snapshot:=security.scheduler_workflow_profile_binding_snapshot_v1(p_profile_id,v_binding.sync_course_ids,v_binding.discovery_course_ids);
    if v_snapshot is null
       or (v_snapshot->>'profile_version_id')::uuid<>v_binding.profile_version_id
       or v_snapshot->>'identity_fingerprint'<>v_binding.identity_fingerprint
       or v_snapshot->>'queueable_fingerprint'<>v_binding.queueable_fingerprint
       or coalesce((v_snapshot->>'all_ids_valid')::boolean,false)=false
    then raise exception 'scheduler async bound profile/course identity changed before deterministic handoff' using errcode='22023'; end if;

    if exists(
      select 1 from unnest(v_binding.discovery_course_ids) cid
      where not exists(
        select 1 from pipeline.layer2_course_discovery_candidates d
        where d.course_id=cid
          and d.source_profile_version_id=v_binding.profile_version_id
          and d.selected=true
          and nullif(d.discovered_url,'') is not null
          and d.created_at>=v_binding.activated_at
      )
    ) then raise exception 'scheduler async discovery did not produce a current selected URL for every preview-bound discovery course' using errcode='22023'; end if;
  end if;

  select s.provider_id into v_provider from pipeline.sources s where s.id=v_profile.source_id;

  select b.id into v_active
  from pipeline.layer2_run_batches b
  where b.profile_id=p_profile_id and b.status in ('queued','running','partial')
  order by b.created_at desc limit 1;
  if v_active is not null then
    if v_bound then raise exception 'preview-bound Layer 2 handoff conflicts with an existing active batch' using errcode='55000'; end if;
    return jsonb_build_object('ok',true,'status','already_running','batch_id',v_active,'profile_id',p_profile_id);
  end if;

  with chosen as (
    select c.id,
      coalesce((
        select d.discovered_url
        from pipeline.layer2_course_discovery_candidates d
        where d.course_id=c.id and d.source_profile_version_id=v_profile.current_version_id
          and d.selected and nullif(d.discovered_url,'') is not null
        order by d.created_at desc limit 1
      ),nullif(c.course_url,'')) url
    from catalogue.courses c
    where c.provider_id=v_provider and c.id=any(p_course_ids)
  )
  select jsonb_agg(jsonb_build_object('entity_type','course','entity_id',id,'source_url',url) order by id),
         count(*) filter(where url is not null)
  into v_items,v_count
  from chosen where url is not null;

  if v_items is null or v_count=0 then
    if v_bound then raise exception 'preview-bound Layer 2 handoff has no queueable courses after discovery' using errcode='22023'; end if;
    return jsonb_build_object('ok',true,'status','nothing_queueable','profile_id',p_profile_id,'requested_count',coalesce(array_length(p_course_ids,1),0));
  end if;
  if v_bound and v_count<>cardinality(v_binding.sync_course_ids) then raise exception 'preview-bound Layer 2 handoff is incomplete after discovery' using errcode='22023'; end if;

  v_batch:=public.layer2_run_batch_create(p_profile_id,'manual',p_actor,v_items);
  v_req:=public.layer2_run_batch_dispatch(v_batch);

  if v_bound then
    update pipeline.scheduler_workflow_async_bindings
    set status='handoff_started',handoff_started_at=now()
    where preview_token=v_binding.preview_token and profile_id=v_binding.profile_id;
  end if;

  return jsonb_build_object(
    'ok',true,'status','started','profile_id',p_profile_id,'batch_id',v_batch,
    'dispatch_request_id',v_req,'target_count',v_count,'requested_count',array_length(p_course_ids,1),
    'scheduler_preview_token',case when v_bound then v_binding.preview_token else null end
  );
end
$function$;
revoke all on function public.layer2_scope_profile_batch_service(uuid,uuid,uuid[]) from public,anon,authenticated;
grant execute on function public.layer2_scope_profile_batch_service(uuid,uuid,uuid[]) to service_role;

-- Preserve every prior rank/target/mode/fingerprint/idempotency guard. The only new line
-- is a transaction-local exact Preview token passed to the service-only discovery bridge;
-- asynchronous continuations resolve the resulting durable active binding server-side.
create or replace function security.scheduler_workflow_run_now_v2_browser_bridge(
  p_preview_token uuid,p_workflow_key text,p_country_code text,p_scope_type text,p_scope_id uuid,p_processing_mode text,p_reason text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_actor uuid:=auth.uid(); v_workflow text:=lower(coalesce(trim(p_workflow_key),'')); v_scope text:=lower(coalesce(trim(p_scope_type),'')); v_mode text:=lower(coalesce(trim(p_processing_mode),''));
  v_preview pipeline.jobs%rowtype; v_prior pipeline.jobs%rowtype; v_live_snapshot jsonb; v_post_snapshot jsonb; v_result jsonb; v_scope_key text; v_invalid_profiles integer:=0; v_policy_gaps integer:=0; v_oversized_profiles integer:=0; v_route_gaps integer:=0; v_discovery_config_gaps integer:=0;
  v_preview_profiles uuid[]:='{}'::uuid[]; v_live_profiles uuid[]:='{}'::uuid[]; v_started_profiles uuid[]:='{}'::uuid[]; v_preview_fingerprint text; v_live_fingerprint text;
begin
  if v_actor is null or security.current_role_rank() < 4 then raise exception 'pipeline operator role required' using errcode='42501'; end if;
  if length(trim(coalesce(p_reason,''))) < 5 then raise exception 'governance reason required' using errcode='22023'; end if;
  if v_workflow <> 'course_facts_l2' or upper(coalesce(trim(p_country_code),'')) <> 'AU' then raise exception 'workflow is not executable from Scheduled Tasks' using errcode='22023'; end if;
  if v_scope not in ('country','state','university') then raise exception 'unsupported scope type' using errcode='22023'; end if;
  if v_scope in ('state','university') and p_scope_id is null then raise exception 'scope id required' using errcode='22023'; end if;
  if v_scope='country' and p_scope_id is not null then raise exception 'country scope must not include a scope id' using errcode='22023'; end if;
  if v_mode <> 'acquisition_only' then raise exception 'processing mode is not yet qualified for generic Scheduled Tasks execution' using errcode='22023'; end if;
  if p_preview_token is null then raise exception 'valid preview token required' using errcode='22023'; end if;
  v_scope_key:=v_workflow||'|'||upper(p_country_code)||'|'||v_scope||'|'||coalesce(p_scope_id::text,'country')||'|'||v_mode;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_scope_key,0));
  select * into v_preview from pipeline.jobs j where j.id=p_preview_token and j.job_type='scheduler_workflow_preview' and j.requested_by=v_actor and j.created_at>=now()-interval '15 minutes' for update;
  if not found then raise exception 'preview token is missing, expired or belongs to another actor' using errcode='22023'; end if;
  if coalesce(v_preview.payload->>'workflow_key','')<>v_workflow or coalesce(v_preview.payload->>'country_code','')<>upper(p_country_code) or coalesce(v_preview.payload->>'scope_type','')<>v_scope or coalesce(v_preview.payload->>'scope_id','')<>coalesce(p_scope_id::text,'') or coalesce(v_preview.payload->>'processing_mode','')<>v_mode then raise exception 'preview token does not match the exact requested workflow target' using errcode='22023'; end if;
  if v_preview.payload ? 'dispatch_result' then return jsonb_build_object('ok',true,'preview_token',p_preview_token,'idempotent_replay',true,'result',v_preview.payload->'dispatch_result'); end if;
  select coalesce(array_agg((x)::uuid order by (x)::uuid),'{}'::uuid[]) into v_preview_profiles from jsonb_array_elements_text(coalesce(v_preview.result->'profile_ids','[]'::jsonb)) x;
  v_preview_fingerprint:=nullif(v_preview.result->>'scope_fingerprint','');
  if cardinality(v_preview_profiles)=0 or v_preview_fingerprint is null then raise exception 'preview token predates exact runnable-scope binding; preview again before dispatch' using errcode='22023'; end if;
  if coalesce((v_preview.result->>'executable')::boolean,false)=false then raise exception 'previewed scope has no executable Layer 2 work' using errcode='22023'; end if;

  v_live_snapshot:=security.scheduler_workflow_scope_snapshot_v2(upper(p_country_code),v_scope,p_scope_id);
  select coalesce(array_agg((x)::uuid order by (x)::uuid),'{}'::uuid[]) into v_live_profiles from jsonb_array_elements_text(coalesce(v_live_snapshot->'profile_ids','[]'::jsonb)) x;
  v_live_fingerprint:=v_live_snapshot->>'scope_fingerprint';
  if v_live_profiles<>v_preview_profiles or coalesce(v_live_fingerprint,'')<>v_preview_fingerprint then raise exception 'Layer 2 runnable scope changed after preview; preview again before dispatch' using errcode='22023'; end if;
  if coalesce((v_live_snapshot->>'queueable_count')::integer,0)+coalesce((v_live_snapshot->>'needs_discovery_count')::integer,0)<=0 then raise exception 'Layer 2 runnable scope changed after preview; preview again before dispatch' using errcode='22023'; end if;

  select count(distinct sc.profile_id)::integer into v_invalid_profiles from public.layer2_scope_courses(upper(p_country_code),v_scope,p_scope_id) sc join pipeline.layer2_source_profiles lp on lp.id=sc.profile_id left join pipeline.layer2_source_profile_versions pv on pv.id=lp.current_version_id where lp.current_version_id is null or pv.id is null or pv.validation_status<>'valid'; if v_invalid_profiles>0 then raise exception 'Layer 2 profile qualification changed after preview; preview again after requalification' using errcode='22023'; end if;
  v_policy_gaps:=security.scheduler_workflow_execution_policy_gap_count_v1(upper(p_country_code),v_scope,p_scope_id); if v_policy_gaps>0 then raise exception 'Layer 2 execution policy qualification changed after preview; configure the execution policy and preview again' using errcode='22023'; end if;
  v_oversized_profiles:=security.scheduler_workflow_oversized_profile_count_v1(upper(p_country_code),v_scope,p_scope_id); if v_oversized_profiles>0 then raise exception 'Layer 2 scope exceeds the current 1,000-course per-profile dispatch contract; narrow the target and preview again' using errcode='22023'; end if;
  v_route_gaps:=security.scheduler_workflow_route_gap_count_v1(upper(p_country_code),v_scope,p_scope_id); if v_route_gaps>0 then raise exception 'Layer 2 acquisition route qualification changed after preview; restore a runtime-usable governed route and preview again' using errcode='22023'; end if;
  v_discovery_config_gaps:=security.scheduler_workflow_discovery_config_gap_count_v1(upper(p_country_code),v_scope,p_scope_id); if v_discovery_config_gaps>0 then raise exception 'Layer 2 source/discovery URL qualification changed after preview; correct the worker-valid HTTPS target/allowlist and preview again' using errcode='22023'; end if;

  select * into v_prior from pipeline.jobs j where j.id<>p_preview_token and j.job_type='scheduler_workflow_preview' and nullif(j.payload->>'consumed_at','') is not null and (j.payload->>'consumed_at')::timestamptz>=now()-interval '10 minutes' and coalesce(j.payload->>'workflow_key','')=v_workflow and coalesce(j.payload->>'country_code','')=upper(p_country_code) and coalesce(j.payload->>'scope_type','')=v_scope and coalesce(j.payload->>'scope_id','')=coalesce(p_scope_id::text,'') and coalesce(j.payload->>'processing_mode','')=v_mode and coalesce(j.result->>'scope_fingerprint','')=v_live_fingerprint and coalesce(j.result->'profile_ids','[]'::jsonb)=to_jsonb(v_live_profiles) and j.payload ? 'dispatch_result' order by (j.payload->>'consumed_at')::timestamptz desc limit 1;
  if found then update pipeline.jobs set payload=payload||jsonb_build_object('deduplicated_at',now(),'dispatch_result',v_prior.payload->'dispatch_result','deduplicated_against_preview',v_prior.id,'governance_reason',trim(p_reason)) where id=p_preview_token; return jsonb_build_object('ok',true,'preview_token',p_preview_token,'existing_recent_dispatch',true,'deduplicated_against_preview',v_prior.id,'result',v_prior.payload->'dispatch_result'); end if;

  perform set_config('coursefinder.scheduler_preview_token',p_preview_token::text,true);
  v_result:=public.layer2_operator_scope_service(v_actor,'start',upper(p_country_code),v_scope,p_scope_id);
  select coalesce(array_agg(distinct (e->>'profile_id')::uuid order by (e->>'profile_id')::uuid),'{}'::uuid[]) into v_started_profiles from jsonb_array_elements(coalesce(v_result->'profiles','[]'::jsonb)) e where nullif(e->>'profile_id','') is not null;
  if v_started_profiles<>v_live_profiles then raise exception 'Layer 2 runnable profile set changed during dispatch; transaction rolled back, preview again before dispatch' using errcode='22023'; end if;
  if exists (
    select 1 from jsonb_array_elements(coalesce(v_result->'profiles','[]'::jsonb)) e
    where coalesce(e->>'status','') not in ('started','discovery_started')
       or (e->>'status'='started' and (nullif(e->>'batch_id','') is null or nullif(e->>'dispatch_request_id','') is null or coalesce((e->>'target_count')::integer,-1)<>coalesce((e->>'requested_count')::integer,-2)))
       or (e->>'status'='discovery_started' and nullif(e->>'request_id','') is null)
  ) then raise exception 'Layer 2 dispatch did not start the exact previewed work for every profile; transaction rolled back, resolve active/incompatible work and preview again' using errcode='22023'; end if;
  v_post_snapshot:=security.scheduler_workflow_scope_snapshot_v2(upper(p_country_code),v_scope,p_scope_id);
  if coalesce(v_post_snapshot->>'scope_fingerprint','')<>v_preview_fingerprint or coalesce(v_post_snapshot->'profile_ids','[]'::jsonb)<>to_jsonb(v_live_profiles) then raise exception 'Layer 2 runnable scope changed during dispatch; transaction rolled back, preview again before dispatch' using errcode='40001'; end if;
  update pipeline.jobs set payload=payload||jsonb_build_object('consumed_at',now(),'dispatch_result',coalesce(v_result,'{}'::jsonb),'governance_reason',trim(p_reason)),result=result||jsonb_build_object('dispatch_result',coalesce(v_result,'{}'::jsonb)) where id=p_preview_token;
  return jsonb_build_object('ok',true,'preview_token',p_preview_token,'idempotent_replay',false,'result',v_result);
end
$function$;

revoke all on function security.scheduler_workflow_run_now_v2_browser_bridge(uuid,text,text,text,uuid,text,text) from public,anon;
grant execute on function security.scheduler_workflow_run_now_v2_browser_bridge(uuid,text,text,text,uuid,text,text) to authenticated;

commit;
