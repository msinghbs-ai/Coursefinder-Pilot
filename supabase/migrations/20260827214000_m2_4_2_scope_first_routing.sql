-- M2.4.2 A9 — scope-first sync, ordered routing and bounded large-batch execution.
-- Preserves Layer 1 identity/authority and keeps privileged helpers service-only.

begin;

-- AU Course acquisition order: Direct HTTP -> Firecrawl -> remaining enabled fallbacks.
update pipeline.layer2_profile_provider_routes r
set priority = 1000 + r.priority
from pipeline.layer2_source_profiles p
where r.profile_id=p.id
  and p.domain='course_facts'
  and p.enabled and not p.paused;

update pipeline.layer2_profile_provider_routes r
set priority = case ap.provider_key
  when 'direct-http' then 10
  when 'firecrawl' then 20
  when 'scrape-do' then 30
  when 'scraperapi' then 40
  when 'zenrows' then 50
  else r.priority
end
from pipeline.layer2_acquisition_providers ap,
     pipeline.layer2_source_profiles p
where r.acquisition_provider_id=ap.id
  and r.profile_id=p.id
  and p.domain='course_facts'
  and p.enabled and not p.paused;

create or replace function public.layer2_run_batch_create(
  p_profile_id uuid,
  p_trigger_type text,
  p_requested_by uuid,
  p_items jsonb
) returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog','pipeline'
as $$
declare
  v_profile pipeline.layer2_source_profiles%rowtype;
  v_policy pipeline.layer2_execution_policies%rowtype;
  v_batch uuid:=gen_random_uuid();
  v_count integer;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  if p_trigger_type not in ('manual','schedule','trial','resume') then raise exception 'invalid trigger_type'; end if;
  if jsonb_typeof(p_items)<>'array' then raise exception 'items must be array'; end if;
  v_count:=jsonb_array_length(p_items);
  if v_count<1 or v_count>1000 then raise exception 'batch item count must be 1..1000'; end if;

  select * into v_profile from pipeline.layer2_source_profiles where id=p_profile_id;
  if not found then raise exception 'profile not found'; end if;
  if not v_profile.enabled or v_profile.paused then raise exception 'profile not executable'; end if;
  if v_profile.current_version_id is null then raise exception 'profile has no current version'; end if;

  select * into v_policy from pipeline.layer2_execution_policies where profile_id=p_profile_id;
  if not found then raise exception 'execution policy missing'; end if;

  insert into pipeline.layer2_run_batches(
    id,profile_id,profile_version_id,trigger_type,status,requested_by,policy_snapshot,target_count
  ) values(
    v_batch,p_profile_id,v_profile.current_version_id,p_trigger_type,'queued',p_requested_by,
    jsonb_build_object(
      'schedule_mode',v_policy.schedule_mode,
      'batch_size',v_policy.batch_size,
      'routing_strategy',v_policy.routing_strategy,
      'max_paid_attempts_per_entity',v_policy.max_paid_attempts_per_entity,
      'max_vendor_units_per_entity',v_policy.max_vendor_units_per_entity,
      'max_cost_usd_per_entity',v_policy.max_cost_usd_per_entity,
      'auto_handoff_layer3',v_policy.auto_handoff_layer3,
      'stop_on_identity_mismatch',v_policy.stop_on_identity_mismatch,
      'max_concurrency',v_policy.max_concurrency
    ),
    v_count
  );

  insert into pipeline.layer2_run_items(id,batch_id,entity_type,entity_id,source_url,status,selected_provider_id)
  select gen_random_uuid(),v_batch,lower(x->>'entity_type'),(x->>'entity_id')::uuid,x->>'source_url','queued',nullif(x->>'provider_id','')::uuid
  from jsonb_array_elements(p_items) x;

  if exists(
    select 1 from pipeline.layer2_run_items
    where batch_id=v_batch
      and (entity_type not in ('course','scholarship') or entity_id is null or nullif(source_url,'') is null)
  ) then raise exception 'each item requires valid entity_type, entity_id and source_url'; end if;

  if exists(
    select 1
    from pipeline.layer2_run_items i
    left join pipeline.layer2_acquisition_providers p on p.id=i.selected_provider_id
    where i.batch_id=v_batch
      and i.selected_provider_id is not null
      and (p.id is null or not p.enabled)
  ) then raise exception 'selected provider invalid or disabled'; end if;

  return v_batch;
