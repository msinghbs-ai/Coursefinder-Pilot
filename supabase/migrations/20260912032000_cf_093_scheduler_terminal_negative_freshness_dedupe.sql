-- CF-CHG-20260910-093
-- Large-university scheduler correction:
-- 1. A current-version terminal discovery outcome remains governed Evidence for the
--    profile freshness SLA and must not be rediscovered on an immediately fresh Preview.
-- 2. Fresh-preview dispatch dedupe must remain observable after a legitimate large
--    Layer 2 batch clears. Use the already-governed execution-policy stale horizon,
--    never less than the accepted 10-minute floor.
--
-- This does not create URLs, mutate canonical Layer 1, invoke Layer 3, or authorise
-- Search/Publication. Expired terminal outcomes and profile-version changes rediscover.

create or replace function security.scheduler_workflow_recent_terminal_negative_v1(
  p_profile_id uuid,
  p_course_id uuid
) returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  with profile_ctx as (
    select lp.current_version_id,
           case
             when coalesce(pv.configuration->>'freshness_sla_hours','') ~ '^[0-9]+$'
               then (pv.configuration->>'freshness_sla_hours')::integer
             else null
           end as freshness_sla_hours
    from pipeline.layer2_source_profiles lp
    join pipeline.layer2_source_profile_versions pv on pv.id=lp.current_version_id
    where lp.id=p_profile_id
      and lp.domain='course_facts'
      and lp.enabled
      and not lp.paused
  ), latest as (
    select d.selected,d.status,d.created_at
    from profile_ctx p
    join lateral (
      select x.selected,x.status,x.created_at
      from pipeline.layer2_course_discovery_candidates x
      where x.course_id=p_course_id
        and x.source_profile_version_id=p.current_version_id
      order by x.created_at desc,x.id desc
      limit 1
    ) d on true
  )
  select coalesce(
    (
      select p.freshness_sla_hours is not null
         and p.freshness_sla_hours>0
         and l.selected=false
         and l.status in ('current_page_not_found','ambiguous','identity_mismatch')
         and l.created_at>=now()-make_interval(hours=>p.freshness_sla_hours)
      from profile_ctx p cross join latest l
    ),false
  )
$function$;

revoke all on function security.scheduler_workflow_recent_terminal_negative_v1(uuid,uuid) from public,anon,authenticated;
grant execute on function security.scheduler_workflow_recent_terminal_negative_v1(uuid,uuid) to service_role;

