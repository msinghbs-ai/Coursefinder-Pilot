-- CF-CHG-20260915-246 — M2.4.6 Production Operations Contract / G1.
-- Active Layer 2 wave requests become idempotent by scope + route.
-- No scheduler frequency/concurrency/provider/authority/publication change.

create unique index if not exists layer2_scope_wave_requests_active_identity_uq
on pipeline.layer2_scope_wave_requests(
  upper(country_code),
  lower(scope_type),
  coalesce(scope_id,'00000000-0000-0000-0000-000000000000'::uuid),
  lower(route_mode)
)
where status in ('planned','scheduled','running','wave1_dispatched');

create or replace function public.layer2_wave_scope_service(
  p_actor uuid,
  p_action text,
  p_country_code text,
  p_scope_type text default 'country',
  p_scope_id uuid default null,
  p_wave_size integer default 500,
  p_schedule_remaining boolean default true,
  p_route_mode text default 'managed',
  p_request_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','pipeline','catalogue','ref','security'
as $$
declare
  v_rank integer:=0;
  v_mode text:=lower(coalesce(p_route_mode,'managed'));
  v_requested integer:=greatest(coalesce(p_wave_size,500),1);
  v_accepted integer:=least(v_requested,1000);
  v_request uuid;
  v_total integer:=0;
  v_missing integer:=0;
  v_firecrawl uuid;
  v_result jsonb;
  v_scope text:=lower(coalesce(p_scope_type,'country'));
  v_existing pipeline.layer2_scope_wave_requests%rowtype;
begin
  if current_user not in('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;

  select coalesce(max(r.rank),0) into v_rank
  from security.user_roles ur
  join security.roles r on r.code=ur.role_code
  where ur.user_id=p_actor
    and (ur.expires_at is null or ur.expires_at>now())
    and r.status='active';
  if v_rank<4 then
    raise exception 'pipeline_operator role required' using errcode='42501';
  end if;

  if v_mode not in('managed','scraper_first') then
    raise exception 'invalid route mode' using errcode='22023';
  end if;
  if v_scope not in('country','state','university') then
    raise exception 'invalid scope type' using errcode='22023';
  end if;
  if v_scope in('state','university') and p_scope_id is null then
    raise exception 'scope id required' using errcode='22023';
  end if;
  if upper(p_country_code)='NZ' then
    raise exception 'NZ Layer 2 Course enrichment is deferred' using errcode='22023';
  end if;

  if p_action='preview' then
    select count(*) filter(where source_url is not null),count(*) filter(where source_url is null)
      into v_total,v_missing
    from public.layer2_scope_courses(p_country_code,v_scope,p_scope_id);
    return jsonb_build_object(
      'ok',true,
      'queueable_courses',v_total,
      'missing_url_courses',v_missing,
      'requested_wave_size',v_requested,
      'accepted_wave_size',v_accepted,
      'platform_wave_ceiling',1000,
      'wave_1',least(v_total,v_accepted),
      'remaining_after_wave_1',greatest(v_total-v_accepted,0),
      'estimated_remaining_waves',case when v_total<=v_accepted then 0 else ceil((v_total-v_accepted)::numeric/v_accepted)::integer end,
      'schedule_remaining',p_schedule_remaining,
      'route_mode',v_mode,
      'route_note',case when v_mode='scraper_first'
        then 'Firecrawl is explicitly selected where enabled; API/provider ceilings still apply.'
        else 'Managed route: Direct HTTP → Firecrawl → governed fallback.' end
    );
  end if;

  if p_action='continue' then
    if p_request_id is null then
      raise exception 'request id required' using errcode='22023';
    end if;
    return security.layer2_wave_dispatch_request(p_request_id);
  end if;

  if p_action<>'start' then
    raise exception 'unsupported action' using errcode='22023';
  end if;

  -- Serialize starts for the same governed scope/route so two concurrent operator
  -- actions cannot both create an active request before either becomes visible.
  perform pg_advisory_xact_lock(
    hashtextextended(
      upper(coalesce(p_country_code,''))||'|'||v_scope||'|'||coalesce(p_scope_id::text,'country')||'|'||v_mode,
      246
    )
  );

  select * into v_existing
  from pipeline.layer2_scope_wave_requests
  where upper(country_code)=upper(p_country_code)
    and lower(scope_type)=v_scope
    and scope_id is not distinct from p_scope_id
    and lower(route_mode)=v_mode
    and status in('planned','scheduled','running','wave1_dispatched')
  order by created_at asc
  limit 1;

  if found then
    return jsonb_build_object(
      'ok',true,
      'status','active_wave_reused',
      'request_reused',true,
      'request_id',v_existing.id,
      'country_code',v_existing.country_code,
      'scope_type',v_existing.scope_type,
      'scope_id',v_existing.scope_id,
      'route_mode',v_existing.route_mode,
      'requested_wave_size',v_existing.requested_wave_size,
      'accepted_wave_size',v_existing.accepted_wave_size,
      'schedule_remaining',v_existing.schedule_remaining,
      'request_status',v_existing.status,
      'dispatched_items',v_existing.dispatched_items,
      'completed_items',v_existing.completed_items,
      'failed_items',v_existing.failed_items,
      'next_wave_not_before',v_existing.next_wave_not_before,
      'change_control_ref','CF-CHG-20260915-246'
    );
  end if;

  if v_mode='scraper_first' then
    select id into v_firecrawl
    from pipeline.layer2_acquisition_providers
    where provider_key='firecrawl' and enabled
    limit 1;
    if v_firecrawl is null then
      raise exception 'Firecrawl acquisition provider is not enabled' using errcode='22023';
    end if;
  end if;

  insert into pipeline.layer2_scope_wave_requests(
    requested_by,country_code,scope_type,scope_id,route_mode,
    requested_wave_size,accepted_wave_size,schedule_remaining,status,change_control_ref,metadata
  ) values(
    p_actor,upper(p_country_code),v_scope,p_scope_id,v_mode,
    v_requested,v_accepted,coalesce(p_schedule_remaining,true),'planned','CF-CHG-20260915-246',
    jsonb_build_object('platform_wave_ceiling',1000,'requested_route',v_mode,'idempotent_request_identity',true)
  ) returning id into v_request;

  insert into pipeline.layer2_scope_wave_items(
    request_id,ordinal,profile_id,course_id,source_url,selected_provider_id,status,blocker
  )
  select v_request,row_number() over(order by sc.provider_name,sc.profile_id,sc.course_id)::integer,
         sc.profile_id,sc.course_id,sc.source_url,
         case when v_mode='scraper_first' and exists(
           select 1 from pipeline.layer2_profile_provider_routes pr
           where pr.profile_id=sc.profile_id
             and pr.acquisition_provider_id=v_firecrawl
             and pr.enabled
         ) then v_firecrawl else null end,
         case when sc.source_url is null then 'missing_url'
              when v_mode='scraper_first' and not exists(
                select 1 from pipeline.layer2_profile_provider_routes pr
                where pr.profile_id=sc.profile_id
                  and pr.acquisition_provider_id=v_firecrawl
                  and pr.enabled
              ) then 'blocked'
              else 'pending' end,
         case when sc.source_url is null then 'course_url_requires_discovery'
              when v_mode='scraper_first' and not exists(
                select 1 from pipeline.layer2_profile_provider_routes pr
                where pr.profile_id=sc.profile_id
                  and pr.acquisition_provider_id=v_firecrawl
                  and pr.enabled
              ) then 'firecrawl_not_enabled_for_profile'
              else null end
  from public.layer2_scope_courses(p_country_code,v_scope,p_scope_id) sc;

  select count(*) filter(where status='pending'),count(*) filter(where status='missing_url')
    into v_total,v_missing
  from pipeline.layer2_scope_wave_items
  where request_id=v_request;

  update pipeline.layer2_scope_wave_requests
  set total_items=v_total,
      missing_url_items=v_missing,
      metadata=metadata||jsonb_build_object(
        'blocked_items',(
          select count(*)
          from pipeline.layer2_scope_wave_items
          where request_id=v_request and status='blocked'
        )
      ),
      updated_at=now()
  where id=v_request;

  v_result:=security.layer2_wave_dispatch_request(v_request);
  return v_result||jsonb_build_object(
    'status','wave_started',
    'request_reused',false,
    'queueable_courses',v_total,
    'missing_url_courses',v_missing,
    'requested_wave_size',v_requested,
    'accepted_wave_size',v_accepted,
    'platform_wave_ceiling',1000,
    'change_control_ref','CF-CHG-20260915-246'
  );
end
$$;

revoke all on function public.layer2_wave_scope_service(uuid,text,text,text,uuid,integer,boolean,text,uuid) from public,anon,authenticated;
grant execute on function public.layer2_wave_scope_service(uuid,text,text,text,uuid,integer,boolean,text,uuid) to service_role;
