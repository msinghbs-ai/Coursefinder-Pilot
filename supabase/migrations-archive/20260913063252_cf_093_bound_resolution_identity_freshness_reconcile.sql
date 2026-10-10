begin;

-- CF-CHG-20260910-093 forward-only reconciliation.
-- 1) Bound discovery may only treat a newly selected candidate as resolved when
--    its provider attempt/job carries the same exact scheduler Preview token.
-- 2) Terminal-negative freshness is valid only while the Evidence-evaluated
--    course code/title still match current Layer 1 identity.

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
as $$
declare
  v_ctx jsonb;
  v_provider uuid;
  v_courses jsonb;
  v_binding pipeline.scheduler_workflow_async_bindings%rowtype;
  v_requested uuid[];
  v_snapshot jsonb;
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
  select s.provider_id into v_provider from pipeline.sources s where s.id=(v_ctx->>'source_id')::uuid;
  if v_provider is null then raise exception 'profile source is not bound to a canonical provider' using errcode='22023'; end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.canonical_title,x.id),'[]'::jsonb) into v_courses
  from (
    select c.id,c.canonical_title,c.display_title,c.course_code
    from catalogue.courses c
    where c.provider_id=v_provider and c.id=any(v_requested)
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
    order by c.canonical_title,c.id
    limit least(greatest(coalesce(p_limit,50),1),50)
  ) x;

  return jsonb_build_object(
    'runtime',v_ctx,'canonical_provider_id',v_provider,'courses',v_courses,
    'scheduler_preview_token',v_binding.preview_token,'scheduler_bound_retry',true,
    'identity_revalidated',true,'historical_dispositions_preserved',true
  );
end $$;

revoke all on function public.layer2_discovery_context_scope_bound_v1(uuid,uuid,uuid,uuid[],integer) from public,anon,authenticated;
grant execute on function public.layer2_discovery_context_scope_bound_v1(uuid,uuid,uuid,uuid[],integer) to service_role;

create or replace function security.scheduler_workflow_scope_state_v1(
  p_country_code text,
  p_scope_type text,
  p_scope_id uuid default null
)
returns table(
  profile_id uuid,
  profile_key text,
  provider_name text,
  provider_id uuid,
  course_id uuid,
  source_url text,
  current_version_id uuid,
  configuration jsonb,
  course_code text,
  canonical_title text,
  display_title text,
  recent_terminal_negative boolean
)
language sql
stable
security definer
set search_path=''
as $function$
with scoped_base as materialized (
  select sc.profile_id,sc.profile_key,sc.provider_name,sc.provider_id,sc.course_id,sc.source_url,
         lp.current_version_id,pv.configuration,c.course_code,c.canonical_title,c.display_title,
         case when coalesce(pv.configuration->>'freshness_sla_hours','') ~ '^[0-9]+$'
              then (pv.configuration->>'freshness_sla_hours')::integer else null end as freshness_sla_hours
  from public.layer2_scope_courses(upper(p_country_code),lower(p_scope_type),p_scope_id) sc
  join pipeline.layer2_source_profiles lp on lp.id=sc.profile_id
  join pipeline.layer2_source_profile_versions pv on pv.id=lp.current_version_id
  join catalogue.courses c on c.id=sc.course_id
  where lp.domain='course_facts' and lp.enabled and not lp.paused
), disposition as materialized (
  select s.profile_id,s.course_id,
         max(d.created_at) filter (
           where d.selected=false
             and coalesce(trim(d.match_basis->>'expected_course_code'),'')=coalesce(trim(s.course_code),'')
             and lower(regexp_replace(coalesce(d.match_basis->>'expected_title',''),'\s+',' ','g'))
                 =lower(regexp_replace(coalesce(s.canonical_title,s.display_title,''),'\s+',' ','g'))
             and (
               d.status in ('ambiguous','identity_mismatch') or (
                 d.status='current_page_not_found'
                 and coalesce(d.match_basis->>'worker_version','')='layer2-scope-discover-scheduled-v1.3.10'
                 and (
                   coalesce((d.match_basis->>'zero_result_marker_qualified')::boolean,false)=true
                   or coalesce((d.match_basis->>'required_prefix_link_count')::integer,0)>0
                 )
               )
             )
         ) as terminal_at,
         max(d.created_at) filter (where d.selected=true and nullif(d.discovered_url,'') is not null) as selected_at
  from scoped_base s
  left join pipeline.layer2_course_discovery_candidates d
    on d.course_id=s.course_id and d.source_profile_version_id=s.current_version_id
  group by s.profile_id,s.course_id
)
select s.profile_id,s.profile_key,s.provider_name,s.provider_id,s.course_id,s.source_url,
       s.current_version_id,s.configuration,s.course_code,s.canonical_title,s.display_title,
       coalesce(s.freshness_sla_hours is not null and s.freshness_sla_hours>0
         and d.terminal_at is not null
         and d.terminal_at>=now()-make_interval(hours=>s.freshness_sla_hours)
         and (d.selected_at is null or d.selected_at<d.terminal_at),false) as recent_terminal_negative
from scoped_base s
join disposition d using(profile_id,course_id)
$function$;

revoke all on function security.scheduler_workflow_scope_state_v1(text,text,uuid) from public,anon,authenticated;
grant execute on function security.scheduler_workflow_scope_state_v1(text,text,uuid) to service_role;

commit;
