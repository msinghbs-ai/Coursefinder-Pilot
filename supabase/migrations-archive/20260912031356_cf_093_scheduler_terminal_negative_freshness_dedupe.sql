-- CF-CHG-20260910-093
-- Large-university scheduler correction.
-- Current-version governed terminal discovery outcomes remain authoritative for the
-- profile freshness SLA and are not immediately rediscovered. They remain non-queueable,
-- do not manufacture URLs, and do not authorise Layer 3, Search or Publication.
-- Recent-dispatch dedupe uses the already-governed execution-policy stale horizon,
-- never less than the accepted 10-minute floor.

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
  ), disposition as (
    select
      max(d.created_at) filter (
        where d.selected=false
          and d.status in ('current_page_not_found','ambiguous','identity_mismatch')
      ) as terminal_at,
      max(d.created_at) filter (
        where d.selected=true and nullif(d.discovered_url,'') is not null
      ) as selected_at
    from profile_ctx p
    left join pipeline.layer2_course_discovery_candidates d
      on d.course_id=p_course_id
     and d.source_profile_version_id=p.current_version_id
  )
  select coalesce((
    select p.freshness_sla_hours is not null
       and p.freshness_sla_hours>0
       and x.terminal_at is not null
       and x.terminal_at>=now()-make_interval(hours=>p.freshness_sla_hours)
       and (x.selected_at is null or x.selected_at<x.terminal_at)
    from profile_ctx p cross join disposition x
  ),false)
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
               profile_id::text,current_version_id::text,course_id::text,source_url,
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

-- Patch the current Preview bridge to bind only discovery courses that are not already
-- covered by fresh terminal Evidence, and expose the terminal-negative count.
do $migration$
declare
  v_reg regprocedure := 'security.scheduler_workflow_preview_v1_browser_bridge(text,text,text,uuid)'::regprocedure;
  v_def text;
begin
  select pg_get_functiondef(v_reg) into v_def;
  v_def:=replace(v_def,
    $$v_result:=coalesce(public.layer2_operator_scope_service(v_actor,'preview',upper(p_country_code),v_scope,p_scope_id),'{}'::jsonb)||jsonb_build_object('queueable_count',coalesce((v_snapshot->>'queueable_count')::integer,0),'needs_discovery_count',v_discovery_count,'scoped_course_count',coalesce((v_snapshot->>'scoped_course_count')::integer,0),'scope_fingerprint',v_snapshot->>'scope_fingerprint');$$,
    $$v_result:=coalesce(public.layer2_operator_scope_service(v_actor,'preview',upper(p_country_code),v_scope,p_scope_id),'{}'::jsonb)||jsonb_build_object('queueable_count',coalesce((v_snapshot->>'queueable_count')::integer,0),'needs_discovery_count',v_discovery_count,'terminal_negative_count',coalesce((v_snapshot->>'terminal_negative_count')::integer,0),'scoped_course_count',coalesce((v_snapshot->>'scoped_course_count')::integer,0),'scope_fingerprint',v_snapshot->>'scope_fingerprint');$$);
  v_def:=replace(v_def,
    $$array_agg(distinct sc.course_id order by sc.course_id) filter(where sc.source_url is null) discovery_ids$$,
    $$array_agg(distinct sc.course_id order by sc.course_id) filter(where sc.source_url is null and not security.scheduler_workflow_recent_terminal_negative_v1(sc.profile_id,sc.course_id)) discovery_ids$$);
  v_def:=replace(v_def,
    $$having count(*) filter(where sc.source_url is null)>0$$,
    $$having count(*) filter(where sc.source_url is null and not security.scheduler_workflow_recent_terminal_negative_v1(sc.profile_id,sc.course_id))>0$$);
  execute v_def;
end
$migration$;

-- Derive the recent-dispatch horizon from already-qualified execution policy rather than
-- inventing a new timeout. Later forward migrations refine exact-scope accounting and
-- completion anchoring without rewriting this applied state.
do $migration$
declare
  v_reg regprocedure := 'security.scheduler_workflow_run_now_v2_browser_bridge(uuid,text,text,text,uuid,text,text)'::regprocedure;
  v_def text;
  v_decl_old text := $$v_preview_fingerprint text; v_live_fingerprint text;$$;
  v_decl_new text := $$v_preview_fingerprint text; v_live_fingerprint text; v_dedupe_minutes integer:=10;$$;
  v_prior_old text := $$select * into v_prior from pipeline.jobs j where j.id<>p_preview_token and j.job_type='scheduler_workflow_preview' and nullif(j.payload->>'consumed_at','') is not null and (j.payload->>'consumed_at')::timestamptz>=now()-interval '10 minutes'$$;
  v_prior_new text := $$select greatest(10,coalesce(max(ep.stale_after_minutes),10))::integer into v_dedupe_minutes from pipeline.layer2_execution_policies ep where ep.profile_id=any(v_live_profiles) and ep.enabled;
 select * into v_prior from pipeline.jobs j where j.id<>p_preview_token and j.job_type='scheduler_workflow_preview' and nullif(j.payload->>'consumed_at','') is not null and (j.payload->>'consumed_at')::timestamptz>=now()-make_interval(mins=>v_dedupe_minutes)$$;
begin
  select pg_get_functiondef(v_reg) into v_def;
  if position(v_decl_old in v_def)=0 or position(v_prior_old in v_def)=0 then
    raise exception 'CF-093 terminal-negative freshness/dedupe patch target not found';
  end if;
  v_def:=replace(v_def,v_decl_old,v_decl_new);
  v_def:=replace(v_def,v_prior_old,v_prior_new);
  v_def:=replace(v_def,
    $$'deduplicated_against_preview',v_prior.id,'governance_reason',trim(p_reason)$$,
    $$'deduplicated_against_preview',v_prior.id,'dedupe_horizon_minutes',v_dedupe_minutes,'governance_reason',trim(p_reason)$$);
  v_def:=replace(v_def,
    $$'deduplicated_against_preview',v_prior.id,'result',v_prior.payload->'dispatch_result'$$,
    $$'deduplicated_against_preview',v_prior.id,'dedupe_horizon_minutes',v_dedupe_minutes,'result',v_prior.payload->'dispatch_result'$$);
  v_def:=replace(v_def,
    $$'governance_reason',trim(p_reason)),result=result||jsonb_build_object('dispatch_result'$$,
    $$'governance_reason',trim(p_reason),'dedupe_horizon_minutes',v_dedupe_minutes),result=result||jsonb_build_object('dispatch_result'$$);
  v_def:=replace(v_def,
    $$'idempotent_replay',false,'result',v_result$$,
    $$'idempotent_replay',false,'dedupe_horizon_minutes',v_dedupe_minutes,'result',v_result$$);
  execute v_def;
end
$migration$;
