begin;

-- CF-093 forward-only corrective pass.
-- 1) keep generic async discovery fail-closed with an operator-truthful block reason;
-- 2) mirror deterministic worker allowlist parsing for queueable URLs;
-- 3) respect ordered provider-route blocking/fallback semantics before declaring a route usable.

create or replace function security.scheduler_workflow_queueable_url_allowed_v1(p_profile_id uuid,p_url text)
returns boolean
language sql
stable
security definer
set search_path=''
as $function$
  with cfg as (
    select pv.configuration
    from pipeline.layer2_source_profiles lp
    join pipeline.layer2_source_profile_versions pv on pv.id=lp.current_version_id
    where lp.id=p_profile_id
  ), target as (
    select security.scheduler_workflow_https_host_v1(p_url) host
  ), refs(raw) as (
    select configuration->>'base_domain' from cfg
    union all select configuration->>'discovery_url' from cfg
    union all
    select x.value from cfg cross join lateral jsonb_array_elements_text(case when jsonb_typeof(configuration->'url_patterns')='array' then configuration->'url_patterns' else '[]'::jsonb end) x(value)
    union all
    select 'https://'||x.value from cfg cross join lateral jsonb_array_elements_text(case when jsonb_typeof(configuration->'discovery_hosts')='array' then configuration->'discovery_hosts' else '[]'::jsonb end) x(value)
  ), hosts as (
    -- Do not expand {query}: layer2-acquire-v2 builds its allowlist from the configured
    -- URL literally. A placeholder in the hostname therefore must not authorise a
    -- concrete queueable host that the worker itself would reject.
    select distinct security.scheduler_workflow_https_host_v1(raw) host
    from refs where nullif(trim(coalesce(raw,'')),'') is not null
  )
  select coalesce((select target.host is not null and exists(
    select 1 from hosts h
    where h.host is not null and (target.host=h.host or target.host like '%.'||h.host)
  ) from target),false)
