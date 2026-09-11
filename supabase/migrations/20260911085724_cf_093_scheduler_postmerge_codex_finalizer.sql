begin;

create or replace function security.scheduler_workflow_profile_ids_v1(
  p_country_code text,
  p_scope_type text,
  p_scope_id uuid default null
) returns uuid[]
language sql
stable
security definer
set search_path=''
as $function$
  select coalesce(array_agg(distinct sc.profile_id order by sc.profile_id), '{}'::uuid[])
  from public.layer2_scope_courses(upper(p_country_code),lower(p_scope_type),p_scope_id) sc
$function$;
revoke all on function security.scheduler_workflow_profile_ids_v1(text,text,uuid) from public,anon,authenticated;

create or replace function security.scheduler_workflow_route_gap_count_v1(
  p_country_code text,
  p_scope_type text,
  p_scope_id uuid default null
) returns integer
language sql
stable
security definer
set search_path=''
as $function$
  select count(*)::integer
  from (
    select distinct sc.profile_id
    from public.layer2_scope_courses(upper(p_country_code),lower(p_scope_type),p_scope_id) sc
    where not exists (
      select 1
      from pipeline.layer2_profile_provider_routes r
      join pipeline.layer2_acquisition_providers ap on ap.id=r.acquisition_provider_id
      where r.profile_id=sc.profile_id and r.enabled=true and ap.enabled=true
    )
  ) gaps