create or replace function security.scheduler_workflow_scope_snapshot_v2(
  p_country_code text,
  p_scope_type text,
  p_scope_id uuid default null
) returns jsonb
language sql
stable
security definer
set search_path to ''
as $function$
  with scoped_base as materialized (
    select sc.profile_id,sc.course_id,sc.source_url,lp.current_version_id,pv.configuration,
           c.course_code,c.canonical_title,c.display_title,
           security.scheduler_workflow_recent_terminal_negative_v1(sc.profile_id,sc.course_id) as recent_terminal_negative
    from public.layer2_scope_courses(upper(p_country_code),lower(p_scope_type),p_scope_id) sc
    join pipeline.layer2_source_profiles lp on lp.id=sc.profile_id
    join pipeline.layer2_source_profile_versions pv on pv.id=lp.current_version_id
    join catalogue.courses c on c.id=sc.course_id
  ), scoped as materialized (
    select profile_id,course_id,source_url,current_version_id,course_code,canonical_title,display_title,recent_terminal_negative,
      case when source_url is null and not recent_terminal_negative then
        case
          when lower(coalesce(configuration#>>'{discovery_strategy,type}',''))='first_party_search'
               and nullif(trim(coalesce(configuration#>>'{discovery_strategy,search_url_template}','')),'') is not null
            then trim(configuration#>>'{discovery_strategy,search_url_template}')
          when nullif(trim(coalesce(configuration#>>'{discovery_strategy,catalogue_url}','')),'') is not null
            then trim(configuration#>>'{discovery_strategy,catalogue_url}')
          else nullif(trim(coalesce(configuration->>'discovery_url','')),'')
        end
      else null end as discovery_target
    from scoped_base
  ), profile_ids as (
    select coalesce(array_agg(distinct profile_id order by profile_id),'{}'::uuid[]) ids from scoped
  ), counts as (
    select count(*) filter (where source_url is not null)::integer queueable_count,
           count(*) filter (where source_url is null and not recent_terminal_negative)::integer needs_discovery_count,
           count(*) filter (where source_url is null and recent_terminal_negative)::integer terminal_negative_count,
           count(*)::integer scoped_course_count,
           md5(coalesce(jsonb_agg(
             jsonb_build_array(
               profile_id::text,
               current_version_id::text,
               course_id::text,
               source_url,
               case when source_url is null and recent_terminal_negative then 'terminal_negative_fresh' else discovery_target end,
               case when source_url is null and not recent_terminal_negative then course_code else null end,
               case when source_url is null and not recent_terminal_negative then canonical_title else null end,
               case when source_url is null and not recent_terminal_negative then display_title else null end
             ) order by profile_id,current_version_id,course_id,coalesce(source_url,''),coalesce(discovery_target,''),coalesce(course_code,''),coalesce(canonical_title,''),coalesce(display_title,'')
           ),'[]'::jsonb)::text) scope_fingerprint
    from scoped
  )
  select jsonb_build_object(
    'profile_ids',to_jsonb(profile_ids.ids),
    'queueable_count',counts.queueable_count,
    'needs_discovery_count',counts.needs_discovery_count,
    'terminal_negative_count',counts.terminal_negative_count,
    'scoped_course_count',counts.scoped_course_count,
    'scope_fingerprint',counts.scope_fingerprint
  )
  from profile_ids cross join counts
$function$;

create or replace function public.layer2_operator_scope_service(
  p_actor uuid,
  p_action text,
  p_country_code text default null,
  p_scope_type text default 'country',
  p_scope_id uuid default null
) returns jsonb
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
  select coalesce(max(role.rank),0) into v_rank
  from security.user_roles ur join security.roles role on role.code=ur.role_code
  where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and role.status='active';
  if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;

  if p_action='options' then
    return jsonb_build_object(
      'countries',(select coalesce(jsonb_agg(distinct jsonb_build_object('code',c.iso_alpha2::text,'name',c.name)),'[]'::jsonb)
        from pipeline.layer2_source_profiles lp join pipeline.sources s on s.id=lp.source_id join ref.countries c on c.id=s.country_id
        where lp.domain='course_facts' and lp.enabled and not lp.paused),
      'states',(select coalesce(jsonb_agg(x.obj order by x.name),'[]'::jsonb) from (
        select distinct sd.name,jsonb_build_object('id',sd.id,'code',sd.code,'name',sd.name) obj
        from pipeline.layer2_source_profiles lp
        join pipeline.sources s on s.id=lp.source_id
        join ref.countries co on co.id=s.country_id
        join catalogue.courses c on c.provider_id=s.provider_id
        join catalogue.course_campuses ccx on ccx.course_id=c.id
        join catalogue.campuses cam on cam.id=ccx.campus_id
        join ref.subdivisions sd on sd.id=cam.subdivision_id
        where lp.domain='course_facts' and lp.enabled and not lp.paused
          and (p_country_code is null or upper(co.iso_alpha2::text)=upper(p_country_code))
      ) x),
      'universities',(select coalesce(jsonb_agg(x.obj order by x.name),'[]'::jsonb) from (
        select distinct cp.canonical_name name,jsonb_build_object('id',cp.id,'name',cp.canonical_name,'profile_id',lp.id) obj
        from pipeline.layer2_source_profiles lp
        join pipeline.sources s on s.id=lp.source_id
        join ref.countries co on co.id=s.country_id
        join catalogue.providers cp on cp.id=s.provider_id
        where lp.domain='course_facts' and lp.enabled and not lp.paused
          and (p_country_code is null or upper(co.iso_alpha2::text)=upper(p_country_code))
      ) x)
    );
  end if;

  if p_country_code is null then raise exception 'country required' using errcode='22023'; end if;
  if lower(p_scope_type) not in ('country','state','university') then raise exception 'invalid scope type' using errcode='22023'; end if;
  if lower(p_scope_type) in ('state','university') and p_scope_id is null then raise exception 'scope id required' using errcode='22023'; end if;

  if p_action='preview' then
    select jsonb_build_object(
      'ok',true,'country_code',upper(p_country_code),'scope_type',lower(p_scope_type),'scope_id',p_scope_id,
      'university_count',count(distinct sc.provider_id),
      'catalogue_count',count(distinct sc.course_id),
      'queueable_count',count(distinct sc.course_id) filter(where sc.source_url is not null),
      'needs_discovery_count',count(distinct sc.course_id) filter(where sc.source_url is null and not security.scheduler_workflow_recent_terminal_negative_v1(sc.profile_id,sc.course_id)),
      'terminal_negative_count',count(distinct sc.course_id) filter(where sc.source_url is null and security.scheduler_workflow_recent_terminal_negative_v1(sc.profile_id,sc.course_id)),
      'active_run_count',(select count(*) from pipeline.layer2_run_batches b where b.profile_id in (select distinct q.profile_id from public.layer2_scope_courses(p_country_code,p_scope_type,p_scope_id) q) and (b.status in ('queued','running') or (b.status='partial' and b.completed_at is null)))
    ) into v_result
    from public.layer2_scope_courses(p_country_code,p_scope_type,p_scope_id) sc;
    return coalesce(v_result,jsonb_build_object('ok',true,'country_code',upper(p_country_code),'scope_type',lower(p_scope_type),'catalogue_count',0,'queueable_count',0,'needs_discovery_count',0,'terminal_negative_count',0,'university_count',0,'profiles','[]'::jsonb));
  end if;

  if p_action='start' then
    if upper(p_country_code)='NZ' then raise exception 'NZ Layer 2 Course enrichment is deferred' using errcode='22023'; end if;
    for r in
      select sc.profile_id,sc.profile_key,sc.provider_name,
             array_agg(sc.course_id order by sc.course_id) as all_ids,
             array_agg(sc.course_id order by sc.course_id) filter(where sc.source_url is null and not security.scheduler_workflow_recent_terminal_negative_v1(sc.profile_id,sc.course_id)) as missing_ids,
             count(*) as total_count,
             count(*) filter(where sc.source_url is null and not security.scheduler_workflow_recent_terminal_negative_v1(sc.profile_id,sc.course_id)) as missing_count,
             count(*) filter(where sc.source_url is null and security.scheduler_workflow_recent_terminal_negative_v1(sc.profile_id,sc.course_id)) as terminal_negative_count
      from public.layer2_scope_courses(p_country_code,p_scope_type,p_scope_id) sc
      group by sc.profile_id,sc.profile_key,sc.provider_name
      order by sc.provider_name
    loop
      v_all:=r.all_ids; v_missing:=r.missing_ids;
      if r.missing_count>0 then
        v_started:=security.layer2_discovery_scope_dispatch_v2(r.profile_id,v_missing,50,p_actor,v_all);
        v_results:=v_results||jsonb_build_array(jsonb_build_object('profile_id',r.profile_id,'profile_key',r.profile_key,'provider_name',r.provider_name,'status','discovery_started','total_count',r.total_count,'needs_discovery',r.missing_count,'fresh_terminal_negative_count',r.terminal_negative_count,'request_id',v_started->'request_id'));
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

create or replace function security.scheduler_workflow_preview_v1_browser_bridge(
  p_workflow_key text,
  p_country_code text,
  p_scope_type text,
  p_scope_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
 v_actor uuid:=auth.uid(); v_workflow text:=lower(coalesce(trim(p_workflow_key),'')); v_scope text:=lower(coalesce(trim(p_scope_type),''));
 v_result jsonb; v_snapshot jsonb; v_confirm jsonb; v_preview_id uuid; v_binding jsonb;
 v_invalid_profiles integer:=0; v_policy_gaps integer:=0; v_oversized_profiles integer:=0; v_route_gaps integer:=0; v_discovery_config_gaps integer:=0; v_discovery_count integer:=0;
 v_profile_ids uuid[]:='{}'::uuid[]; v_preview_expires timestamptz:=now()+interval '15 minutes'; r record;
begin
 if v_actor is null or security.current_role_rank() < 4 then raise exception 'pipeline operator role required' using errcode='42501'; end if;
 if v_workflow <> 'course_facts_l2' then raise exception 'workflow is not executable from Scheduled Tasks' using errcode='22023'; end if;
 if upper(coalesce(trim(p_country_code),'')) <> 'AU' then raise exception 'only AU Layer 2 Course Facts is currently authorised for this builder' using errcode='22023'; end if;
 if v_scope not in ('country','state','university') then raise exception 'unsupported scope type' using errcode='22023'; end if;
 if v_scope in ('state','university') and p_scope_id is null then raise exception 'scope id required' using errcode='22023'; end if;
 if v_scope='country' and p_scope_id is not null then raise exception 'country scope must not include a scope id' using errcode='22023'; end if;
 v_snapshot:=security.scheduler_workflow_scope_snapshot_v2(upper(p_country_code),v_scope,p_scope_id);
 select coalesce(array_agg((x)::uuid order by (x)::uuid),'{}'::uuid[]) into v_profile_ids from jsonb_array_elements_text(coalesce(v_snapshot->'profile_ids','[]'::jsonb)) x;
 v_discovery_count:=coalesce((v_snapshot->>'needs_discovery_count')::integer,0);
 v_result:=coalesce(public.layer2_operator_scope_service(v_actor,'preview',upper(p_country_code),v_scope,p_scope_id),'{}'::jsonb)||jsonb_build_object('queueable_count',coalesce((v_snapshot->>'queueable_count')::integer,0),'needs_discovery_count',v_discovery_count,'terminal_negative_count',coalesce((v_snapshot->>'terminal_negative_count')::integer,0),'scoped_course_count',coalesce((v_snapshot->>'scoped_course_count')::integer,0),'scope_fingerprint',v_snapshot->>'scope_fingerprint');
 select count(distinct sc.profile_id)::integer into v_invalid_profiles from public.layer2_scope_courses(upper(p_country_code),v_scope,p_scope_id) sc join pipeline.layer2_source_profiles lp on lp.id=sc.profile_id left join pipeline.layer2_source_profile_versions pv on pv.id=lp.current_version_id where lp.current_version_id is null or pv.id is null or pv.validation_status<>'valid';
 v_policy_gaps:=security.scheduler_workflow_execution_policy_gap_count_v1(upper(p_country_code),v_scope,p_scope_id);
 v_oversized_profiles:=security.scheduler_workflow_oversized_profile_count_v1(upper(p_country_code),v_scope,p_scope_id);
 v_route_gaps:=security.scheduler_workflow_route_gap_count_v1(upper(p_country_code),v_scope,p_scope_id);
 v_discovery_config_gaps:=security.scheduler_workflow_discovery_config_gap_count_v1(upper(p_country_code),v_scope,p_scope_id);
 v_confirm:=security.scheduler_workflow_scope_snapshot_v2(upper(p_country_code),v_scope,p_scope_id);
 if coalesce(v_confirm->>'scope_fingerprint','')<>coalesce(v_snapshot->>'scope_fingerprint','') or coalesce(v_confirm->'profile_ids','[]'::jsonb)<>coalesce(v_snapshot->'profile_ids','[]'::jsonb) then raise exception 'Layer 2 scope changed while preview was being constructed; preview again' using errcode='40001'; end if;
 v_result:=v_result||jsonb_build_object('workflow_key','course_facts_l2','workflow_label','Course Facts enrichment','processing_modes',jsonb_build_array(jsonb_build_object('key','acquisition_only','label','Acquisition + deterministic Layer 2','enabled',true),jsonb_build_object('key','automatic_governed_pipeline','label','Automatic governed pipeline','enabled',false,'reason','Conditional Layer 3/L4 orchestration is not yet qualified for generic Scheduled Tasks execution.'),jsonb_build_object('key','reprocess_governed_evidence','label','Reprocess governed Evidence','enabled',false,'reason','Use the governed Layer 3 workspace until an Evidence/profile-specific scheduler contract is accepted.')),'schedule_supported',v_scope='university','schedule_reason',case when v_scope='university' then 'University scope can resolve to an existing qualified Layer 2 source profile; schedule creation remains a separate governed action.' else 'Country/state schedules are not advertised because the current Layer 2 scheduler dispatches profile-wide and cannot enforce a multi-profile scope policy.' end,'invalid_profile_count',v_invalid_profiles,'missing_execution_policy_count',v_policy_gaps,'oversized_profile_count',v_oversized_profiles,'missing_acquisition_route_count',v_route_gaps,'unsupported_discovery_count',0,'preview_bound_discovery_count',v_discovery_count,'missing_discovery_config_count',v_discovery_config_gaps,'profile_ids',to_jsonb(v_profile_ids));
 if v_invalid_profiles>0 then return v_result||jsonb_build_object('executable',false,'execution_block_reason','One or more Layer 2 Course Facts profiles in this scope do not have a valid current profile version. Requalify the affected profile before dispatch.','preview_token',null,'preview_expires_at',null); end if;
 if v_policy_gaps>0 then return v_result||jsonb_build_object('executable',false,'execution_block_reason','One or more Layer 2 profiles in this scope do not have the execution policy required by deterministic Layer 2 processing. Configure the execution policy through the normal governed lifecycle before acquisition or dispatch.','preview_token',null,'preview_expires_at',null); end if;
 if v_oversized_profiles>0 then return v_result||jsonb_build_object('executable',false,'execution_block_reason','One or more Layer 2 profiles in this scope exceed the current 1,000-course dispatch contract. Narrow the target scope before dispatch.','preview_token',null,'preview_expires_at',null); end if;
 if v_route_gaps>0 then return v_result||jsonb_build_object('executable',false,'execution_block_reason','One or more Layer 2 profiles in this scope have no runtime-usable acquisition route under the configured route order and fallback policy. Correct the blocking route/fallback or restore a usable governed route before dispatch.','preview_token',null,'preview_expires_at',null); end if;
 if v_discovery_config_gaps>0 then return v_result||jsonb_build_object('executable',false,'execution_block_reason','One or more Layer 2 discovery targets or queueable Course Facts URLs are not worker-valid under the governed profile configuration. Correct the governed profile before dispatch.','preview_token',null,'preview_expires_at',null); end if;
 if coalesce((v_result->>'active_run_count')::integer,0)>0 then return v_result||jsonb_build_object('executable',false,'execution_block_reason','One or more target profiles already have queued/running Layer 2 work. Wait for the existing governed work to finish before dispatch.','preview_token',null,'preview_expires_at',null); end if;
 if cardinality(v_profile_ids)=0 or coalesce((v_snapshot->>'scoped_course_count')::integer,0)<=0 then return v_result||jsonb_build_object('executable',false,'execution_block_reason','No executable Layer 2 work is available for this governed scope.','preview_token',null,'preview_expires_at',null); end if;
 v_result:=v_result||jsonb_build_object('executable',true,'async_discovery_preview_bound',v_discovery_count>0);
 insert into pipeline.jobs(job_type,domain,status,requested_by,started_at,completed_at,payload,result) values('scheduler_workflow_preview','course_facts','completed',v_actor,now(),now(),jsonb_build_object('workflow_key',v_workflow,'country_code',upper(p_country_code),'scope_type',v_scope,'scope_id',p_scope_id,'processing_mode','acquisition_only','change_control_ref','CF-CHG-20260910-093','expires_at',v_preview_expires),v_result) returning id into v_preview_id;
 for r in
  select sc.profile_id,
         array_agg(distinct sc.course_id order by sc.course_id) sync_ids,
         array_agg(distinct sc.course_id order by sc.course_id) filter(where sc.source_url is null and not security.scheduler_workflow_recent_terminal_negative_v1(sc.profile_id,sc.course_id)) discovery_ids
  from public.layer2_scope_courses(upper(p_country_code),v_scope,p_scope_id) sc
  group by sc.profile_id
  having count(*) filter(where sc.source_url is null and not security.scheduler_workflow_recent_terminal_negative_v1(sc.profile_id,sc.course_id))>0
 loop
  v_binding:=security.scheduler_workflow_profile_binding_snapshot_v1(r.profile_id,r.sync_ids,r.discovery_ids);
  if v_binding is null or coalesce((v_binding->>'all_ids_valid')::boolean,false)=false or coalesce((v_binding->>'discovery_subset_valid')::boolean,false)=false or coalesce((v_binding->>'all_discovery_missing')::boolean,false)=false then raise exception 'Layer 2 async discovery inputs changed while preview was being bound; preview again' using errcode='40001'; end if;
  insert into pipeline.scheduler_workflow_async_bindings(preview_token,actor_id,profile_id,profile_version_id,country_code,scope_type,scope_id,scope_fingerprint,identity_fingerprint,queueable_fingerprint,sync_course_ids,discovery_course_ids,status,preview_expires_at)
  values(v_preview_id,v_actor,r.profile_id,(v_binding->>'profile_version_id')::uuid,'AU',v_scope,p_scope_id,v_snapshot->>'scope_fingerprint',v_binding->>'identity_fingerprint',v_binding->>'queueable_fingerprint',r.sync_ids,r.discovery_ids,'prepared',v_preview_expires);
 end loop;
 return v_result||jsonb_build_object('preview_token',v_preview_id,'preview_expires_at',v_preview_expires,'async_binding_profile_count',(select count(*) from pipeline.scheduler_workflow_async_bindings b where b.preview_token=v_preview_id));
end
$function$;

create or replace function security.scheduler_workflow_run_now_v2_browser_bridge(
  p_preview_token uuid,
  p_workflow_key text,
  p_country_code text,
  p_scope_type text,
  p_scope_id uuid,
  p_processing_mode text,
  p_reason text
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
 v_actor uuid:=auth.uid(); v_workflow text:=lower(coalesce(trim(p_workflow_key),'')); v_scope text:=lower(coalesce(trim(p_scope_type),'')); v_mode text:=lower(coalesce(trim(p_processing_mode),''));
 v_preview pipeline.jobs%rowtype; v_prior pipeline.jobs%rowtype; v_live_snapshot jsonb; v_post_snapshot jsonb; v_result jsonb; v_scope_key text; v_invalid_profiles integer:=0; v_policy_gaps integer:=0; v_oversized_profiles integer:=0; v_route_gaps integer:=0; v_discovery_config_gaps integer:=0;
 v_preview_profiles uuid[]:='{}'::uuid[]; v_live_profiles uuid[]:='{}'::uuid[]; v_started_profiles uuid[]:='{}'::uuid[]; v_preview_fingerprint text; v_live_fingerprint text; v_dedupe_minutes integer:=10;
begin
 if v_actor is null or security.current_role_rank() < 4 then raise exception 'pipeline operator role required' using errcode='42501'; end if;
 if length(trim(coalesce(p_reason,''))) < 5 then raise exception 'governance reason required' using errcode='22023'; end if;
 if v_workflow <> 'course_facts_l2' or upper(coalesce(trim(p_country_code),'')) <> 'AU' then raise exception 'workflow is not executable from Scheduled Tasks' using errcode='22023'; end if;
 if v_scope not in ('country','state','university') then raise exception 'unsupported scope type' using errcode='22023'; end if;
 if v_scope in ('state','university') and p_scope_id is null then raise exception 'scope id required' using errcode='22023'; end if;
 if v_scope='country' and p_scope_id is not null then raise exception 'country scope must not include a scope id' using errcode='22023'; end if;
 if v_mode <> 'acquisition_only' then raise exception 'processing mode is not yet qualified for generic Scheduled Tasks execution' using errcode='22023'; end if;
 if p_preview_token is null then raise exception 'valid preview token required' using errcode='22023'; end if;
 v_scope_key:=v_workflow||'|'||upper(p_country_code)||'|'||v_scope||'|'||coalesce(p_scope_id::text,'country')||'|'||v_mode; perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_scope_key,0));
 select * into v_preview from pipeline.jobs j where j.id=p_preview_token and j.job_type='scheduler_workflow_preview' and j.requested_by=v_actor and j.created_at>=now()-interval '15 minutes' for update;
 if not found then raise exception 'preview token is missing, expired or belongs to another actor' using errcode='22023'; end if;
 if coalesce(v_preview.payload->>'workflow_key','')<>v_workflow or coalesce(v_preview.payload->>'country_code','')<>upper(p_country_code) or coalesce(v_preview.payload->>'scope_type','')<>v_scope or coalesce(v_preview.payload->>'scope_id','')<>coalesce(p_scope_id::text,'') or coalesce(v_preview.payload->>'processing_mode','')<>v_mode then raise exception 'preview token does not match the exact requested workflow target' using errcode='22023'; end if;
 if v_preview.payload ? 'dispatch_result' then return jsonb_build_object('ok',true,'preview_token',p_preview_token,'idempotent_replay',true,'result',v_preview.payload->'dispatch_result'); end if;
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
 select * into v_prior from pipeline.jobs j where j.id<>p_preview_token and j.job_type='scheduler_workflow_preview' and nullif(j.payload->>'consumed_at','') is not null and (j.payload->>'consumed_at')::timestamptz>=now()-make_interval(mins=>v_dedupe_minutes) and coalesce(j.payload->>'workflow_key','')=v_workflow and coalesce(j.payload->>'country_code','')=upper(p_country_code) and coalesce(j.payload->>'scope_type','')=v_scope and coalesce(j.payload->>'scope_id','')=coalesce(p_scope_id::text,'') and coalesce(j.payload->>'processing_mode','')=v_mode and coalesce(j.result->>'scope_fingerprint','')=v_live_fingerprint and coalesce(j.result->'profile_ids','[]'::jsonb)=to_jsonb(v_live_profiles) and j.payload ? 'dispatch_result' order by (j.payload->>'consumed_at')::timestamptz desc limit 1;
 if found then update pipeline.jobs set payload=payload||jsonb_build_object('deduplicated_at',now(),'dispatch_result',v_prior.payload->'dispatch_result','deduplicated_against_preview',v_prior.id,'dedupe_horizon_minutes',v_dedupe_minutes,'governance_reason',trim(p_reason)) where id=p_preview_token; return jsonb_build_object('ok',true,'preview_token',p_preview_token,'existing_recent_dispatch',true,'deduplicated_against_preview',v_prior.id,'dedupe_horizon_minutes',v_dedupe_minutes,'result',v_prior.payload->'dispatch_result'); end if;
 perform set_config('coursefinder.scheduler_preview_token',p_preview_token::text,true);
 v_result:=public.layer2_operator_scope_service(v_actor,'start',upper(p_country_code),v_scope,p_scope_id);
 select coalesce(array_agg(distinct (e->>'profile_id')::uuid order by (e->>'profile_id')::uuid),'{}'::uuid[]) into v_started_profiles from jsonb_array_elements(coalesce(v_result->'profiles','[]'::jsonb)) e where nullif(e->>'profile_id','') is not null;
 if v_started_profiles<>v_live_profiles then raise exception 'Layer 2 runnable profile set changed during dispatch; transaction rolled back, preview again before dispatch' using errcode='22023'; end if;
 if exists(select 1 from jsonb_array_elements(coalesce(v_result->'profiles','[]'::jsonb)) e where coalesce(e->>'status','') not in ('started','discovery_started') or (e->>'status'='started' and (nullif(e->>'batch_id','') is null or nullif(e->>'dispatch_request_id','') is null or coalesce((e->>'target_count')::integer,-1)<>coalesce((e->>'requested_count')::integer,-2))) or (e->>'status'='discovery_started' and nullif(e->>'request_id','') is null)) then raise exception 'Layer 2 dispatch did not start the exact previewed work for every profile; transaction rolled back, resolve active/incompatible work and preview again' using errcode='22023'; end if;
 v_post_snapshot:=security.scheduler_workflow_scope_snapshot_v2(upper(p_country_code),v_scope,p_scope_id); if coalesce(v_post_snapshot->>'scope_fingerprint','')<>v_preview_fingerprint or coalesce(v_post_snapshot->'profile_ids','[]'::jsonb)<>to_jsonb(v_live_profiles) then raise exception 'Layer 2 runnable scope changed during dispatch; transaction rolled back, preview again' using errcode='40001'; end if;
 update pipeline.jobs set payload=payload||jsonb_build_object('consumed_at',now(),'dispatch_result',coalesce(v_result,'{}'::jsonb),'governance_reason',trim(p_reason),'dedupe_horizon_minutes',v_dedupe_minutes),result=result||jsonb_build_object('dispatch_result',coalesce(v_result,'{}'::jsonb)) where id=p_preview_token;
 return jsonb_build_object('ok',true,'preview_token',p_preview_token,'idempotent_replay',false,'dedupe_horizon_minutes',v_dedupe_minutes,'result',v_result);
end
$function$;

revoke all on function public.layer2_operator_scope_service(uuid,text,text,text,uuid) from public,anon,authenticated;
grant execute on function public.layer2_operator_scope_service(uuid,text,text,text,uuid) to service_role;
revoke all on function security.scheduler_workflow_preview_v1_browser_bridge(text,text,text,uuid) from public,anon,authenticated;
revoke all on function security.scheduler_workflow_run_now_v2_browser_bridge(uuid,text,text,text,uuid,text,text) from public,anon,authenticated;
grant execute on function security.scheduler_workflow_preview_v1_browser_bridge(text,text,text,uuid) to service_role;
grant execute on function security.scheduler_workflow_run_now_v2_browser_bridge(uuid,text,text,text,uuid,text,text) to service_role;