end $$;

revoke all on function public.layer2_run_batch_create(uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.layer2_run_batch_create(uuid,text,uuid,jsonb) to service_role;

create or replace function public.layer2_discovery_context_scope(
  p_profile_id uuid,
  p_course_ids uuid[] default null,
  p_limit integer default 50
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','pipeline','catalogue','public'
as $$
declare
  v_ctx jsonb;
  v_provider uuid;
  v_courses jsonb;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  select public.layer2_runtime_context(p_profile_id) into v_ctx;
  if v_ctx is null or v_ctx->>'domain'<>'course_facts' then raise exception 'course_facts profile required' using errcode='22023'; end if;

  select s.provider_id into v_provider
  from pipeline.sources s
  where s.id=(v_ctx->>'source_id')::uuid;
  if v_provider is null then raise exception 'profile source is not bound to a canonical provider' using errcode='22023'; end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.canonical_title,x.id),'[]'::jsonb)
  into v_courses
  from (
    select c.id,c.canonical_title,c.display_title,c.course_code
    from catalogue.courses c
    where c.provider_id=v_provider
      and (p_course_ids is null or c.id=any(p_course_ids))
      and not exists(
        select 1
        from pipeline.layer2_course_discovery_candidates dc
        where dc.course_id=c.id
          and dc.source_profile_version_id=(v_ctx->>'version_id')::uuid
          and dc.selected=true
      )
    order by c.canonical_title,c.id
    limit least(greatest(coalesce(p_limit,50),1),50)
  ) x;

  return jsonb_build_object('runtime',v_ctx,'canonical_provider_id',v_provider,'courses',v_courses);
end $$;

revoke all on function public.layer2_discovery_context_scope(uuid,uuid[],integer) from public,anon,authenticated;
grant execute on function public.layer2_discovery_context_scope(uuid,uuid[],integer) to service_role;

