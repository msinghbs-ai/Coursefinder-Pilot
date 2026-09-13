-- CF-CHG-20260910-093
-- Final forward-only review reconciliation.
-- Applied predecessors remain immutable.
-- 1) Enforce approved first-party acquisition targets before provider work begins.
-- 2) Enforce governed retry policy and fairness before continuation nonce creation.
-- 3) Aggregate exact-token retry history once per bound context call.
-- 4) Never fall back to a concurrent Layer 1 URL for Preview discovery-subset handoff.

begin;

create or replace function public.layer2_provider_attempt_start(
  p_job_id uuid,
  p_provider_id uuid,
  p_request_url text
) returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog','pipeline','public','security'
as $function$
declare
  v_version uuid;
  v_profile_id uuid;
  v_attempt int;
  v_id uuid;
  v_budget jsonb;
  v_planned numeric:=1;
begin
  if auth.role()<>'service_role' then raise exception 'service_role required' using errcode='42501'; end if;

  select j.source_profile_version_id,pv.profile_id
  into v_version,v_profile_id
  from pipeline.jobs j
  join pipeline.layer2_source_profile_versions pv on pv.id=j.source_profile_version_id
  where j.id=p_job_id;

  if v_version is null or v_profile_id is null then
    raise exception 'versioned Layer 2 job required' using errcode='22023';
  end if;

  if not security.scheduler_workflow_queueable_url_allowed_v1(v_profile_id,p_request_url) then
    raise exception 'Layer 2 acquisition target is outside the governed profile host allowlist' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtext('layer2-provider-budget:'||p_provider_id::text)::bigint);
  select coalesce(nullif(request_template->>'fixed_credit_units','')::numeric,1)
  into v_planned
  from pipeline.layer2_acquisition_providers
  where id=p_provider_id;

  v_budget:=security.layer2_provider_budget_status(p_provider_id,v_planned);
  if coalesce((v_budget->>'allowed')::boolean,true) is not true then
    raise exception 'provider monthly budget stop threshold reached: %',v_budget using errcode='P0001';
  end if;

  select coalesce(max(attempt_no),0)+1 into v_attempt
  from pipeline.layer2_provider_attempts
  where job_id=p_job_id;

  insert into pipeline.layer2_provider_attempts(
    job_id,profile_version_id,acquisition_provider_id,attempt_no,status,request_url,started_at,metrics
  ) values(
    p_job_id,v_version,p_provider_id,v_attempt,'running',p_request_url,now(),jsonb_build_object('budget_at_start',v_budget)
  ) returning id into v_id;

  return v_id;
end
$function$;