$function$;
revoke all on function security.scheduler_workflow_route_gap_count_v1(text,text,uuid) from public,anon,authenticated;

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
  select count(*)::integer
  from (
    select distinct sc.profile_id
    from public.layer2_scope_courses(upper(p_country_code),lower(p_scope_type),p_scope_id) sc
    join pipeline.layer2_source_profiles lp on lp.id=sc.profile_id
    join pipeline.layer2_source_profile_versions pv on pv.id=lp.current_version_id
    where sc.source_url is null
      and not (
        nullif(trim(coalesce(pv.configuration->>'discovery_url','')),'') is not null
        or nullif(trim(coalesce(pv.configuration#>>'{discovery_strategy,catalogue_url}','')),'') is not null
        or (
          lower(coalesce(pv.configuration#>>'{discovery_strategy,type}',''))='first_party_search'
          and nullif(trim(coalesce(pv.configuration#>>'{discovery_strategy,search_url_template}','')),'') is not null
        )
      )
  ) gaps
$function$;
revoke all on function security.scheduler_workflow_discovery_config_gap_count_v1(text,text,uuid) from public,anon,authenticated;

create or replace function security.scheduler_workflow_scope_options_v1_browser_bridge(
  p_country_code text default null,
  p_kind text default 'country',
  p_state_id uuid default null,
  p_query text default null,
  p_limit integer default 10,
  p_offset integer default 0
) returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_actor uuid:=auth.uid();
  v_kind text:=lower(coalesce(nullif(trim(p_kind),''),'country'));
  v_country text:=upper(coalesce(nullif(trim(p_country_code),''),''));
  v_query text:=lower(nullif(trim(coalesce(p_query,'')),''));
  v_limit integer:=least(greatest(coalesce(p_limit,10),1),10);
  v_offset integer:=greatest(coalesce(p_offset,0),0);
  v_items jsonb:='[]'::jsonb;
  v_total integer:=0;
begin
  if v_actor is null or security.current_role_rank() < 4 then
    raise exception 'pipeline operator role required' using errcode='42501';
  end if;
  if v_kind='country' then
    return public.layer2_scope_countries_service(v_actor);
  elsif v_kind='state' then
    with q as (
      select sd.id::text value,sd.name label,sd.code meta
      from ref.subdivisions sd
      join ref.countries co on co.id=sd.country_id
      where upper(co.iso_alpha2::text)=v_country
        and (v_query is null or lower(sd.name||' '||coalesce(sd.code,'')) like '%'||v_query||'%')
        and exists (
          select 1
          from public.layer2_scope_courses(v_country,'state',sd.id) sc
        )
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
    into v_items,v_total;
    return jsonb_build_object('items',v_items,'total',v_total,'limit',v_limit,'offset',v_offset,'has_more',(v_offset+jsonb_array_length(v_items))<v_total,'scope_source','layer2_executable_course_campus_scope');
  elsif v_kind='university' then
    return public.layer2_scope_options_page_service(v_actor,v_country,v_kind,p_state_id,p_query,v_limit,v_offset);
  end if;
  raise exception 'unsupported scope option kind' using errcode='22023';
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
set search_path=''
as $function$
declare
  v_actor uuid:=auth.uid();
  v_workflow text:=lower(coalesce(trim(p_workflow_key),''));
  v_scope text:=lower(coalesce(trim(p_scope_type),''));
  v_result jsonb;
  v_preview_id uuid;
  v_invalid_profiles integer:=0;
  v_policy_gaps integer:=0;
  v_oversized_profiles integer:=0;
  v_route_gaps integer:=0;
  v_discovery_config_gaps integer:=0;
  v_profile_ids uuid[]:='{}'::uuid[];
begin
  if v_actor is null or security.current_role_rank() < 4 then raise exception 'pipeline operator role required' using errcode='42501'; end if;
  if v_workflow <> 'course_facts_l2' then raise exception 'workflow is not executable from Scheduled Tasks' using errcode='22023'; end if;
  if upper(coalesce(trim(p_country_code),'')) <> 'AU' then raise exception 'only AU Layer 2 Course Facts is currently authorised for this builder' using errcode='22023'; end if;
  if v_scope not in ('country','state','university') then raise exception 'unsupported scope type' using errcode='22023'; end if;
  if v_scope in ('state','university') and p_scope_id is null then raise exception 'scope id required' using errcode='22023'; end if;
  if v_scope='country' and p_scope_id is not null then raise exception 'country scope must not include a scope id' using errcode='22023'; end if;

  v_result:=public.layer2_operator_scope_service(v_actor,'preview',upper(p_country_code),v_scope,p_scope_id);
  v_profile_ids:=security.scheduler_workflow_profile_ids_v1(upper(p_country_code),v_scope,p_scope_id);
  select count(distinct sc.profile_id)::integer into v_invalid_profiles
  from public.layer2_scope_courses(upper(p_country_code),v_scope,p_scope_id) sc
  join pipeline.layer2_source_profiles lp on lp.id=sc.profile_id
  left join pipeline.layer2_source_profile_versions pv on pv.id=lp.current_version_id
  where lp.current_version_id is null or pv.id is null or pv.validation_status<>'valid';
  v_policy_gaps:=security.scheduler_workflow_execution_policy_gap_count_v1(upper(p_country_code),v_scope,p_scope_id);
  v_oversized_profiles:=security.scheduler_workflow_oversized_profile_count_v1(upper(p_country_code),v_scope,p_scope_id);
  v_route_gaps:=security.scheduler_workflow_route_gap_count_v1(upper(p_country_code),v_scope,p_scope_id);
  v_discovery_config_gaps:=security.scheduler_workflow_discovery_config_gap_count_v1(upper(p_country_code),v_scope,p_scope_id);

  v_result:=coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
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
    'missing_discovery_config_count',v_discovery_config_gaps,
    'profile_ids',to_jsonb(v_profile_ids)
  );
  if v_invalid_profiles>0 then return v_result||jsonb_build_object('executable',false,'execution_block_reason','One or more Layer 2 Course Facts profiles in this scope do not have a valid current profile version. Requalify the affected profile before dispatch.','preview_token',null,'preview_expires_at',null); end if;
  if v_policy_gaps>0 then return v_result||jsonb_build_object('executable',false,'execution_block_reason','One or more Layer 2 profiles in this scope do not have the execution policy required by deterministic Layer 2 processing. Configure the execution policy before acquisition or dispatch.','preview_token',null,'preview_expires_at',null); end if;
  if v_oversized_profiles>0 then return v_result||jsonb_build_object('executable',false,'execution_block_reason','One or more Layer 2 profiles in this scope exceed the current 1,000-course dispatch contract. Narrow the target scope before dispatch.','preview_token',null,'preview_expires_at',null); end if;
  if v_route_gaps>0 then return v_result||jsonb_build_object('executable',false,'execution_block_reason','One or more Layer 2 profiles in this scope have no enabled acquisition route backed by an enabled provider. Restore a governed route before dispatch.','preview_token',null,'preview_expires_at',null); end if;
  if v_discovery_config_gaps>0 then return v_result||jsonb_build_object('executable',false,'execution_block_reason','One or more profiles requiring discovery lack a worker-compatible discovery URL or first-party search target. Correct the governed profile configuration before dispatch.','preview_token',null,'preview_expires_at',null); end if;
  if cardinality(v_profile_ids)=0 or coalesce((v_result->>'queueable_count')::integer,0)+coalesce((v_result->>'needs_discovery_count')::integer,0)<=0 then
    return v_result||jsonb_build_object('executable',false,'execution_block_reason','No executable Layer 2 work is available for this governed scope. Qualify a Layer 2 Course Facts profile or choose a scope with queueable/discovery work.','preview_token',null,'preview_expires_at',null);
  end if;
  v_result:=v_result||jsonb_build_object('executable',true);
  insert into pipeline.jobs(job_type,domain,status,requested_by,started_at,completed_at,payload,result)
  values('scheduler_workflow_preview','course_facts','completed',v_actor,now(),now(),jsonb_build_object('workflow_key',v_workflow,'country_code',upper(p_country_code),'scope_type',v_scope,'scope_id',p_scope_id,'processing_mode','acquisition_only','change_control_ref','CF-CHG-20260910-093','expires_at',now()+interval '15 minutes'),v_result)
  returning id into v_preview_id;
  return v_result||jsonb_build_object('preview_token',v_preview_id,'preview_expires_at',now()+interval '15 minutes');
end
$function$;

create or replace function security.scheduler_workflow_run_now_v2_browser_bridge(
  p_preview_token uuid,p_workflow_key text,p_country_code text,p_scope_type text,p_scope_id uuid,p_processing_mode text,p_reason text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_actor uuid:=auth.uid(); v_workflow text:=lower(coalesce(trim(p_workflow_key),'')); v_scope text:=lower(coalesce(trim(p_scope_type),'')); v_mode text:=lower(coalesce(trim(p_processing_mode),''));
  v_preview pipeline.jobs%rowtype; v_prior pipeline.jobs%rowtype; v_live_preview jsonb; v_result jsonb; v_scope_key text; v_work integer:=0; v_live_work integer:=0; v_invalid_profiles integer:=0; v_policy_gaps integer:=0; v_oversized_profiles integer:=0; v_route_gaps integer:=0; v_discovery_config_gaps integer:=0;
  v_preview_profiles uuid[]:='{}'::uuid[]; v_live_profiles uuid[]:='{}'::uuid[]; v_started_profiles uuid[]:='{}'::uuid[];
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
  if cardinality(v_preview_profiles)=0 then raise exception 'preview token predates exact profile-set binding; preview again before dispatch' using errcode='22023'; end if;
  v_work:=coalesce((v_preview.result->>'queueable_count')::integer,0)+coalesce((v_preview.result->>'needs_discovery_count')::integer,0);
  if v_work<=0 or coalesce((v_preview.result->>'executable')::boolean,false)=false then raise exception 'previewed scope has no executable Layer 2 work' using errcode='22023'; end if;
  v_live_profiles:=security.scheduler_workflow_profile_ids_v1(upper(p_country_code),v_scope,p_scope_id);
  if v_live_profiles<>v_preview_profiles then raise exception 'Layer 2 profile membership changed after preview; preview again before dispatch' using errcode='22023'; end if;
  select count(distinct sc.profile_id)::integer into v_invalid_profiles from public.layer2_scope_courses(upper(p_country_code),v_scope,p_scope_id) sc join pipeline.layer2_source_profiles lp on lp.id=sc.profile_id left join pipeline.layer2_source_profile_versions pv on pv.id=lp.current_version_id where lp.current_version_id is null or pv.id is null or pv.validation_status<>'valid';
  if v_invalid_profiles>0 then raise exception 'Layer 2 profile qualification changed after preview; preview again after requalification' using errcode='22023'; end if;
  v_policy_gaps:=security.scheduler_workflow_execution_policy_gap_count_v1(upper(p_country_code),v_scope,p_scope_id); if v_policy_gaps>0 then raise exception 'Layer 2 execution policy qualification changed after preview; configure the execution policy and preview again' using errcode='22023'; end if;
  v_oversized_profiles:=security.scheduler_workflow_oversized_profile_count_v1(upper(p_country_code),v_scope,p_scope_id); if v_oversized_profiles>0 then raise exception 'Layer 2 scope exceeds the current 1,000-course per-profile dispatch contract; narrow the target and preview again' using errcode='22023'; end if;
  v_route_gaps:=security.scheduler_workflow_route_gap_count_v1(upper(p_country_code),v_scope,p_scope_id); if v_route_gaps>0 then raise exception 'Layer 2 acquisition route qualification changed after preview; restore the governed route and preview again' using errcode='22023'; end if;
  v_discovery_config_gaps:=security.scheduler_workflow_discovery_config_gap_count_v1(upper(p_country_code),v_scope,p_scope_id); if v_discovery_config_gaps>0 then raise exception 'Layer 2 discovery configuration changed after preview; correct the profile and preview again' using errcode='22023'; end if;
  v_live_preview:=public.layer2_operator_scope_service(v_actor,'preview',upper(p_country_code),v_scope,p_scope_id);
  v_live_work:=coalesce((v_live_preview->>'queueable_count')::integer,0)+coalesce((v_live_preview->>'needs_discovery_count')::integer,0);
  if v_live_work<=0 then raise exception 'Layer 2 runnable scope changed after preview; preview again before dispatch' using errcode='22023'; end if;
  select * into v_prior from pipeline.jobs j where j.id<>p_preview_token and j.job_type='scheduler_workflow_preview' and nullif(j.payload->>'consumed_at','') is not null and (j.payload->>'consumed_at')::timestamptz>=now()-interval '10 minutes' and coalesce(j.payload->>'workflow_key','')=v_workflow and coalesce(j.payload->>'country_code','')=upper(p_country_code) and coalesce(j.payload->>'scope_type','')=v_scope and coalesce(j.payload->>'scope_id','')=coalesce(p_scope_id::text,'') and coalesce(j.payload->>'processing_mode','')=v_mode and j.payload ? 'dispatch_result' order by (j.payload->>'consumed_at')::timestamptz desc limit 1;
  if found then
    update pipeline.jobs set payload=payload||jsonb_build_object('deduplicated_at',now(),'dispatch_result',v_prior.payload->'dispatch_result','deduplicated_against_preview',v_prior.id,'governance_reason',trim(p_reason)) where id=p_preview_token;
    return jsonb_build_object('ok',true,'preview_token',p_preview_token,'existing_recent_dispatch',true,'deduplicated_against_preview',v_prior.id,'result',v_prior.payload->'dispatch_result');
  end if;
  v_result:=public.layer2_operator_scope_service(v_actor,'start',upper(p_country_code),v_scope,p_scope_id);
  select coalesce(array_agg(distinct (e->>'profile_id')::uuid order by (e->>'profile_id')::uuid),'{}'::uuid[]) into v_started_profiles from jsonb_array_elements(coalesce(v_result->'profiles','[]'::jsonb)) e where nullif(e->>'profile_id','') is not null;
  if v_started_profiles<>v_live_profiles then raise exception 'Layer 2 runnable profile set changed during dispatch; transaction rolled back, preview again before dispatch' using errcode='22023'; end if;
  update pipeline.jobs set payload=payload||jsonb_build_object('consumed_at',now(),'dispatch_result',coalesce(v_result,'{}'::jsonb),'governance_reason',trim(p_reason)), result=result||jsonb_build_object('dispatch_result',coalesce(v_result,'{}'::jsonb)) where id=p_preview_token;
  return jsonb_build_object('ok',true,'preview_token',p_preview_token,'idempotent_replay',false,'result',v_result);
end
$function$;

commit;
