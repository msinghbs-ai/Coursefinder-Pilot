create or replace function security.scheduler_workflow_route_gap_count_v1(p_country_code text,p_scope_type text,p_scope_id uuid default null)
returns integer
language sql
stable
security definer
set search_path to ''
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
    from scoped_profiles sp
    join pipeline.layer2_profile_provider_routes r on r.profile_id=sp.profile_id and r.enabled=true
    cross join lateral public.layer2_provider_runtime_config(r.acquisition_provider_id) pc
  ), candidates as (
    select e.* from route_eval e where e.pre_attempt_eligible and e.base_url_usable
  )
  select count(*)::integer
  from scoped_profiles sp
  where not exists (
    select 1 from candidates c
    where c.profile_id=sp.profile_id
      and not exists (
        select 1 from route_eval b
        where b.profile_id=c.profile_id and b.route_id<>c.route_id and b.priority<=c.priority
          and b.pre_attempt_eligible and not b.base_url_usable
          and not (coalesce(b.fallback_on,'[]'::jsonb) ? 'blocked')
      )
  )
$function$;