revoke all on function public.layer2_provider_attempt_start(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.layer2_provider_attempt_start(uuid,uuid,text) to service_role;

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
as $function$
declare
  v_ctx jsonb;
  v_provider uuid;
  v_courses jsonb;
  v_binding pipeline.scheduler_workflow_async_bindings%rowtype;
  v_requested uuid[];
  v_snapshot jsonb;
  v_retry_max integer:=3;
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

  begin
    v_retry_max:=greatest(coalesce(nullif(v_ctx#>>'{configuration,retry,max_attempts}','')::integer,3),1);
  exception when others then
    v_retry_max:=3;
  end;

  select s.provider_id into v_provider from pipeline.sources s where s.id=(v_ctx->>'source_id')::uuid;
  if v_provider is null then raise exception 'profile source is not bound to a canonical provider' using errcode='22023'; end if;

  with retry_counts as (
    select (r->>'course_id')::uuid course_id,count(*)::integer retry_attempts
    from pipeline.jobs j
    cross join lateral jsonb_array_elements(coalesce(j.result->'results','[]'::jsonb)) r
    where j.job_type='layer2_discovery'
      and j.payload->>'scheduler_preview_token'=v_binding.preview_token::text
      and j.payload->>'profile_id'=p_profile_id::text
      and nullif(r->>'course_id','') is not null
      and (r->>'course_id')::uuid=any(v_requested)
      and r->>'status' in ('failed','candidate')
    group by (r->>'course_id')::uuid
  ), ranked as (
    select c.id,c.canonical_title,c.display_title,c.course_code,coalesce(a.retry_attempts,0)::integer retry_attempts
    from catalogue.courses c
    left join retry_counts a on a.course_id=c.id
    where c.provider_id=v_provider and c.id=any(v_requested)
      and coalesce(a.retry_attempts,0)<v_retry_max
      and not exists(
        select 1
        from pipeline.layer2_course_discovery_candidates dc
        join pipeline.layer2_provider_attempts pa on pa.id=dc.provider_attempt_id
        join pipeline.jobs j on j.id=pa.job_id
        where dc.course_id=c.id
          and dc.source_profile_version_id=v_binding.profile_version_id
          and dc.selected=true
          and nullif(dc.discovered_url,'') is not null
          and dc.created_at>=v_binding.activated_at
          and coalesce(j.payload->>'scheduler_preview_token','')=v_binding.preview_token::text
      )
    order by coalesce(a.retry_attempts,0),c.canonical_title,c.id
    limit least(greatest(coalesce(p_limit,50),1),50)
  )
  select coalesce(jsonb_agg(to_jsonb(ranked)-'retry_attempts' order by retry_attempts,canonical_title,id),'[]'::jsonb)
  into v_courses
  from ranked;

  return jsonb_build_object(
    'runtime',v_ctx,'canonical_provider_id',v_provider,'courses',v_courses,
    'scheduler_preview_token',v_binding.preview_token,'scheduler_bound_retry',true,
    'retry_max_attempts',v_retry_max,
    'identity_revalidated',true,'historical_dispositions_preserved',true
  );
end
$function$;

revoke all on function public.layer2_discovery_context_scope_bound_v1(uuid,uuid,uuid,uuid[],integer) from public,anon,authenticated;
grant execute on function public.layer2_discovery_context_scope_bound_v1(uuid,uuid,uuid,uuid[],integer) to service_role;

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
  v_ordered uuid[];
  v_bound boolean:=false;
  v_retry_max integer:=3;
  v_profile_version uuid;
  v_exhausted integer:=0;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  if p_course_ids is null or coalesce(array_length(p_course_ids,1),0)=0 then raise exception 'course_ids required' using errcode='22023'; end if;
  if array_length(p_course_ids,1)>1000 or coalesce(array_length(p_sync_course_ids,1),0)>1000 then raise exception 'course_ids exceeds 1000' using errcode='22023'; end if;

  select current_version_id into v_profile_version
  from pipeline.layer2_source_profiles
  where id=p_profile_id and domain='course_facts' and enabled and not paused;
  if v_profile_version is null then raise exception 'enabled course_facts profile required' using errcode='22023'; end if;

  select coalesce(array_agg(distinct x order by x),'{}'::uuid[]) into v_requested from unnest(p_course_ids) x;
  select coalesce(array_agg(distinct x order by x),'{}'::uuid[]) into v_sync from unnest(coalesce(p_sync_course_ids,p_course_ids)) x;
  begin v_preview_token:=nullif(current_setting('coursefinder.scheduler_preview_token',true),'')::uuid; exception when others then v_preview_token:=null; end;

  if v_preview_token is not null then
    select * into v_binding from pipeline.scheduler_workflow_async_bindings b
    where b.preview_token=v_preview_token and b.actor_id=p_actor and b.profile_id=p_profile_id for update;
    v_bound:=found;
  elsif p_actor is not null then
    select * into v_binding from pipeline.scheduler_workflow_async_bindings b
    where b.actor_id=p_actor and b.profile_id=p_profile_id and b.sync_course_ids=v_sync and b.discovery_course_ids @> v_requested
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
    v_profile_version:=v_binding.profile_version_id;
  end if;

  begin
    select greatest(coalesce(nullif(pv.configuration#>>'{retry,max_attempts}','')::integer,3),1)
    into v_retry_max
    from pipeline.layer2_source_profile_versions pv
    where pv.id=v_profile_version;
  exception when others then
    v_retry_max:=3;
  end;
  v_retry_max:=coalesce(v_retry_max,3);

  with requested as (
    select x course_id from unnest(v_requested) x
  ), retry_counts as (
    select (r->>'course_id')::uuid course_id,count(*)::integer attempts
    from pipeline.jobs j
    cross join lateral jsonb_array_elements(coalesce(j.result->'results','[]'::jsonb)) r
    where j.job_type='layer2_discovery'
      and j.source_profile_version_id=v_profile_version
      and j.payload->>'profile_id'=p_profile_id::text
      and nullif(r->>'course_id','') is not null
      and (r->>'course_id')::uuid=any(v_requested)
      and r->>'status' in ('failed','candidate')
      and (
        (v_bound and j.payload->>'scheduler_preview_token'=v_preview_token::text)
        or (not v_bound and nullif(j.payload->>'scheduler_preview_token','') is null)
      )
    group by (r->>'course_id')::uuid
  ), ordered as (
    select q.course_id,coalesce(a.attempts,0) attempts
    from requested q left join retry_counts a using(course_id)
    where coalesce(a.attempts,0)<v_retry_max
    order by coalesce(a.attempts,0),q.course_id
  )
  select coalesce(array_agg(course_id order by attempts,course_id),'{}'::uuid[])
  into v_ordered from ordered;

  v_exhausted:=cardinality(v_requested)-cardinality(v_ordered);
  if cardinality(v_ordered)=0 then
    return jsonb_build_object(
      'ok',true,'status','retry_exhausted','profile_id',p_profile_id,'request_id',null,
      'course_count',0,'retry_exhausted_count',v_exhausted,'retry_max_attempts',v_retry_max,
      'operator_review_required',true,
      'scheduler_preview_token',case when v_bound then v_preview_token else null end
    );
  end if;

  v_req:=pipeline.svc_pilot_submit_nonce(
    'layer2-scope-discover-scheduled',
    jsonb_build_object(
      'profile_id',p_profile_id,
      'limit',least(greatest(coalesce(p_limit,50),1),50),
      'course_ids',to_jsonb(v_ordered),
      'auto_sync_actor',p_actor,
      'sync_course_ids',to_jsonb(coalesce(p_sync_course_ids,p_course_ids)),
      'scheduler_preview_token',case when v_bound then v_preview_token else null end,
      'retry_max_attempts',v_retry_max,
      'retry_exhausted_count',v_exhausted
    )
  );

  return jsonb_build_object(
    'ok',true,'status','queued','profile_id',p_profile_id,'request_id',v_req,
    'course_count',cardinality(v_ordered),'retry_exhausted_count',v_exhausted,
    'retry_max_attempts',v_retry_max,
    'scheduler_preview_token',case when v_bound then v_preview_token else null end
  );
end
$function$;

revoke all on function security.layer2_discovery_scope_dispatch_v2(uuid,uuid[],integer,uuid,uuid[]) from public,anon,authenticated;
grant execute on function security.layer2_discovery_scope_dispatch_v2(uuid,uuid[],integer,uuid,uuid[]) to service_role;

create or replace function public.layer2_scope_profile_batch_service(p_actor uuid, p_profile_id uuid, p_course_ids uuid[])
returns jsonb
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
  v_selected_discovery_count integer:=0;
  v_terminal_negative_count integer:=0;
  v_expected_preview uuid:=nullif(current_setting('coursefinder.scheduler_preview_token',true),'')::uuid;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  if p_actor is null then raise exception 'actor required' using errcode='42501'; end if;

  select coalesce(max(r.rank),0) into v_rank
  from security.user_roles ur join security.roles r on r.code=ur.role_code
  where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and r.status='active';
  if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;

  select * into v_profile from pipeline.layer2_source_profiles
  where id=p_profile_id and domain='course_facts' and enabled and not paused;
  if not found then raise exception 'profile not executable' using errcode='22023'; end if;

  select coalesce(array_agg(distinct x order by x),'{}'::uuid[]) into v_sync
  from unnest(coalesce(p_course_ids,'{}'::uuid[])) x;

  if v_expected_preview is not null then
    select * into v_binding from pipeline.scheduler_workflow_async_bindings b
    where b.preview_token=v_expected_preview and b.actor_id=p_actor and b.profile_id=p_profile_id
      and b.sync_course_ids=v_sync and b.status in ('active','handoff_started')
    order by b.created_at desc limit 1 for update;
    if not found then raise exception 'exact scheduler Preview binding is missing, cancelled, expired or does not match the handoff scope' using errcode='22023'; end if;
  else
    select * into v_binding from pipeline.scheduler_workflow_async_bindings b
    where b.actor_id=p_actor and b.profile_id=p_profile_id and b.sync_course_ids=v_sync
      and b.status in ('active','handoff_started')
    order by b.created_at desc limit 1 for update;
  end if;

  if found or v_expected_preview is not null then
    v_bound:=true;
    if v_binding.status<>'active' then raise exception 'scheduler async binding has already handed off this exact scope' using errcode='22023'; end if;
    if v_binding.execution_expires_at is null or v_binding.execution_expires_at<=now() then raise exception 'scheduler async execution binding expired before Layer 2 handoff' using errcode='22023'; end if;
    v_snapshot:=security.scheduler_workflow_profile_binding_snapshot_v1(p_profile_id,v_binding.sync_course_ids,v_binding.discovery_course_ids);
    if v_snapshot is null or (v_snapshot->>'profile_version_id')::uuid<>v_binding.profile_version_id
       or v_snapshot->>'identity_fingerprint'<>v_binding.identity_fingerprint
       or v_snapshot->>'queueable_fingerprint'<>v_binding.queueable_fingerprint
       or coalesce((v_snapshot->>'all_ids_valid')::boolean,false)=false
    then raise exception 'scheduler async bound profile/course identity changed before deterministic handoff' using errcode='22023'; end if;

    if exists(
      select 1 from unnest(v_binding.discovery_course_ids) cid
      where not exists(
        select 1 from pipeline.layer2_course_discovery_candidates d
        join pipeline.layer2_provider_attempts pa on pa.id=d.provider_attempt_id
        join pipeline.jobs j on j.id=pa.job_id
        where d.course_id=cid and d.source_profile_version_id=v_binding.profile_version_id
          and d.created_at>=v_binding.activated_at
          and j.payload->>'scheduler_preview_token'=v_binding.preview_token::text
          and ((d.selected=true and nullif(d.discovered_url,'') is not null)
            or (d.selected=false and d.status in ('current_page_not_found','ambiguous','identity_mismatch')))
      )
    ) then raise exception 'scheduler async discovery has transient, unattempted or non-Preview-bound courses without a governed terminal outcome' using errcode='22023'; end if;

    select count(*)::integer into v_selected_discovery_count
    from unnest(v_binding.discovery_course_ids) cid
    where exists(
      select 1 from pipeline.layer2_course_discovery_candidates d
      join pipeline.layer2_provider_attempts pa on pa.id=d.provider_attempt_id
      join pipeline.jobs j on j.id=pa.job_id
      where d.course_id=cid and d.source_profile_version_id=v_binding.profile_version_id
        and d.created_at>=v_binding.activated_at and d.selected=true and nullif(d.discovered_url,'') is not null
        and j.payload->>'scheduler_preview_token'=v_binding.preview_token::text
    );

    select count(*)::integer into v_terminal_negative_count
    from unnest(v_binding.discovery_course_ids) cid
    where not exists(
      select 1 from pipeline.layer2_course_discovery_candidates d
      join pipeline.layer2_provider_attempts pa on pa.id=d.provider_attempt_id
      join pipeline.jobs j on j.id=pa.job_id
      where d.course_id=cid and d.source_profile_version_id=v_binding.profile_version_id
        and d.created_at>=v_binding.activated_at and d.selected=true and nullif(d.discovered_url,'') is not null
        and j.payload->>'scheduler_preview_token'=v_binding.preview_token::text
    ) and exists(
      select 1 from pipeline.layer2_course_discovery_candidates d
      join pipeline.layer2_provider_attempts pa on pa.id=d.provider_attempt_id
      join pipeline.jobs j on j.id=pa.job_id
      where d.course_id=cid and d.source_profile_version_id=v_binding.profile_version_id
        and d.created_at>=v_binding.activated_at and d.selected=false
        and d.status in ('current_page_not_found','ambiguous','identity_mismatch')
        and j.payload->>'scheduler_preview_token'=v_binding.preview_token::text
    );
  end if;

  select s.provider_id into v_provider from pipeline.sources s where s.id=v_profile.source_id;

  select b.id into v_active from pipeline.layer2_run_batches b
  where b.profile_id=p_profile_id and (b.status in ('queued','running') or
    (b.status='partial' and exists(select 1 from pipeline.layer2_run_items i where i.batch_id=b.id and i.status in ('queued','running'))))
  order by b.created_at desc limit 1;
  if v_active is not null then
    if v_bound then raise exception 'preview-bound Layer 2 handoff conflicts with an existing active batch' using errcode='55000'; end if;
    return jsonb_build_object('ok',true,'status','already_running','batch_id',v_active,'profile_id',p_profile_id);
  end if;

  with chosen as (
    select c.id,
      case
        when v_bound and c.id=any(v_binding.discovery_course_ids) then (
          select d.discovered_url
          from pipeline.layer2_course_discovery_candidates d
          join pipeline.layer2_provider_attempts pa on pa.id=d.provider_attempt_id
          join pipeline.jobs j on j.id=pa.job_id
          where d.course_id=c.id and d.source_profile_version_id=v_binding.profile_version_id
            and d.created_at>=v_binding.activated_at and d.selected=true and nullif(d.discovered_url,'') is not null
            and j.payload->>'scheduler_preview_token'=v_binding.preview_token::text
          order by d.created_at desc limit 1
        )
        when v_bound then coalesce((
          select d.discovered_url from pipeline.layer2_course_discovery_candidates d
          where d.course_id=c.id and d.source_profile_version_id=v_binding.profile_version_id
            and d.selected=true and nullif(d.discovered_url,'') is not null
          order by d.created_at desc limit 1
        ),nullif(c.course_url,''))
        else coalesce((
          select d.discovered_url from pipeline.layer2_course_discovery_candidates d
          where d.course_id=c.id and d.source_profile_version_id=v_profile.current_version_id
            and d.selected=true and nullif(d.discovered_url,'') is not null
          order by d.created_at desc limit 1
        ),nullif(c.course_url,''))
      end url
    from catalogue.courses c
    where c.provider_id=v_provider and c.id=any(p_course_ids)
  )
  select jsonb_agg(jsonb_build_object('entity_type','course','entity_id',id,'source_url',url) order by id),
         count(*) filter(where url is not null)
  into v_items,v_count from chosen where url is not null;

  if v_items is null or v_count=0 then
    if v_bound then
      if v_selected_discovery_count=0 and v_terminal_negative_count=cardinality(v_binding.discovery_course_ids)
         and cardinality(v_binding.sync_course_ids)=cardinality(v_binding.discovery_course_ids) then
        update pipeline.scheduler_workflow_async_bindings
        set status='handoff_started',handoff_started_at=coalesce(handoff_started_at,now())
        where preview_token=v_binding.preview_token and profile_id=v_binding.profile_id and status='active';
        update pipeline.jobs j
        set result=coalesce(j.result,'{}'::jsonb)||jsonb_build_object(
          'async_handoffs',coalesce(j.result->'async_handoffs','[]'::jsonb)||jsonb_build_array(jsonb_build_object(
            'profile_id',p_profile_id,'terminal_only',true,'requested_count',cardinality(v_binding.sync_course_ids),
            'terminal_negative_count',v_terminal_negative_count,'recorded_at',now()
          )))
        where j.id=v_binding.preview_token and j.job_type='scheduler_workflow_preview' and j.requested_by=p_actor;
        return jsonb_build_object('ok',true,'status','terminal_only_complete','profile_id',p_profile_id,
          'requested_count',cardinality(v_binding.sync_course_ids),'target_count',0,
          'selected_discovery_count',0,'terminal_negative_count',v_terminal_negative_count,
          'scheduler_preview_token',v_binding.preview_token);
      end if;
      raise exception 'preview-bound Layer 2 handoff has no queueable courses after discovery without exact terminal accounting' using errcode='22023';
    end if;
    return jsonb_build_object('ok',true,'status','nothing_queueable','profile_id',p_profile_id,'requested_count',coalesce(array_length(p_course_ids,1),0));
  end if;

  v_batch:=public.layer2_run_batch_create(p_profile_id,'manual',p_actor,v_items);
  v_req:=public.layer2_run_batch_dispatch(v_batch);
  if v_bound then
    update pipeline.scheduler_workflow_async_bindings set status='handoff_started',handoff_started_at=now()
    where preview_token=v_binding.preview_token and profile_id=v_binding.profile_id;
    update pipeline.jobs set result=result||jsonb_build_object('async_handoff',jsonb_build_object(
      'profile_id',p_profile_id,'profile_version_id',v_binding.profile_version_id,
      'requested_count',cardinality(v_binding.sync_course_ids),'queueable_target_count',v_count,
      'selected_discovery_count',v_selected_discovery_count,'terminal_negative_count',v_terminal_negative_count,
      'terminal_negative_statuses',jsonb_build_array('current_page_not_found','ambiguous','identity_mismatch'),
      'canonical_mutation_authorised',false,'search_publication_authorised',false,'recorded_at',now()))
    where id=v_binding.preview_token;
  end if;

  return jsonb_build_object('ok',true,'status','started','profile_id',p_profile_id,'batch_id',v_batch,
    'dispatch_request_id',v_req,'target_count',v_count,'requested_count',array_length(p_course_ids,1),
    'selected_discovery_count',case when v_bound then v_selected_discovery_count else null end,
    'terminal_negative_count',case when v_bound then v_terminal_negative_count else null end,
    'scheduler_preview_token',case when v_bound then v_binding.preview_token else null end);
end
$function$;

revoke all on function public.layer2_scope_profile_batch_service(uuid,uuid,uuid[]) from public,anon,authenticated;
grant execute on function public.layer2_scope_profile_batch_service(uuid,uuid,uuid[]) to service_role;

commit;