$function$;
revoke all on function security.scheduler_workflow_queueable_url_allowed_v1(uuid,text) from public,anon,authenticated;

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
  with scoped_profiles as materialized (
    select distinct sc.profile_id
    from public.layer2_scope_courses(upper(p_country_code),lower(p_scope_type),p_scope_id) sc
  ), route_eval as materialized (
    select r.id route_id,r.profile_id,r.priority,r.fallback_on,
           coalesce((pc->>'enabled')::boolean,false) provider_enabled,
           lower(coalesce(pc->>'provider_key','')) provider_key,
           lower(coalesce(pc->>'adapter_type','direct_http')) adapter_type,
           lower(coalesce(pc->>'auth_scheme','none')) auth_scheme,
           nullif(pc->>'secret','') secret,
           coalesce(pc#>>'{budget_status,allowed}','true') budget_allowed,
           nullif(pc->>'estimated_request_cost_usd','') estimated_cost,
           pc->>'base_url' base_url,
           (
             coalesce((pc->>'enabled')::boolean,false)=true
             and lower(coalesce(pc->>'provider_key',''))<>'parsebot'
             and (lower(coalesce(pc->>'auth_scheme','none'))='none' or nullif(pc->>'secret','') is not null)
             and coalesce(pc#>>'{budget_status,allowed}','true')<>'false'
             and (lower(coalesce(pc->>'provider_key',''))='direct-http' or nullif(pc->>'estimated_request_cost_usd','') is not null)
           ) pre_attempt_eligible,
           (
             lower(coalesce(pc->>'adapter_type','direct_http'))='direct_http'
             or security.scheduler_workflow_https_host_v1(pc->>'base_url') is not null
           ) base_url_usable
    from pipeline.layer2_profile_provider_routes r
    cross join lateral public.layer2_provider_runtime_config(r.acquisition_provider_id) pc
    where r.enabled=true
  ), candidates as (
    select e.*
    from route_eval e
    where e.pre_attempt_eligible and e.base_url_usable
  )
  select count(*)::integer
  from scoped_profiles sp
  where not exists (
    select 1
    from candidates c
    where c.profile_id=sp.profile_id
      and not exists (
        select 1
        from route_eval b
        where b.profile_id=c.profile_id
          and b.route_id<>c.route_id
          and b.priority<=c.priority
          and b.pre_attempt_eligible
          and not b.base_url_usable
          and not (coalesce(b.fallback_on,'[]'::jsonb) ? 'blocked')
      )
  )
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
  -- Generic async discovery is blocked separately and truthfully in Preview. This
  -- function now reports only deterministic queueable URL/allowlist mismatches.
  select count(*)::integer
  from public.layer2_scope_courses(upper(p_country_code),lower(p_scope_type),p_scope_id) sc
  where sc.source_url is not null
    and not security.scheduler_workflow_queueable_url_allowed_v1(sc.profile_id,sc.source_url)
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
  v_result jsonb; v_snapshot jsonb; v_confirm jsonb; v_preview_id uuid;
  v_invalid_profiles integer:=0; v_policy_gaps integer:=0; v_oversized_profiles integer:=0; v_route_gaps integer:=0; v_discovery_config_gaps integer:=0; v_unsupported_discovery integer:=0;
  v_profile_ids uuid[]:='{}'::uuid[];
begin
  if v_actor is null or security.current_role_rank() < 4 then raise exception 'pipeline operator role required' using errcode='42501'; end if;
  if v_workflow <> 'course_facts_l2' then raise exception 'workflow is not executable from Scheduled Tasks' using errcode='22023'; end if;
  if upper(coalesce(trim(p_country_code),'')) <> 'AU' then raise exception 'only AU Layer 2 Course Facts is currently authorised for this builder' using errcode='22023'; end if;
  if v_scope not in ('country','state','university') then raise exception 'unsupported scope type' using errcode='22023'; end if;
  if v_scope in ('state','university') and p_scope_id is null then raise exception 'scope id required' using errcode='22023'; end if;
  if v_scope='country' and p_scope_id is not null then raise exception 'country scope must not include a scope id' using errcode='22023'; end if;

  v_snapshot:=security.scheduler_workflow_scope_snapshot_v2(upper(p_country_code),v_scope,p_scope_id);
  select coalesce(array_agg((x)::uuid order by (x)::uuid),'{}'::uuid[]) into v_profile_ids from jsonb_array_elements_text(coalesce(v_snapshot->'profile_ids','[]'::jsonb)) x;
  v_unsupported_discovery:=coalesce((v_snapshot->>'needs_discovery_count')::integer,0);
  v_result:=coalesce(public.layer2_operator_scope_service(v_actor,'preview',upper(p_country_code),v_scope,p_scope_id),'{}'::jsonb)
    ||jsonb_build_object('queueable_count',coalesce((v_snapshot->>'queueable_count')::integer,0),'needs_discovery_count',v_unsupported_discovery,'scoped_course_count',coalesce((v_snapshot->>'scoped_course_count')::integer,0),'scope_fingerprint',v_snapshot->>'scope_fingerprint');

  select count(distinct sc.profile_id)::integer into v_invalid_profiles from public.layer2_scope_courses(upper(p_country_code),v_scope,p_scope_id) sc join pipeline.layer2_source_profiles lp on lp.id=sc.profile_id left join pipeline.layer2_source_profile_versions pv on pv.id=lp.current_version_id where lp.current_version_id is null or pv.id is null or pv.validation_status<>'valid';
  v_policy_gaps:=security.scheduler_workflow_execution_policy_gap_count_v1(upper(p_country_code),v_scope,p_scope_id);
  v_oversized_profiles:=security.scheduler_workflow_oversized_profile_count_v1(upper(p_country_code),v_scope,p_scope_id);
  v_route_gaps:=security.scheduler_workflow_route_gap_count_v1(upper(p_country_code),v_scope,p_scope_id);
  v_discovery_config_gaps:=security.scheduler_workflow_discovery_config_gap_count_v1(upper(p_country_code),v_scope,p_scope_id);
  v_confirm:=security.scheduler_workflow_scope_snapshot_v2(upper(p_country_code),v_scope,p_scope_id);
  if coalesce(v_confirm->>'scope_fingerprint','')<>coalesce(v_snapshot->>'scope_fingerprint','') or coalesce(v_confirm->'profile_ids','[]'::jsonb)<>coalesce(v_snapshot->'profile_ids','[]'::jsonb) then raise exception 'Layer 2 scope changed while preview was being constructed; preview again' using errcode='40001'; end if;

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
    'unsupported_discovery_count',v_unsupported_discovery,
    'missing_discovery_config_count',v_discovery_config_gaps,
    'profile_ids',to_jsonb(v_profile_ids)
  );
  if v_invalid_profiles>0 then return v_result||jsonb_build_object('executable',false,'execution_block_reason','One or more Layer 2 Course Facts profiles in this scope do not have a valid current profile version. Requalify the affected profile before dispatch.','preview_token',null,'preview_expires_at',null); end if;
  if v_policy_gaps>0 then return v_result||jsonb_build_object('executable',false,'execution_block_reason','One or more Layer 2 profiles in this scope do not have the execution policy required by deterministic Layer 2 processing. Configure the execution policy before acquisition or dispatch.','preview_token',null,'preview_expires_at',null); end if;
  if v_oversized_profiles>0 then return v_result||jsonb_build_object('executable',false,'execution_block_reason','One or more Layer 2 profiles in this scope exceed the current 1,000-course dispatch contract. Narrow the target scope before dispatch.','preview_token',null,'preview_expires_at',null); end if;
  if v_unsupported_discovery>0 then return v_result||jsonb_build_object('executable',false,'execution_block_reason','This scope requires asynchronous Course Facts discovery, which Scheduled Tasks intentionally does not execute until Preview-bound discovery inputs are carried and verified through the worker and continuations. Use a fully queueable scope or the governed Layer 2 discovery workflow.','preview_token',null,'preview_expires_at',null); end if;
  if v_route_gaps>0 then return v_result||jsonb_build_object('executable',false,'execution_block_reason','One or more Layer 2 profiles in this scope have no runtime-usable acquisition route under the configured route order and fallback policy. Correct the blocking route/fallback or restore a usable governed route before dispatch.','preview_token',null,'preview_expires_at',null); end if;
  if v_discovery_config_gaps>0 then return v_result||jsonb_build_object('executable',false,'execution_block_reason','One or more queueable Course Facts URLs are not accepted by the current profile allowlist using the same literal URL-reference semantics as the acquisition worker. Correct the governed profile allowlist or source URL before dispatch.','preview_token',null,'preview_expires_at',null); end if;
  if cardinality(v_profile_ids)=0 or coalesce((v_snapshot->>'queueable_count')::integer,0)<=0 then return v_result||jsonb_build_object('executable',false,'execution_block_reason','No executable deterministic Layer 2 work is available for this governed scope. Choose a fully queueable qualified Course Facts scope.','preview_token',null,'preview_expires_at',null); end if;
  v_result:=v_result||jsonb_build_object('executable',true);
  insert into pipeline.jobs(job_type,domain,status,requested_by,started_at,completed_at,payload,result) values('scheduler_workflow_preview','course_facts','completed',v_actor,now(),now(),jsonb_build_object('workflow_key',v_workflow,'country_code',upper(p_country_code),'scope_type',v_scope,'scope_id',p_scope_id,'processing_mode','acquisition_only','change_control_ref','CF-CHG-20260910-093','expires_at',now()+interval '15 minutes'),v_result) returning id into v_preview_id;
  return v_result||jsonb_build_object('preview_token',v_preview_id,'preview_expires_at',now()+interval '15 minutes');
end
$function$;

revoke all on function security.scheduler_workflow_preview_v1_browser_bridge(text,text,text,uuid) from public,anon;
grant execute on function security.scheduler_workflow_preview_v1_browser_bridge(text,text,text,uuid) to authenticated;

commit;
