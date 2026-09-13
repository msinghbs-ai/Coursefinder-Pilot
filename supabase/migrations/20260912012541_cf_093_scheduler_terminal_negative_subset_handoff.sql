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
  v_selected_discovery_count integer:=0;
  v_terminal_negative_count integer:=0;
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

  select coalesce(array_agg(distinct x order by x),'{}'::uuid[]) into v_sync
  from unnest(coalesce(p_course_ids,'{}'::uuid[])) x;

  select * into v_binding
  from pipeline.scheduler_workflow_async_bindings b
  where b.actor_id=p_actor
    and b.profile_id=p_profile_id
    and b.sync_course_ids=v_sync
    and b.status in ('active','handoff_started')
  order by b.created_at desc
  limit 1
  for update;

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

    -- Every Preview-bound discovery course must have a post-activation governed outcome.
    -- Selected URLs remain CRICOS/detail-verified by the discovery worker. Explicit terminal
    -- negatives are retained as Evidence and are not manufactured into queueable URLs.
    -- Transient worker failures/unattempted courses have no qualifying disposition and block.
    if exists(
      select 1
      from unnest(v_binding.discovery_course_ids) cid
      where not exists(
        select 1
        from pipeline.layer2_course_discovery_candidates d
        where d.course_id=cid
          and d.source_profile_version_id=v_binding.profile_version_id
          and d.created_at>=v_binding.activated_at
          and (
            (d.selected=true and nullif(d.discovered_url,'') is not null)
            or (d.selected=false and d.status in ('current_page_not_found','ambiguous','identity_mismatch'))
          )
      )
    ) then
      raise exception 'scheduler async discovery has transient/unattempted courses without a governed terminal outcome' using errcode='22023';
    end if;

    select count(*)::integer into v_selected_discovery_count
    from unnest(v_binding.discovery_course_ids) cid
    where exists(
      select 1 from pipeline.layer2_course_discovery_candidates d
      where d.course_id=cid
        and d.source_profile_version_id=v_binding.profile_version_id
        and d.created_at>=v_binding.activated_at
        and d.selected=true
        and nullif(d.discovered_url,'') is not null
    );

    select count(*)::integer into v_terminal_negative_count
    from unnest(v_binding.discovery_course_ids) cid
    where not exists(
      select 1 from pipeline.layer2_course_discovery_candidates d
      where d.course_id=cid
        and d.source_profile_version_id=v_binding.profile_version_id
        and d.created_at>=v_binding.activated_at
        and d.selected=true
        and nullif(d.discovered_url,'') is not null
    )
    and exists(
      select 1 from pipeline.layer2_course_discovery_candidates d
      where d.course_id=cid
        and d.source_profile_version_id=v_binding.profile_version_id
        and d.created_at>=v_binding.activated_at
        and d.selected=false
        and d.status in ('current_page_not_found','ambiguous','identity_mismatch')
    );
  end if;

  select s.provider_id into v_provider
  from pipeline.sources s
  where s.id=v_profile.source_id;

  -- Historical partial batches are not live work. Block queued/running batches and only
  -- a partial batch that still contains genuinely live queued/running items.
  select b.id into v_active
  from pipeline.layer2_run_batches b
  where b.profile_id=p_profile_id
    and (
      b.status in ('queued','running')
      or (
        b.status='partial'
        and exists(
          select 1 from pipeline.layer2_run_items i
          where i.batch_id=b.id and i.status in ('queued','running')
        )
      )
    )
  order by b.created_at desc
  limit 1;

  if v_active is not null then
    if v_bound then raise exception 'preview-bound Layer 2 handoff conflicts with an existing active batch' using errcode='55000'; end if;
    return jsonb_build_object('ok',true,'status','already_running','batch_id',v_active,'profile_id',p_profile_id);
  end if;

  with chosen as (
    select c.id,
      coalesce((
        select d.discovered_url
        from pipeline.layer2_course_discovery_candidates d
        where d.course_id=c.id
          and d.source_profile_version_id=v_profile.current_version_id
          and d.selected=true
          and nullif(d.discovered_url,'') is not null
        order by d.created_at desc
        limit 1
      ),nullif(c.course_url,'')) url
    from catalogue.courses c
    where c.provider_id=v_provider and c.id=any(p_course_ids)
  )
  select jsonb_agg(jsonb_build_object('entity_type','course','entity_id',id,'source_url',url) order by id),
         count(*) filter(where url is not null)
  into v_items,v_count
  from chosen
  where url is not null;

  if v_items is null or v_count=0 then
    if v_bound then raise exception 'preview-bound Layer 2 handoff has no queueable courses after discovery' using errcode='22023'; end if;
    return jsonb_build_object('ok',true,'status','nothing_queueable','profile_id',p_profile_id,'requested_count',coalesce(array_length(p_course_ids,1),0));
  end if;

  v_batch:=public.layer2_run_batch_create(p_profile_id,'manual',p_actor,v_items);
  v_req:=public.layer2_run_batch_dispatch(v_batch);

  if v_bound then
    update pipeline.scheduler_workflow_async_bindings
    set status='handoff_started',handoff_started_at=now()
    where preview_token=v_binding.preview_token and profile_id=v_binding.profile_id;

    update pipeline.jobs
    set result=result||jsonb_build_object(
      'async_handoff',jsonb_build_object(
        'profile_id',p_profile_id,
        'profile_version_id',v_binding.profile_version_id,
        'requested_count',cardinality(v_binding.sync_course_ids),
        'queueable_target_count',v_count,
        'selected_discovery_count',v_selected_discovery_count,
        'terminal_negative_count',v_terminal_negative_count,
        'terminal_negative_statuses',jsonb_build_array('current_page_not_found','ambiguous','identity_mismatch'),
        'canonical_mutation_authorised',false,
        'search_publication_authorised',false,
        'recorded_at',now()
      )
    )
    where id=v_binding.preview_token;
  end if;

  return jsonb_build_object(
    'ok',true,
    'status','started',
    'profile_id',p_profile_id,
    'batch_id',v_batch,
    'dispatch_request_id',v_req,
    'target_count',v_count,
    'requested_count',array_length(p_course_ids,1),
    'selected_discovery_count',case when v_bound then v_selected_discovery_count else null end,
    'terminal_negative_count',case when v_bound then v_terminal_negative_count else null end,
    'scheduler_preview_token',case when v_bound then v_binding.preview_token else null end
  );
end
$function$;

revoke all on function public.layer2_scope_profile_batch_service(uuid,uuid,uuid[]) from public,anon,authenticated;
grant execute on function public.layer2_scope_profile_batch_service(uuid,uuid,uuid[]) to service_role;
