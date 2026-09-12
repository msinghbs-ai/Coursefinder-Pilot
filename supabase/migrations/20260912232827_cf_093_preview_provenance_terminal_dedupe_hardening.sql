-- CF-CHG-20260910-093
-- Forward-only hardening. Applied predecessor migrations are immutable.
-- Enforces exact Preview provenance at deterministic handoff, fail-closed binding lookup,
-- terminal-only completion, mixed-scope accounting, async completion-aware dedupe,
-- and idempotent cancellation audit preservation.

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

  select * into v_profile
  from pipeline.layer2_source_profiles
  where id=p_profile_id and domain='course_facts' and enabled and not paused;
  if not found then raise exception 'profile not executable' using errcode='22023'; end if;

  select coalesce(array_agg(distinct x order by x),'{}'::uuid[]) into v_sync
  from unnest(coalesce(p_course_ids,'{}'::uuid[])) x;

  if v_expected_preview is not null then
    select * into v_binding
    from pipeline.scheduler_workflow_async_bindings b
    where b.preview_token=v_expected_preview
      and b.actor_id=p_actor
      and b.profile_id=p_profile_id
      and b.sync_course_ids=v_sync
      and b.status in ('active','handoff_started')
    order by b.created_at desc limit 1 for update;
    if not found then
      raise exception 'exact scheduler Preview binding is missing, cancelled, expired or does not match the handoff scope' using errcode='22023';
    end if;
  else
    select * into v_binding
    from pipeline.scheduler_workflow_async_bindings b
    where b.actor_id=p_actor and b.profile_id=p_profile_id and b.sync_course_ids=v_sync
      and b.status in ('active','handoff_started')
    order by b.created_at desc limit 1 for update;
  end if;

  if found or v_expected_preview is not null then
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
        select 1
        from pipeline.layer2_course_discovery_candidates d
        join pipeline.layer2_provider_attempts pa on pa.id=d.provider_attempt_id
        join pipeline.jobs j on j.id=pa.job_id
        where d.course_id=cid
          and d.source_profile_version_id=v_binding.profile_version_id
          and d.created_at>=v_binding.activated_at
          and j.payload->>'scheduler_preview_token'=v_binding.preview_token::text
          and ((d.selected=true and nullif(d.discovered_url,'') is not null)
            or (d.selected=false and d.status in ('current_page_not_found','ambiguous','identity_mismatch')))
      )
    ) then raise exception 'scheduler async discovery has transient, unattempted or non-Preview-bound courses without a governed terminal outcome' using errcode='22023'; end if;

    select count(*)::integer into v_selected_discovery_count
    from unnest(v_binding.discovery_course_ids) cid
    where exists(
      select 1
      from pipeline.layer2_course_discovery_candidates d
      join pipeline.layer2_provider_attempts pa on pa.id=d.provider_attempt_id
      join pipeline.jobs j on j.id=pa.job_id
      where d.course_id=cid and d.source_profile_version_id=v_binding.profile_version_id
        and d.created_at>=v_binding.activated_at and d.selected=true and nullif(d.discovered_url,'') is not null
        and j.payload->>'scheduler_preview_token'=v_binding.preview_token::text
    );

    select count(*)::integer into v_terminal_negative_count
    from unnest(v_binding.discovery_course_ids) cid
    where not exists(
      select 1
      from pipeline.layer2_course_discovery_candidates d
      join pipeline.layer2_provider_attempts pa on pa.id=d.provider_attempt_id
      join pipeline.jobs j on j.id=pa.job_id
      where d.course_id=cid and d.source_profile_version_id=v_binding.profile_version_id
        and d.created_at>=v_binding.activated_at and d.selected=true and nullif(d.discovered_url,'') is not null
        and j.payload->>'scheduler_preview_token'=v_binding.preview_token::text
    ) and exists(
      select 1
      from pipeline.layer2_course_discovery_candidates d
      join pipeline.layer2_provider_attempts pa on pa.id=d.provider_attempt_id
      join pipeline.jobs j on j.id=pa.job_id
      where d.course_id=cid and d.source_profile_version_id=v_binding.profile_version_id
        and d.created_at>=v_binding.activated_at and d.selected=false
        and d.status in ('current_page_not_found','ambiguous','identity_mismatch')
        and j.payload->>'scheduler_preview_token'=v_binding.preview_token::text
    );
  end if;

  select s.provider_id into v_provider from pipeline.sources s where s.id=v_profile.source_id;

  select b.id into v_active
  from pipeline.layer2_run_batches b
  where b.profile_id=p_profile_id and (b.status in ('queued','running') or
    (b.status='partial' and exists(select 1 from pipeline.layer2_run_items i where i.batch_id=b.id and i.status in ('queued','running'))))
  order by b.created_at desc limit 1;
  if v_active is not null then
    if v_bound then raise exception 'preview-bound Layer 2 handoff conflicts with an existing active batch' using errcode='55000'; end if;
    return jsonb_build_object('ok',true,'status','already_running','batch_id',v_active,'profile_id',p_profile_id);
  end if;

  with chosen as (
    select c.id,
      case when v_bound then coalesce((
        select d.discovered_url
        from pipeline.layer2_course_discovery_candidates d
        join pipeline.layer2_provider_attempts pa on pa.id=d.provider_attempt_id
        join pipeline.jobs j on j.id=pa.job_id
        where d.course_id=c.id and d.source_profile_version_id=v_binding.profile_version_id
          and d.created_at>=v_binding.activated_at and d.selected=true and nullif(d.discovered_url,'') is not null
          and j.payload->>'scheduler_preview_token'=v_binding.preview_token::text
        order by d.created_at desc limit 1
      ),nullif(c.course_url,'')) else coalesce((
        select d.discovered_url from pipeline.layer2_course_discovery_candidates d
        where d.course_id=c.id and d.source_profile_version_id=v_profile.current_version_id
          and d.selected=true and nullif(d.discovered_url,'') is not null
        order by d.created_at desc limit 1
      ),nullif(c.course_url,'')) end url
    from catalogue.courses c where c.provider_id=v_provider and c.id=any(p_course_ids)
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

create or replace function public.layer2_operator_scope_service(p_actor uuid,p_action text,p_country_code text default null,p_scope_type text default 'country',p_scope_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','pipeline','catalogue','ref','security'
as $function$
declare
  v_rank integer:=0; v_result jsonb; v_results jsonb:='[]'::jsonb; r record;
  v_all uuid[]; v_missing uuid[]; v_started jsonb;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  if p_actor is null then raise exception 'actor required' using errcode='42501'; end if;
  select coalesce(max(role.rank),0) into v_rank from security.user_roles ur join security.roles role on role.code=ur.role_code where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and role.status='active';
  if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
  if p_action='options' then
    return jsonb_build_object(
      'countries',(select coalesce(jsonb_agg(distinct jsonb_build_object('code',c.iso_alpha2::text,'name',c.name)),'[]'::jsonb) from pipeline.layer2_source_profiles lp join pipeline.sources s on s.id=lp.source_id join ref.countries c on c.id=s.country_id where lp.domain='course_facts' and lp.enabled and not lp.paused),
      'states',(select coalesce(jsonb_agg(x.obj order by x.name),'[]'::jsonb) from (select distinct sd.name,jsonb_build_object('id',sd.id,'code',sd.code,'name',sd.name) obj from pipeline.layer2_source_profiles lp join pipeline.sources s on s.id=lp.source_id join ref.countries co on co.id=s.country_id join catalogue.courses c on c.provider_id=s.provider_id join catalogue.course_campuses ccx on ccx.course_id=c.id join catalogue.campuses cam on cam.id=ccx.campus_id join ref.subdivisions sd on sd.id=cam.subdivision_id where lp.domain='course_facts' and lp.enabled and not lp.paused and (p_country_code is null or upper(co.iso_alpha2::text)=upper(p_country_code))) x),
      'universities',(select coalesce(jsonb_agg(x.obj order by x.name),'[]'::jsonb) from (select distinct cp.canonical_name name,jsonb_build_object('id',cp.id,'name',cp.canonical_name,'profile_id',lp.id) obj from pipeline.layer2_source_profiles lp join pipeline.sources s on s.id=lp.source_id join ref.countries co on co.id=s.country_id join catalogue.providers cp on cp.id=s.provider_id where lp.domain='course_facts' and lp.enabled and not lp.paused and (p_country_code is null or upper(co.iso_alpha2::text)=upper(p_country_code))) x));
  end if;
  if p_country_code is null then raise exception 'country required' using errcode='22023'; end if;
  if lower(p_scope_type) not in ('country','state','university') then raise exception 'invalid scope type' using errcode='22023'; end if;
  if lower(p_scope_type) in ('state','university') and p_scope_id is null then raise exception 'scope id required' using errcode='22023'; end if;
  if p_action='preview' then
    select jsonb_build_object('ok',true,'country_code',upper(p_country_code),'scope_type',lower(p_scope_type),'scope_id',p_scope_id,'university_count',count(distinct sc.provider_id),'catalogue_count',count(distinct sc.course_id),'queueable_count',count(distinct sc.course_id) filter(where sc.source_url is not null),'needs_discovery_count',count(distinct sc.course_id) filter(where sc.source_url is null and not security.scheduler_workflow_recent_terminal_negative_v1(sc.profile_id,sc.course_id)),'terminal_negative_count',count(distinct sc.course_id) filter(where sc.source_url is null and security.scheduler_workflow_recent_terminal_negative_v1(sc.profile_id,sc.course_id)),'active_run_count',(select count(*) from pipeline.layer2_run_batches b where b.profile_id in(select distinct q.profile_id from public.layer2_scope_courses(p_country_code,p_scope_type,p_scope_id) q) and (b.status in ('queued','running') or (b.status='partial' and b.completed_at is null)))) into v_result from public.layer2_scope_courses(p_country_code,p_scope_type,p_scope_id) sc;
    return coalesce(v_result,jsonb_build_object('ok',true,'country_code',upper(p_country_code),'scope_type',lower(p_scope_type),'catalogue_count',0,'queueable_count',0,'needs_discovery_count',0,'terminal_negative_count',0,'university_count',0,'profiles','[]'::jsonb));
  end if;
  if p_action='start' then
    if upper(p_country_code)='NZ' then raise exception 'NZ Layer 2 Course enrichment is deferred' using errcode='22023'; end if;
    for r in select sc.profile_id,sc.profile_key,sc.provider_name,array_agg(sc.course_id order by sc.course_id) all_ids,array_agg(sc.course_id order by sc.course_id) filter(where sc.source_url is null and not security.scheduler_workflow_recent_terminal_negative_v1(sc.profile_id,sc.course_id)) missing_ids,count(*) total_count,count(*) filter(where sc.source_url is null and not security.scheduler_workflow_recent_terminal_negative_v1(sc.profile_id,sc.course_id)) missing_count,count(*) filter(where sc.source_url is null and security.scheduler_workflow_recent_terminal_negative_v1(sc.profile_id,sc.course_id)) terminal_negative_count from public.layer2_scope_courses(p_country_code,p_scope_type,p_scope_id) sc group by sc.profile_id,sc.profile_key,sc.provider_name order by sc.provider_name
    loop
      v_all:=r.all_ids; v_missing:=r.missing_ids;
      if r.missing_count>0 then
        v_started:=security.layer2_discovery_scope_dispatch_v2(r.profile_id,v_missing,50,p_actor,v_all);
        v_results:=v_results||jsonb_build_array(jsonb_build_object('profile_id',r.profile_id,'profile_key',r.profile_key,'provider_name',r.provider_name,'status','discovery_started','total_count',r.total_count,'needs_discovery',r.missing_count,'fresh_terminal_negative_count',r.terminal_negative_count,'request_id',v_started->'request_id'));
      elsif r.terminal_negative_count=r.total_count then
        v_results:=v_results||jsonb_build_array(jsonb_build_object('profile_id',r.profile_id,'profile_key',r.profile_key,'provider_name',r.provider_name,'status','terminal_only','total_count',r.total_count,'requested_count',r.total_count,'target_count',0,'fresh_terminal_negative_count',r.terminal_negative_count));
      else
        v_started:=public.layer2_scope_profile_batch_service(p_actor,r.profile_id,v_all);
        v_results:=v_results||jsonb_build_array(v_started||jsonb_build_object('profile_key',r.profile_key,'provider_name',r.provider_name,'fresh_terminal_negative_count',r.terminal_negative_count));
      end if;
    end loop;
    return jsonb_build_object('ok',true,'status','scope_started','country_code',upper(p_country_code),'scope_type',lower(p_scope_type),'scope_id',p_scope_id,'profiles',v_results);
  end if;
  raise exception 'unsupported action' using errcode='22023';
end
$function$;

create or replace function security.scheduler_workflow_dispatch_dedupe_anchor_v1(p_dispatch_result jsonb,p_consumed_at timestamptz)
returns timestamptz
language sql
stable security definer
set search_path to ''
as $function$
with preview_job as (
  select j.id,j.result from pipeline.jobs j where j.job_type='scheduler_workflow_preview' and j.payload->'dispatch_result'=p_dispatch_result and nullif(j.payload->>'consumed_at','') is not null and (j.payload->>'consumed_at')::timestamptz=p_consumed_at order by j.created_at desc limit 1
), expected_async as (
  select distinct (e->>'profile_id')::uuid profile_id from jsonb_array_elements(coalesce(p_dispatch_result->'profiles','[]'::jsonb)) e where e->>'status'='discovery_started' and nullif(e->>'profile_id','') is not null
), completions as (
  select distinct (e->>'profile_id')::uuid profile_id,nullif(e->>'batch_id','')::uuid batch_id,coalesce((e->>'terminal_only')::boolean,false) terminal_only,nullif(e->>'recorded_at','')::timestamptz recorded_at from preview_job j cross join lateral jsonb_array_elements(coalesce(j.result->'async_handoffs','[]'::jsonb)) e where nullif(e->>'profile_id','') is not null
  union all
  select (j.result->'async_handoff'->>'profile_id')::uuid,nullif(j.result->'async_handoff'->>'batch_id','')::uuid,false,nullif(j.result->'async_handoff'->>'recorded_at','')::timestamptz from preview_job j where nullif(j.result->'async_handoff'->>'profile_id','') is not null
), async_check as (
  select (select count(*) from expected_async) expected_count,(select count(*) from expected_async ea where exists(select 1 from completions c where c.profile_id=ea.profile_id and (c.batch_id is not null or c.terminal_only))) completed_count
), direct_ids as (
  select distinct nullif(e->>'batch_id','')::uuid batch_id from jsonb_array_elements(coalesce(p_dispatch_result->'profiles','[]'::jsonb)) e where nullif(e->>'batch_id','') is not null
), async_ids as (
  select distinct batch_id from completions where batch_id is not null
), batch_ids as (select batch_id from direct_ids union select batch_id from async_ids),
stats as (
  select count(*)::integer referenced_count,count(b.id)::integer found_count,count(*) filter(where b.status in ('completed','partial') and b.completed_at is not null)::integer reusable_count,max(b.completed_at) latest_completed_at from batch_ids x left join pipeline.layer2_run_batches b on b.id=x.batch_id
), terminal_anchor as (select max(recorded_at) ts from completions where terminal_only)
select case
  when (select expected_count<>completed_count from async_check) then null
  when referenced_count=0 then greatest(p_consumed_at,coalesce((select ts from terminal_anchor),p_consumed_at))
  when found_count=referenced_count and reusable_count=referenced_count then greatest(latest_completed_at,coalesce((select ts from terminal_anchor),latest_completed_at))
  else null end
from stats
$function$;

create or replace function security.scheduler_workflow_async_binding_cancel_v1(p_actor uuid,p_preview_token uuid,p_reason text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare v_reason text:=trim(coalesce(p_reason,'')); v_total integer:=0; v_changed integer:=0; v_blocked integer:=0; v_profiles jsonb;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  if p_actor is null or p_preview_token is null then raise exception 'actor and preview token required' using errcode='22023'; end if;
  if length(v_reason)<5 then raise exception 'cancellation reason required' using errcode='22023'; end if;
  perform 1 from pipeline.scheduler_workflow_async_bindings b where b.preview_token=p_preview_token and b.actor_id=p_actor for update;
  select count(*),count(*) filter(where status not in ('prepared','active','cancelled')),coalesce(jsonb_agg(jsonb_build_object('profile_id',profile_id,'status',status) order by profile_id),'[]'::jsonb) into v_total,v_blocked,v_profiles from pipeline.scheduler_workflow_async_bindings b where b.preview_token=p_preview_token and b.actor_id=p_actor;
  if v_total=0 then raise exception 'scheduler async binding not found for actor' using errcode='22023'; end if;
  if v_blocked>0 then raise exception 'one or more scheduler async bindings cannot be cancelled from current status' using errcode='22023'; end if;
  update pipeline.scheduler_workflow_async_bindings set status='cancelled',execution_expires_at=least(coalesce(execution_expires_at,now()),now()) where preview_token=p_preview_token and actor_id=p_actor and status in ('prepared','active');
  get diagnostics v_changed=row_count;
  if v_changed>0 then
    update pipeline.jobs set payload=coalesce(payload,'{}'::jsonb)||jsonb_build_object('async_binding_cancelled_at',now(),'async_binding_cancelled_by',p_actor,'async_binding_cancellation_reason',v_reason,'change_control_ref','CF-CHG-20260910-093') where id=p_preview_token and job_type='scheduler_workflow_preview' and requested_by=p_actor;
  end if;
  return jsonb_build_object('ok',true,'preview_token',p_preview_token,'binding_count',v_total,'cancelled_count',v_changed,'profiles',v_profiles,'status','cancelled','idempotent_replay',v_changed=0);
end
$function$;

-- Browser bridge: retain all predecessor qualification checks and accept only an exactly
-- accounted terminal-only profile inside an otherwise executable mixed scope.
create or replace function security.scheduler_workflow_run_now_v2_browser_bridge(p_preview_token uuid,p_workflow_key text,p_country_code text,p_scope_type text,p_scope_id uuid,p_processing_mode text,p_reason text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
 v_actor uuid:=auth.uid(); v_workflow text:=lower(coalesce(trim(p_workflow_key),'')); v_scope text:=lower(coalesce(trim(p_scope_type),'')); v_mode text:=lower(coalesce(trim(p_processing_mode),''));
 v_preview pipeline.jobs%rowtype; v_prior pipeline.jobs%rowtype; v_live_snapshot jsonb; v_post_snapshot jsonb; v_result jsonb; v_scope_key text; v_invalid_profiles integer:=0; v_policy_gaps integer:=0; v_oversized_profiles integer:=0; v_route_gaps integer:=0; v_discovery_config_gaps integer:=0;
 v_preview_profiles uuid[]:='{}'::uuid[]; v_live_profiles uuid[]:='{}'::uuid[]; v_started_profiles uuid[]:='{}'::uuid[]; v_preview_fingerprint text; v_live_fingerprint text; v_dedupe_minutes integer:=10;
begin
 if v_actor is null or security.current_role_rank()<4 then raise exception 'pipeline operator role required' using errcode='42501'; end if;
 if length(trim(coalesce(p_reason,'')))<5 then raise exception 'governance reason required' using errcode='22023'; end if;
 if v_workflow<>'course_facts_l2' or upper(coalesce(trim(p_country_code),''))<>'AU' then raise exception 'workflow is not executable from Scheduled Tasks' using errcode='22023'; end if;
 if v_scope not in ('country','state','university') then raise exception 'unsupported scope type' using errcode='22023'; end if;
 if v_scope in ('state','university') and p_scope_id is null then raise exception 'scope id required' using errcode='22023'; end if;
 if v_scope='country' and p_scope_id is not null then raise exception 'country scope must not include a scope id' using errcode='22023'; end if;
 if v_mode<>'acquisition_only' then raise exception 'processing mode is not yet qualified for generic Scheduled Tasks execution' using errcode='22023'; end if;
 if p_preview_token is null then raise exception 'valid preview token required' using errcode='22023'; end if;
 v_scope_key:=v_workflow||'|'||upper(p_country_code)||'|'||v_scope||'|'||coalesce(p_scope_id::text,'country')||'|'||v_mode; perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_scope_key,0));
 select * into v_preview from pipeline.jobs j where j.id=p_preview_token and j.job_type='scheduler_workflow_preview' and j.requested_by=v_actor and j.created_at>=now()-interval '15 minutes' for update;
 if not found then raise exception 'preview token is missing, expired or belongs to another actor' using errcode='22023'; end if;
 if coalesce(v_preview.payload->>'workflow_key','')<>v_workflow or coalesce(v_preview.payload->>'country_code','')<>upper(p_country_code) or coalesce(v_preview.payload->>'scope_type','')<>v_scope or coalesce(v_preview.payload->>'scope_id','')<>coalesce(p_scope_id::text,'') or coalesce(v_preview.payload->>'processing_mode','')<>v_mode then raise exception 'preview token does not match the exact requested workflow target' using errcode='22023'; end if;
 if v_preview.payload?'dispatch_result' then return jsonb_build_object('ok',true,'preview_token',p_preview_token,'idempotent_replay',true,'result',v_preview.payload->'dispatch_result'); end if;
 select coalesce(array_agg((x)::uuid order by (x)::uuid),'{}'::uuid[]) into v_preview_profiles from jsonb_array_elements_text(coalesce(v_preview.result->'profile_ids','[]'::jsonb)) x; v_preview_fingerprint:=nullif(v_preview.result->>'scope_fingerprint','');
 if cardinality(v_preview_profiles)=0 or v_preview_fingerprint is null then raise exception 'preview token predates exact runnable-scope binding; preview again before dispatch' using errcode='22023'; end if;
 if coalesce((v_preview.result->>'executable')::boolean,false)=false then raise exception 'previewed scope has no executable Layer 2 work' using errcode='22023'; end if;
 v_live_snapshot:=security.scheduler_workflow_scope_snapshot_v2(upper(p_country_code),v_scope,p_scope_id); select coalesce(array_agg((x)::uuid order by (x)::uuid),'{}'::uuid[]) into v_live_profiles from jsonb_array_elements_text(coalesce(v_live_snapshot->'profile_ids','[]'::jsonb)) x; v_live_fingerprint:=v_live_snapshot->>'scope_fingerprint';
 if v_live_profiles<>v_preview_profiles or coalesce(v_live_fingerprint,'')<>v_preview_fingerprint then raise exception 'Layer 2 runnable scope changed after preview; preview again before dispatch' using errcode='22023'; end if;
 if coalesce((v_live_snapshot->>'queueable_count')::integer,0)+coalesce((v_live_snapshot->>'needs_discovery_count')::integer,0)<=0 then raise exception 'Layer 2 runnable scope changed after preview; preview again before dispatch' using errcode='22023'; end if;
 select count(distinct sc.profile_id)::integer into v_invalid_profiles from public.layer2_scope_courses(upper(p_country_code),v_scope,p_scope_id) sc join pipeline.layer2_source_profiles lp on lp.id=sc.profile_id left join pipeline.layer2_source_profile_versions pv on pv.id=lp.current_version_id where lp.current_version_id is null or pv.id is null or pv.validation_status<>'valid'; if v_invalid_profiles>0 then raise exception 'Layer 2 profile qualification changed after preview; preview again after requalification' using errcode='22023'; end if;
 v_policy_gaps:=security.scheduler_workflow_execution_policy_gap_count_v1(upper(p_country_code),v_scope,p_scope_id); if v_policy_gaps>0 then raise exception 'Layer 2 execution policy qualification changed after preview; configure the execution policy and preview again' using errcode='22023'; end if;
 v_oversized_profiles:=security.scheduler_workflow_oversized_profile_count_v1(upper(p_country_code),v_scope,p_scope_id); if v_oversized_profiles>0 then raise exception 'Layer 2 scope exceeds the current 1,000-course per-profile dispatch contract; narrow the target and preview again' using errcode='22023'; end if;
 v_route_gaps:=security.scheduler_workflow_route_gap_count_v1(upper(p_country_code),v_scope,p_scope_id); if v_route_gaps>0 then raise exception 'Layer 2 acquisition route qualification changed after preview; restore a runtime-usable governed route and preview again' using errcode='22023'; end if;
 v_discovery_config_gaps:=security.scheduler_workflow_discovery_config_gap_count_v1(upper(p_country_code),v_scope,p_scope_id); if v_discovery_config_gaps>0 then raise exception 'Layer 2 source/discovery URL qualification changed after preview; correct the worker-valid HTTPS target/allowlist and preview again' using errcode='22023'; end if;
 select greatest(10,coalesce(max(ep.stale_after_minutes),10))::integer into v_dedupe_minutes from pipeline.layer2_execution_policies ep where ep.profile_id=any(v_live_profiles) and ep.enabled;
 select * into v_prior from pipeline.jobs j where j.id<>p_preview_token and j.job_type='scheduler_workflow_preview' and nullif(j.payload->>'consumed_at','') is not null and security.scheduler_workflow_dispatch_dedupe_anchor_v1(j.payload->'dispatch_result',(j.payload->>'consumed_at')::timestamptz)>=now()-make_interval(mins=>v_dedupe_minutes) and coalesce(j.payload->>'workflow_key','')=v_workflow and coalesce(j.payload->>'country_code','')=upper(p_country_code) and coalesce(j.payload->>'scope_type','')=v_scope and coalesce(j.payload->>'scope_id','')=coalesce(p_scope_id::text,'') and coalesce(j.payload->>'processing_mode','')=v_mode and coalesce(j.result->>'scope_fingerprint','')=v_live_fingerprint and coalesce(j.result->'profile_ids','[]'::jsonb)=to_jsonb(v_live_profiles) and j.payload?'dispatch_result' order by (j.payload->>'consumed_at')::timestamptz desc limit 1;
 if found then update pipeline.jobs set payload=payload||jsonb_build_object('deduplicated_at',now(),'dispatch_result',v_prior.payload->'dispatch_result','deduplicated_against_preview',v_prior.id,'dedupe_horizon_minutes',v_dedupe_minutes,'governance_reason',trim(p_reason)) where id=p_preview_token; return jsonb_build_object('ok',true,'preview_token',p_preview_token,'existing_recent_dispatch',true,'deduplicated_against_preview',v_prior.id,'dedupe_horizon_minutes',v_dedupe_minutes,'result',v_prior.payload->'dispatch_result'); end if;
 perform set_config('coursefinder.scheduler_preview_token',p_preview_token::text,true);
 v_result:=public.layer2_operator_scope_service(v_actor,'start',upper(p_country_code),v_scope,p_scope_id);
 select coalesce(array_agg(distinct (e->>'profile_id')::uuid order by (e->>'profile_id')::uuid),'{}'::uuid[]) into v_started_profiles from jsonb_array_elements(coalesce(v_result->'profiles','[]'::jsonb)) e where nullif(e->>'profile_id','') is not null;
 if v_started_profiles<>v_live_profiles then raise exception 'Layer 2 runnable profile set changed during dispatch; transaction rolled back, preview again before dispatch' using errcode='22023'; end if;
 if exists(select 1 from jsonb_array_elements(coalesce(v_result->'profiles','[]'::jsonb)) e where coalesce(e->>'status','') not in ('started','discovery_started','terminal_only') or (e->>'status'='started' and (nullif(e->>'batch_id','') is null or nullif(e->>'dispatch_request_id','') is null or coalesce((e->>'target_count')::integer,-1)+coalesce((e->>'fresh_terminal_negative_count')::integer,0)<>coalesce((e->>'requested_count')::integer,-2))) or (e->>'status'='discovery_started' and nullif(e->>'request_id','') is null) or (e->>'status'='terminal_only' and (coalesce((e->>'target_count')::integer,-1)<>0 or coalesce((e->>'fresh_terminal_negative_count')::integer,-1)<>coalesce((e->>'requested_count')::integer,-2)))) then raise exception 'Layer 2 dispatch did not start or exactly account for the previewed work for every profile; transaction rolled back, resolve active/incompatible work and preview again' using errcode='22023'; end if;
 v_post_snapshot:=security.scheduler_workflow_scope_snapshot_v2(upper(p_country_code),v_scope,p_scope_id); if coalesce(v_post_snapshot->>'scope_fingerprint','')<>v_preview_fingerprint or coalesce(v_post_snapshot->'profile_ids','[]'::jsonb)<>to_jsonb(v_live_profiles) then raise exception 'Layer 2 runnable scope changed during dispatch; transaction rolled back, preview again' using errcode='40001'; end if;
 update pipeline.jobs set payload=payload||jsonb_build_object('consumed_at',now(),'dispatch_result',coalesce(v_result,'{}'::jsonb),'governance_reason',trim(p_reason),'dedupe_horizon_minutes',v_dedupe_minutes),result=result||jsonb_build_object('dispatch_result',coalesce(v_result,'{}'::jsonb)) where id=p_preview_token;
 return jsonb_build_object('ok',true,'preview_token',p_preview_token,'idempotent_replay',false,'dedupe_horizon_minutes',v_dedupe_minutes,'result',v_result);
end
$function$;

comment on function public.layer2_scope_profile_batch_service(uuid,uuid,uuid[]) is 'CF-093 forward hardening: exact Preview provenance required for bound discovery outcomes; terminal-only completion is explicit and no empty batch is created.';
comment on function security.scheduler_workflow_dispatch_dedupe_anchor_v1(jsonb,timestamptz) is 'CF-093 forward hardening: every discovery_started profile requires a reusable async handoff or explicit terminal-only completion before dedupe reuse.';
