begin;

-- CF-093 forward-only corrective pass. Keep generic discovery-backed Scheduled Tasks
-- fail-closed until the asynchronous worker carries and verifies Preview-bound inputs.
-- Queueable deterministic Layer 2 remains supported.

create or replace function security.scheduler_workflow_https_host_v1(p_url text)
returns text
language plpgsql
immutable
security invoker
set search_path=''
as $function$
declare
  v_url text:=nullif(trim(coalesce(p_url,'')),'');
  v_match text[];
  v_port integer;
  v_parts text[];
  v_part text;
  v_octet integer;
  v_host text;
begin
  if v_url is null or v_url ~ '[[:space:]]' then return null; end if;
  v_match:=regexp_match(v_url,'^https://([A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?)(?::([0-9]{1,5}))?(?:[/?#].*)?$','i');
  if v_match is null then return null; end if;
  v_host:=lower(v_match[1]);
  if v_host is null or v_host ~ '\.\.' or v_host ~ '(^[.-]|[.-]$)' then return null; end if;

  -- WHATWG accepts several legacy numeric IPv4 spellings. The scheduler is deliberately
  -- stricter: any numeric/hex-like host must be exactly four canonical decimal octets.
  if v_host ~* '^(?:0x[0-9a-f]+|[0-9]+)(?:\.(?:0x[0-9a-f]+|[0-9]+))*$' then
    if v_host !~ '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' then return null; end if;
    v_parts:=regexp_split_to_array(v_host,'\.');
    if coalesce(array_length(v_parts,1),0)<>4 then return null; end if;
    foreach v_part in array v_parts loop
      if v_part !~ '^(0|[1-9][0-9]{0,2})$' then return null; end if;
      begin v_octet:=v_part::integer; exception when others then return null; end;
      if v_octet<0 or v_octet>255 then return null; end if;
    end loop;
  end if;

  if v_match[2] is not null then
    begin v_port:=v_match[2]::integer; exception when others then return null; end;
    if v_port<0 or v_port>65535 then return null; end if;
  end if;
  return v_host;
end
$function$;
revoke all on function security.scheduler_workflow_https_host_v1(text) from public,anon,authenticated;

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
      cross join lateral public.layer2_provider_runtime_config(r.acquisition_provider_id) pc
      where r.profile_id=sc.profile_id
        and r.enabled=true
        and coalesce((pc->>'enabled')::boolean,false)=true
        and lower(coalesce(pc->>'provider_key',''))<>'parsebot'
        and (lower(coalesce(pc->>'auth_scheme','none'))='none' or nullif(pc->>'secret','') is not null)
        and coalesce(pc#>>'{budget_status,allowed}','true')<>'false'
        and (lower(coalesce(pc->>'provider_key',''))='direct-http' or nullif(pc->>'estimated_request_cost_usd','') is not null)
        and (
          lower(coalesce(pc->>'adapter_type','direct_http'))='direct_http'
          or security.scheduler_workflow_https_host_v1(pc->>'base_url') is not null
        )
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
  with scoped as materialized (
    select sc.profile_id,sc.course_id,sc.source_url
    from public.layer2_scope_courses(upper(p_country_code),lower(p_scope_type),p_scope_id) sc
  ),
  -- Generic Scheduled Tasks discovery is intentionally fail-closed. The asynchronous
  -- worker currently resolves live profile/course inputs after Preview consumption, so
  -- it cannot yet prove execution against the exact Preview-bound target set.
  unsupported_discovery as (
    select distinct s.profile_id::text||':preview_bound_async_discovery_not_supported' gap_key
    from scoped s
    where s.source_url is null
  ),
  invalid_queueable as (
    select s.profile_id::text||':'||s.course_id::text gap_key
    from scoped s
    where s.source_url is not null
      and not security.scheduler_workflow_queueable_url_allowed_v1(s.profile_id,s.source_url)
  )
  select count(*)::integer from (
    select gap_key from unsupported_discovery
    union all
    select gap_key from invalid_queueable
  ) gaps
$function$;
revoke all on function security.scheduler_workflow_discovery_config_gap_count_v1(text,text,uuid) from public,anon,authenticated;

create or replace function security.scheduler_workflow_scope_snapshot_v2(
  p_country_code text,
  p_scope_type text,
  p_scope_id uuid default null
) returns jsonb
language sql
stable
security definer
set search_path=''
as $function$
  with scoped_base as materialized (
    select sc.profile_id,sc.course_id,sc.source_url,lp.current_version_id,pv.configuration,
           c.course_code,c.canonical_title,c.display_title
    from public.layer2_scope_courses(upper(p_country_code),lower(p_scope_type),p_scope_id) sc
    join pipeline.layer2_source_profiles lp on lp.id=sc.profile_id
    join pipeline.layer2_source_profile_versions pv on pv.id=lp.current_version_id
    join catalogue.courses c on c.id=sc.course_id
  ), scoped as materialized (
    select profile_id,course_id,source_url,current_version_id,course_code,canonical_title,display_title,
      case when source_url is null then
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
           count(*) filter (where source_url is null)::integer needs_discovery_count,
           count(*)::integer scoped_course_count,
           md5(coalesce(jsonb_agg(
             jsonb_build_array(
               profile_id::text,
               current_version_id::text,
               course_id::text,
               source_url,
               discovery_target,
               case when source_url is null then course_code else null end,
               case when source_url is null then canonical_title else null end,
               case when source_url is null then display_title else null end
             ) order by profile_id,current_version_id,course_id,coalesce(source_url,''),coalesce(discovery_target,''),coalesce(course_code,''),coalesce(canonical_title,''),coalesce(display_title,'')
           ),'[]'::jsonb)::text) scope_fingerprint
    from scoped
  )
  select jsonb_build_object(
    'profile_ids',to_jsonb(profile_ids.ids),
    'queueable_count',counts.queueable_count,
    'needs_discovery_count',counts.needs_discovery_count,
    'scoped_course_count',counts.scoped_course_count,
    'scope_fingerprint',counts.scope_fingerprint
  )
  from profile_ids cross join counts
$function$;
revoke all on function security.scheduler_workflow_scope_snapshot_v2(text,text,uuid) from public,anon,authenticated;

commit;