create or replace function security.layer2_discovery_scope_dispatch(
  p_profile_id uuid,
  p_course_ids uuid[],
  p_limit integer default 50
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','pipeline','security'
as $$
declare
  v_req bigint;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  if p_course_ids is null or coalesce(array_length(p_course_ids,1),0)=0 then raise exception 'course_ids required' using errcode='22023'; end if;
  if array_length(p_course_ids,1)>1000 then raise exception 'course_ids exceeds 1000' using errcode='22023'; end if;
  if not exists(
    select 1
    from pipeline.layer2_source_profiles
    where id=p_profile_id and domain='course_facts' and enabled and not paused
  ) then raise exception 'enabled course_facts profile required' using errcode='22023'; end if;

  v_req:=pipeline.svc_pilot_submit_nonce(
    'layer2-scope-discover-scheduled',
    jsonb_build_object(
      'profile_id',p_profile_id,
      'limit',least(greatest(coalesce(p_limit,50),1),50),
      'course_ids',to_jsonb(p_course_ids)
    )
  );

  return jsonb_build_object('ok',true,'profile_id',p_profile_id,'request_id',v_req,'course_count',array_length(p_course_ids,1));
end $$;

revoke all on function security.layer2_discovery_scope_dispatch(uuid,uuid[],integer) from public,anon,authenticated;
grant execute on function security.layer2_discovery_scope_dispatch(uuid,uuid[],integer) to service_role;

create or replace function public.layer2_scope_courses(
  p_country_code text,
  p_scope_type text,
  p_scope_id uuid default null
) returns table(
  profile_id uuid,
  profile_key text,
  provider_id uuid,
  provider_name text,
  course_id uuid,
  source_url text
)
language sql
stable
security definer
set search_path to 'pg_catalog','pipeline','catalogue','ref'
as $$
  select
    lp.id,
    lp.profile_key,
    cp.id,
    cp.canonical_name,
    c.id,
    coalesce(nullif(dc.discovered_url,''),nullif(c.course_url,'')) as source_url
  from pipeline.layer2_source_profiles lp
  join pipeline.sources s on s.id=lp.source_id
  join ref.countries country on country.id=s.country_id
  join catalogue.providers cp on cp.id=s.provider_id
  join catalogue.courses c on c.provider_id=cp.id
  left join lateral (
    select d.discovered_url
    from pipeline.layer2_course_discovery_candidates d
    where d.course_id=c.id
      and d.source_profile_version_id=lp.current_version_id
      and d.selected=true
      and nullif(d.discovered_url,'') is not null
    order by d.created_at desc
    limit 1
  ) dc on true
  where lp.domain='course_facts'
    and lp.enabled
    and not lp.paused
    and upper(country.iso_alpha2::text)=upper(p_country_code)
    and (
      lower(p_scope_type)='country'
      or (lower(p_scope_type)='university' and cp.id=p_scope_id)
      or (
        lower(p_scope_type)='state'
        and exists(
          select 1
          from catalogue.course_campuses ccx
          join catalogue.campuses cam on cam.id=ccx.campus_id
          where ccx.course_id=c.id
            and cam.subdivision_id=p_scope_id
        )
      )
    )
$$;

revoke all on function public.layer2_scope_courses(text,text,uuid) from public,anon,authenticated;
grant execute on function public.layer2_scope_courses(text,text,uuid) to service_role;

create or replace function public.layer2_scope_profile_batch_service(
  p_actor uuid,
  p_profile_id uuid,
  p_course_ids uuid[]
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','pipeline','catalogue','security'
as $$
declare
  v_rank integer:=0;
  v_active uuid;
  v_items jsonb;
  v_batch uuid;
  v_req bigint;
  v_count integer:=0;
  v_profile pipeline.layer2_source_profiles%rowtype;
  v_provider uuid;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  if p_actor is null then raise exception 'actor required' using errcode='42501'; end if;

  select coalesce(max(r.rank),0)
  into v_rank
  from security.user_roles ur
  join security.roles r on r.code=ur.role_code
  where ur.user_id=p_actor
    and (ur.expires_at is null or ur.expires_at>now())
    and r.status='active';
  if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;

  select *
  into v_profile
  from pipeline.layer2_source_profiles
  where id=p_profile_id
    and domain='course_facts'
    and enabled
    and not paused;
  if not found then raise exception 'profile not executable' using errcode='22023'; end if;

  select s.provider_id into v_provider
  from pipeline.sources s
  where s.id=v_profile.source_id;

  select b.id into v_active
  from pipeline.layer2_run_batches b
  where b.profile_id=p_profile_id
    and b.status in ('queued','running','partial')
  order by b.created_at desc
  limit 1;
  if v_active is not null then
    return jsonb_build_object('ok',true,'status','already_running','batch_id',v_active,'profile_id',p_profile_id);
  end if;

  with chosen as (
    select
      c.id,
      coalesce(
        (
          select d.discovered_url
          from pipeline.layer2_course_discovery_candidates d
          where d.course_id=c.id
            and d.source_profile_version_id=v_profile.current_version_id
            and d.selected
            and nullif(d.discovered_url,'') is not null
          order by d.created_at desc
          limit 1
        ),
        nullif(c.course_url,'')
      ) as url
    from catalogue.courses c
    where c.provider_id=v_provider
      and c.id=any(p_course_ids)
  )
  select
    jsonb_agg(jsonb_build_object('entity_type','course','entity_id',id,'source_url',url) order by id),
    count(*) filter(where url is not null)
  into v_items,v_count
  from chosen
  where url is not null;

  if v_items is null or v_count=0 then
    return jsonb_build_object(
      'ok',true,
      'status','nothing_queueable',
      'profile_id',p_profile_id,
      'requested_count',coalesce(array_length(p_course_ids,1),0)
    );
  end if;

  v_batch:=public.layer2_run_batch_create(p_profile_id,'manual',p_actor,v_items);
  v_req:=public.layer2_run_batch_dispatch(v_batch);

  return jsonb_build_object(
    'ok',true,
    'status','started',
    'profile_id',p_profile_id,
    'batch_id',v_batch,
    'dispatch_request_id',v_req,
    'target_count',v_count,
    'requested_count',array_length(p_course_ids,1)
  );
end $$;

revoke all on function public.layer2_scope_profile_batch_service(uuid,uuid,uuid[]) from public,anon,authenticated;
grant execute on function public.layer2_scope_profile_batch_service(uuid,uuid,uuid[]) to service_role;

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
as $$
declare
  v_req bigint;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  if p_course_ids is null or coalesce(array_length(p_course_ids,1),0)=0 then raise exception 'course_ids required' using errcode='22023'; end if;
  if array_length(p_course_ids,1)>1000 or coalesce(array_length(p_sync_course_ids,1),0)>1000 then raise exception 'course_ids exceeds 1000' using errcode='22023'; end if;
  if not exists(
    select 1
    from pipeline.layer2_source_profiles
    where id=p_profile_id and domain='course_facts' and enabled and not paused
  ) then raise exception 'enabled course_facts profile required' using errcode='22023'; end if;

  v_req:=pipeline.svc_pilot_submit_nonce(
    'layer2-scope-discover-scheduled',
    jsonb_build_object(
      'profile_id',p_profile_id,
      'limit',least(greatest(coalesce(p_limit,50),1),50),
      'course_ids',to_jsonb(p_course_ids),
      'auto_sync_actor',p_actor,
      'sync_course_ids',to_jsonb(coalesce(p_sync_course_ids,p_course_ids))
    )
  );

  return jsonb_build_object('ok',true,'profile_id',p_profile_id,'request_id',v_req,'course_count',array_length(p_course_ids,1));
end $$;

revoke all on function security.layer2_discovery_scope_dispatch_v2(uuid,uuid[],integer,uuid,uuid[]) from public,anon,authenticated;
grant execute on function security.layer2_discovery_scope_dispatch_v2(uuid,uuid[],integer,uuid,uuid[]) to service_role;

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
as $$
declare
  v_rank integer:=0;
  v_result jsonb;
  v_results jsonb:='[]'::jsonb;
  r record;
  v_all uuid[];
  v_missing uuid[];
  v_started jsonb;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  if p_actor is null then raise exception 'actor required' using errcode='42501'; end if;

  select coalesce(max(role.rank),0)
  into v_rank
  from security.user_roles ur
  join security.roles role on role.code=ur.role_code
  where ur.user_id=p_actor
    and (ur.expires_at is null or ur.expires_at>now())
    and role.status='active';
  if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;

  if p_action='options' then
    return jsonb_build_object(
      'countries',(
        select coalesce(jsonb_agg(distinct jsonb_build_object('code',c.iso_alpha2::text,'name',c.name)),'[]'::jsonb)
        from pipeline.layer2_source_profiles lp
        join pipeline.sources s on s.id=lp.source_id
        join ref.countries c on c.id=s.country_id
        where lp.domain='course_facts' and lp.enabled and not lp.paused
      ),
      'states',(
        select coalesce(jsonb_agg(x.obj order by x.name),'[]'::jsonb)
        from (
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
        ) x
      ),
      'universities',(
        select coalesce(jsonb_agg(x.obj order by x.name),'[]'::jsonb)
        from (
          select distinct cp.canonical_name name,jsonb_build_object('id',cp.id,'name',cp.canonical_name,'profile_id',lp.id) obj
          from pipeline.layer2_source_profiles lp
          join pipeline.sources s on s.id=lp.source_id
          join ref.countries co on co.id=s.country_id
          join catalogue.providers cp on cp.id=s.provider_id
          where lp.domain='course_facts' and lp.enabled and not lp.paused
            and (p_country_code is null or upper(co.iso_alpha2::text)=upper(p_country_code))
        ) x
      )
    );
  end if;

  if p_country_code is null then raise exception 'country required' using errcode='22023'; end if;
  if lower(p_scope_type) not in ('country','state','university') then raise exception 'invalid scope type' using errcode='22023'; end if;
  if lower(p_scope_type) in ('state','university') and p_scope_id is null then raise exception 'scope id required' using errcode='22023'; end if;

  if p_action='preview' then
    select jsonb_build_object(
      'ok',true,
      'country_code',upper(p_country_code),
      'scope_type',lower(p_scope_type),
      'scope_id',p_scope_id,
      'university_count',count(distinct sc.provider_id),
      'catalogue_count',count(distinct sc.course_id),
      'queueable_count',count(distinct sc.course_id) filter(where sc.source_url is not null),
      'needs_discovery_count',count(distinct sc.course_id) filter(where sc.source_url is null),
      'profiles',coalesce(jsonb_agg(distinct jsonb_build_object(
        'profile_id',sc.profile_id,
        'profile_key',sc.profile_key,
        'provider_id',sc.provider_id,
        'provider_name',sc.provider_name
      )),'[]'::jsonb),
      'active_run_count',(
        select count(*)
        from pipeline.layer2_run_batches b
        where b.profile_id in (
          select distinct q.profile_id
          from public.layer2_scope_courses(p_country_code,p_scope_type,p_scope_id) q
        )
        and b.status in ('queued','running','partial')
      )
    )
    into v_result
    from public.layer2_scope_courses(p_country_code,p_scope_type,p_scope_id) sc;

    return coalesce(
      v_result,
      jsonb_build_object(
        'ok',true,
        'country_code',upper(p_country_code),
        'scope_type',lower(p_scope_type),
        'catalogue_count',0,
        'queueable_count',0,
        'needs_discovery_count',0,
        'university_count',0,
        'profiles','[]'::jsonb
      )
    );
  end if;

  if p_action='start' then
    if upper(p_country_code)='NZ' then raise exception 'NZ Layer 2 Course enrichment is deferred' using errcode='22023'; end if;

    for r in
      select
        sc.profile_id,
        sc.profile_key,
        sc.provider_name,
        array_agg(sc.course_id order by sc.course_id) as all_ids,
        array_agg(sc.course_id order by sc.course_id) filter(where sc.source_url is null) as missing_ids,
        count(*) as total_count,
        count(*) filter(where sc.source_url is null) as missing_count
      from public.layer2_scope_courses(p_country_code,p_scope_type,p_scope_id) sc
      group by sc.profile_id,sc.profile_key,sc.provider_name
      order by sc.provider_name
    loop
      v_all:=r.all_ids;
      v_missing:=r.missing_ids;

      if r.missing_count>0 then
        v_started:=security.layer2_discovery_scope_dispatch_v2(r.profile_id,v_missing,50,p_actor,v_all);
        v_results:=v_results||jsonb_build_array(jsonb_build_object(
          'profile_id',r.profile_id,
          'profile_key',r.profile_key,
          'provider_name',r.provider_name,
          'status','discovery_started',
          'total_count',r.total_count,
          'needs_discovery',r.missing_count,
          'request_id',v_started->'request_id'
        ));
      else
        v_started:=public.layer2_scope_profile_batch_service(p_actor,r.profile_id,v_all);
        v_results:=v_results||jsonb_build_array(
          v_started||jsonb_build_object('profile_key',r.profile_key,'provider_name',r.provider_name)
        );
      end if;
    end loop;

    return jsonb_build_object(
      'ok',true,
      'status','scope_started',
      'country_code',upper(p_country_code),
      'scope_type',lower(p_scope_type),
      'scope_id',p_scope_id,
      'profiles',v_results
    );
  end if;

  raise exception 'unsupported action' using errcode='22023';
end $$;

revoke all on function public.layer2_operator_scope_service(uuid,text,text,text,uuid) from public,anon,authenticated;
grant execute on function public.layer2_operator_scope_service(uuid,text,text,text,uuid) to service_role;

commit;
