
create table if not exists pipeline.layer2_scope_wave_requests(
  id uuid primary key default gen_random_uuid(),
  requested_by uuid not null,
  country_code text not null,
  scope_type text not null check(scope_type in('country','state','university')),
  scope_id uuid,
  route_mode text not null default 'managed' check(route_mode in('managed','scraper_first')),
  requested_wave_size integer not null check(requested_wave_size between 1 and 5000),
  accepted_wave_size integer not null check(accepted_wave_size between 1 and 1000),
  schedule_remaining boolean not null default true,
  status text not null default 'planned' check(status in('planned','running','scheduled','wave1_dispatched','completed','partial','blocked','cancelled')),
  total_items integer not null default 0,
  missing_url_items integer not null default 0,
  dispatched_items integer not null default 0,
  completed_items integer not null default 0,
  failed_items integer not null default 0,
  last_wave_at timestamptz,
  next_wave_not_before timestamptz,
  change_control_ref text not null default 'CF-CHG-20260830-048',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists pipeline.layer2_scope_wave_items(
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references pipeline.layer2_scope_wave_requests(id) on delete cascade,
  ordinal integer not null,
  profile_id uuid not null references pipeline.layer2_source_profiles(id),
  course_id uuid not null references catalogue.courses(id),
  source_url text,
  selected_provider_id uuid references pipeline.layer2_acquisition_providers(id),
  status text not null default 'pending' check(status in('pending','dispatched','completed','failed','blocked','missing_url')),
  batch_id uuid references pipeline.layer2_run_batches(id),
  blocker text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(request_id,course_id),
  unique(request_id,ordinal)
);
create index if not exists layer2_scope_wave_requests_status_idx on pipeline.layer2_scope_wave_requests(status,next_wave_not_before,created_at);
create index if not exists layer2_scope_wave_items_request_status_idx on pipeline.layer2_scope_wave_items(request_id,status,ordinal);
alter table pipeline.layer2_scope_wave_requests enable row level security;
alter table pipeline.layer2_scope_wave_items enable row level security;
revoke all on pipeline.layer2_scope_wave_requests,pipeline.layer2_scope_wave_items from public,anon,authenticated;

create or replace function security.layer2_wave_dispatch_request(p_request_id uuid)
returns jsonb language plpgsql security definer
set search_path='pg_catalog','security','pipeline','public'
as $$
declare
  v_req pipeline.layer2_scope_wave_requests%rowtype;
  v_remaining integer:=0;
  v_active integer:=0;
  v_dispatched integer:=0;
  v_batch uuid;
  v_items jsonb;
  r record;
begin
  select * into v_req from pipeline.layer2_scope_wave_requests where id=p_request_id for update;
  if not found then raise exception 'wave request not found' using errcode='22023'; end if;

  update pipeline.layer2_scope_wave_items wi
  set status=case when b.status in('completed','completed_with_fallout','partial') then 'completed' else 'failed' end,
      updated_at=now()
  from pipeline.layer2_run_batches b
  where wi.request_id=p_request_id and wi.batch_id=b.id and wi.status='dispatched'
    and b.status not in('queued','running');

  select count(*) into v_active
  from pipeline.layer2_scope_wave_items wi
  join pipeline.layer2_run_batches b on b.id=wi.batch_id
  where wi.request_id=p_request_id and wi.status='dispatched' and b.status in('queued','running','partial');
  if v_active>0 then
    return jsonb_build_object('ok',true,'status','active_wave_in_progress','request_id',p_request_id,'active_items',v_active);
  end if;

  for r in
    with selected as(
      select wi.* from pipeline.layer2_scope_wave_items wi
      where wi.request_id=p_request_id and wi.status='pending'
      order by wi.ordinal
      limit v_req.accepted_wave_size
    )
    select profile_id,
           jsonb_agg(jsonb_build_object(
             'entity_type','course','entity_id',course_id,'source_url',source_url,
             'provider_id',selected_provider_id
           ) order by ordinal) items,
           array_agg(id order by ordinal) item_ids
    from selected
    group by profile_id
  loop
    if exists(select 1 from pipeline.layer2_run_batches b where b.profile_id=r.profile_id and b.status in('queued','running','partial')) then
      continue;
    end if;
    v_batch:=public.layer2_run_batch_create(r.profile_id,'schedule',v_req.requested_by,r.items);
    perform public.layer2_run_batch_dispatch(v_batch);
    update pipeline.layer2_scope_wave_items
    set status='dispatched',batch_id=v_batch,updated_at=now()
    where id=any(r.item_ids);
    v_dispatched:=v_dispatched+coalesce(array_length(r.item_ids,1),0);
  end loop;

  select count(*) into v_remaining from pipeline.layer2_scope_wave_items where request_id=p_request_id and status='pending';
  update pipeline.layer2_scope_wave_requests q
  set dispatched_items=(select count(*) from pipeline.layer2_scope_wave_items where request_id=p_request_id and status in('dispatched','completed','failed')),
      completed_items=(select count(*) from pipeline.layer2_scope_wave_items where request_id=p_request_id and status='completed'),
      failed_items=(select count(*) from pipeline.layer2_scope_wave_items where request_id=p_request_id and status='failed'),
      last_wave_at=case when v_dispatched>0 then now() else q.last_wave_at end,
      next_wave_not_before=case when v_remaining>0 and q.schedule_remaining then now()+interval '15 minutes' else null end,
      status=case
        when v_remaining=0 and not exists(select 1 from pipeline.layer2_scope_wave_items wi join pipeline.layer2_run_batches b on b.id=wi.batch_id where wi.request_id=p_request_id and wi.status='dispatched' and b.status in('queued','running','partial')) then 'completed'
        when v_remaining>0 and q.schedule_remaining then 'scheduled'
        when v_remaining>0 then 'wave1_dispatched'
        else 'running' end,
      updated_at=now()
  where q.id=p_request_id;

  return jsonb_build_object(
    'ok',true,'request_id',p_request_id,'dispatched_now',v_dispatched,'remaining',v_remaining,
    'schedule_remaining',v_req.schedule_remaining,'accepted_wave_size',v_req.accepted_wave_size,
    'route_mode',v_req.route_mode
  );
end $$;
revoke all on function security.layer2_wave_dispatch_request(uuid) from public,anon,authenticated;
grant execute on function security.layer2_wave_dispatch_request(uuid) to service_role;

create or replace function public.layer2_wave_scope_service(
  p_actor uuid,p_action text,p_country_code text,p_scope_type text default 'country',p_scope_id uuid default null,
  p_wave_size integer default 500,p_schedule_remaining boolean default true,p_route_mode text default 'managed',
  p_request_id uuid default null
) returns jsonb
language plpgsql security definer
set search_path='pg_catalog','public','pipeline','catalogue','ref','security'
as $$
declare
  v_rank integer:=0; v_mode text:=lower(coalesce(p_route_mode,'managed')); v_requested integer:=greatest(coalesce(p_wave_size,500),1);
  v_accepted integer:=least(v_requested,1000); v_request uuid; v_total integer:=0; v_missing integer:=0; v_firecrawl uuid;
  v_result jsonb; v_scope text:=lower(coalesce(p_scope_type,'country'));
begin
  if current_user not in('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  select coalesce(max(r.rank),0) into v_rank from security.user_roles ur join security.roles r on r.code=ur.role_code
  where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and r.status='active';
  if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
  if v_mode not in('managed','scraper_first') then raise exception 'invalid route mode' using errcode='22023'; end if;
  if v_scope not in('country','state','university') then raise exception 'invalid scope type' using errcode='22023'; end if;
  if v_scope in('state','university') and p_scope_id is null then raise exception 'scope id required' using errcode='22023'; end if;
  if upper(p_country_code)='NZ' then raise exception 'NZ Layer 2 Course enrichment is deferred' using errcode='22023'; end if;

  if p_action='preview' then
    select count(*) filter(where source_url is not null),count(*) filter(where source_url is null)
    into v_total,v_missing from public.layer2_scope_courses(p_country_code,v_scope,p_scope_id);
    return jsonb_build_object(
      'ok',true,'queueable_courses',v_total,'missing_url_courses',v_missing,'requested_wave_size',v_requested,
      'accepted_wave_size',v_accepted,'platform_wave_ceiling',1000,'wave_1',least(v_total,v_accepted),
      'remaining_after_wave_1',greatest(v_total-v_accepted,0),
      'estimated_remaining_waves',case when v_total<=v_accepted then 0 else ceil((v_total-v_accepted)::numeric/v_accepted)::integer end,
      'schedule_remaining',p_schedule_remaining,'route_mode',v_mode,
      'route_note',case when v_mode='scraper_first' then 'Firecrawl is explicitly selected where enabled; API/provider ceilings still apply.' else 'Managed route: Direct HTTP → Firecrawl → governed fallback.' end
    );
  end if;

  if p_action='continue' then
    if p_request_id is null then raise exception 'request id required' using errcode='22023'; end if;
    return security.layer2_wave_dispatch_request(p_request_id);
  end if;

  if p_action<>'start' then raise exception 'unsupported action' using errcode='22023'; end if;

  if v_mode='scraper_first' then
    select id into v_firecrawl from pipeline.layer2_acquisition_providers where provider_key='firecrawl' and enabled limit 1;
    if v_firecrawl is null then raise exception 'Firecrawl acquisition provider is not enabled' using errcode='22023'; end if;
  end if;

  insert into pipeline.layer2_scope_wave_requests(
    requested_by,country_code,scope_type,scope_id,route_mode,requested_wave_size,accepted_wave_size,schedule_remaining,status,metadata
  ) values(
    p_actor,upper(p_country_code),v_scope,p_scope_id,v_mode,v_requested,v_accepted,coalesce(p_schedule_remaining,true),'planned',
    jsonb_build_object('platform_wave_ceiling',1000,'requested_route',v_mode)
  ) returning id into v_request;

  insert into pipeline.layer2_scope_wave_items(request_id,ordinal,profile_id,course_id,source_url,selected_provider_id,status,blocker)
  select v_request,row_number() over(order by sc.provider_name,sc.profile_id,sc.course_id)::integer,
         sc.profile_id,sc.course_id,sc.source_url,
         case when v_mode='scraper_first' and exists(
           select 1 from pipeline.layer2_profile_provider_routes pr
           where pr.profile_id=sc.profile_id and pr.acquisition_provider_id=v_firecrawl and pr.enabled
         ) then v_firecrawl else null end,
         case when sc.source_url is null then 'missing_url'
              when v_mode='scraper_first' and not exists(
                select 1 from pipeline.layer2_profile_provider_routes pr
                where pr.profile_id=sc.profile_id and pr.acquisition_provider_id=v_firecrawl and pr.enabled
              ) then 'blocked' else 'pending' end,
         case when sc.source_url is null then 'course_url_requires_discovery'
              when v_mode='scraper_first' and not exists(
                select 1 from pipeline.layer2_profile_provider_routes pr
                where pr.profile_id=sc.profile_id and pr.acquisition_provider_id=v_firecrawl and pr.enabled
              ) then 'firecrawl_not_enabled_for_profile' else null end
  from public.layer2_scope_courses(p_country_code,v_scope,p_scope_id) sc;

  select count(*) filter(where status='pending'),count(*) filter(where status='missing_url')
  into v_total,v_missing from pipeline.layer2_scope_wave_items where request_id=v_request;

  update pipeline.layer2_scope_wave_requests
  set total_items=v_total,missing_url_items=v_missing,
      metadata=metadata||jsonb_build_object('blocked_items',(select count(*) from pipeline.layer2_scope_wave_items where request_id=v_request and status='blocked')),
      updated_at=now()
  where id=v_request;

  v_result:=security.layer2_wave_dispatch_request(v_request);
  return v_result||jsonb_build_object(
    'status','wave_started','queueable_courses',v_total,'missing_url_courses',v_missing,
    'requested_wave_size',v_requested,'accepted_wave_size',v_accepted,'platform_wave_ceiling',1000
  );
end $$;
revoke all on function public.layer2_wave_scope_service(uuid,text,text,text,uuid,integer,boolean,text,uuid) from public,anon,authenticated;
grant execute on function public.layer2_wave_scope_service(uuid,text,text,text,uuid,integer,boolean,text,uuid) to service_role;

create or replace function public.svc_layer2_wave_scheduler()
returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','pipeline','security'
as $$
declare r record; v_count integer:=0; v_results jsonb:='[]'::jsonb; v_one jsonb;
begin
  for r in select id from pipeline.layer2_scope_wave_requests
    where schedule_remaining and status in('scheduled','running') and coalesce(next_wave_not_before,now())<=now()
    order by created_at limit 10
  loop
    v_one:=security.layer2_wave_dispatch_request(r.id);
    v_results:=v_results||jsonb_build_array(v_one);
    v_count:=v_count+1;
  end loop;
  return jsonb_build_object('ok',true,'requests_checked',v_count,'results',v_results);
end $$;
revoke all on function public.svc_layer2_wave_scheduler() from public,anon,authenticated;
grant execute on function public.svc_layer2_wave_scheduler() to service_role;

do $$
begin
 if exists(select 1 from cron.job where jobname='coursefinder-layer2-wave-scheduler') then
   perform cron.unschedule((select jobid from cron.job where jobname='coursefinder-layer2-wave-scheduler' limit 1));
 end if;
 perform cron.schedule('coursefinder-layer2-wave-scheduler','10,25,40,55 * * * *','select public.svc_layer2_wave_scheduler();');
end $$;

create table if not exists scholarship.course_mappings(
  id uuid primary key default gen_random_uuid(),
  scholarship_id uuid not null references scholarship.scholarships(id),
  course_id uuid not null references catalogue.courses(id),
  mapping_state text not null default 'mapped' check(mapping_state in('mapped','needs_review','not_applicable')),
  mapping_basis text not null,
  source_scope_id uuid references scholarship.scopes(id),
  evidence_id uuid references pipeline.evidence_artifacts(id),
  mapped_by uuid,
  mapped_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(scholarship_id,course_id)
);
create table if not exists scholarship.course_mapping_candidates(
  id uuid primary key default gen_random_uuid(),
  scholarship_id uuid not null references scholarship.scholarships(id),
  course_id uuid not null references catalogue.courses(id),
  candidate_reason text not null,
  evidence_id uuid references pipeline.evidence_artifacts(id),
  status text not null default 'needs_review' check(status in('needs_review','accepted','rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(scholarship_id,course_id)
);
alter table scholarship.course_mappings enable row level security;
alter table scholarship.course_mapping_candidates enable row level security;
revoke all on scholarship.course_mappings,scholarship.course_mapping_candidates from public,anon,authenticated;

create or replace function public.scholarship_course_fill_service(
  p_actor uuid,p_action text,p_country_code text default null,p_provider_id uuid default null
) returns jsonb
language plpgsql security definer
set search_path='pg_catalog','public','security','scholarship','catalogue','ref','pipeline'
as $$
declare v_rank integer:=0; v_courses integer:=0; v_scholarships integer:=0; v_pairs integer:=0; v_candidates integer:=0; v_written integer:=0;
begin
 if current_user not in('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 select coalesce(max(r.rank),0) into v_rank from security.user_roles ur join security.roles r on r.code=ur.role_code
 where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and r.status='active';
 if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
 if p_action not in('preview','fill','queue_review') then raise exception 'unsupported action' using errcode='22023'; end if;

 with scoped_courses as(
   select c.id,c.provider_id,c.country_id
   from catalogue.courses c join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
   where (p_provider_id is null or c.provider_id=p_provider_id)
     and (p_country_code is null or upper(co.iso_alpha2::text)=upper(p_country_code))
 ), deterministic as(
   select distinct s.id scholarship_id,c.id course_id,sc.id scope_id,coalesce(sc.evidence_id,s.evidence_id) evidence_id,
     case when sc.scope_type='course' then 'explicit_course_scope' else 'explicit_provider_scope' end basis
   from scholarship.scholarships s
   join scholarship.scopes sc on sc.scholarship_id=s.id and sc.include_exclude='include'
   join scoped_courses c on (sc.scope_type='course' and sc.course_id=c.id) or (sc.scope_type='provider' and sc.provider_id=c.provider_id)
   where not exists(
     select 1 from scholarship.scopes ex
     where ex.scholarship_id=s.id and ex.include_exclude='exclude'
       and ((ex.scope_type='course' and ex.course_id=c.id) or (ex.scope_type='provider' and ex.provider_id=c.provider_id))
   )
 ), provider_candidates as(
   select distinct s.id scholarship_id,c.id course_id,coalesce(s.evidence_id,null) evidence_id
   from scholarship.scholarships s join scoped_courses c on c.provider_id=s.provider_id
   where s.provider_id is not null
     and not exists(select 1 from deterministic d where d.scholarship_id=s.id and d.course_id=c.id)
     and not exists(select 1 from scholarship.scopes sc where sc.scholarship_id=s.id and sc.include_exclude='include' and sc.scope_type in('course','provider'))
 )
 select (select count(*) from scoped_courses),
        (select count(distinct s.id) from scholarship.scholarships s where
          exists(select 1 from scoped_courses c where c.provider_id=s.provider_id) or exists(select 1 from deterministic d where d.scholarship_id=s.id)),
        (select count(*) from deterministic),
        (select count(*) from provider_candidates)
 into v_courses,v_scholarships,v_pairs,v_candidates;

 if p_action='preview' then
   return jsonb_build_object('ok',true,'courses',v_courses,'scholarships',v_scholarships,'deterministic_mappings',v_pairs,
     'provider_level_candidates',v_candidates,'existing_mappings',(select count(*) from scholarship.course_mappings m where exists(
       select 1 from catalogue.courses c join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
       where c.id=m.course_id and (p_provider_id is null or c.provider_id=p_provider_id) and (p_country_code is null or upper(co.iso_alpha2::text)=upper(p_country_code))
     )),
     'rule','Only explicit course/provider include scopes are materialised. Provider ownership without explicit scope remains review-only.');
 end if;

 if p_action='fill' then
   with scoped_courses as(
     select c.id,c.provider_id from catalogue.courses c join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
     where (p_provider_id is null or c.provider_id=p_provider_id) and (p_country_code is null or upper(co.iso_alpha2::text)=upper(p_country_code))
   ), deterministic as(
     select distinct s.id scholarship_id,c.id course_id,sc.id scope_id,coalesce(sc.evidence_id,s.evidence_id) evidence_id,
       case when sc.scope_type='course' then 'explicit_course_scope' else 'explicit_provider_scope' end basis
     from scholarship.scholarships s join scholarship.scopes sc on sc.scholarship_id=s.id and sc.include_exclude='include'
     join scoped_courses c on (sc.scope_type='course' and sc.course_id=c.id) or (sc.scope_type='provider' and sc.provider_id=c.provider_id)
     where not exists(select 1 from scholarship.scopes ex where ex.scholarship_id=s.id and ex.include_exclude='exclude'
       and ((ex.scope_type='course' and ex.course_id=c.id) or (ex.scope_type='provider' and ex.provider_id=c.provider_id)))
   ), ins as(
     insert into scholarship.course_mappings(scholarship_id,course_id,mapping_state,mapping_basis,source_scope_id,evidence_id,mapped_by)
     select scholarship_id,course_id,'mapped',basis,scope_id,evidence_id,p_actor from deterministic
     on conflict(scholarship_id,course_id) do update
       set mapping_state='mapped',mapping_basis=excluded.mapping_basis,source_scope_id=excluded.source_scope_id,
           evidence_id=excluded.evidence_id,mapped_by=excluded.mapped_by,updated_at=now()
     returning 1
   ) select count(*) into v_written from ins;
   return jsonb_build_object('ok',true,'status','filled','written_or_refreshed',v_written,'deterministic_mappings',v_pairs,
     'canonical_course_fields_changed',false,'publication_changed',false);
 end if;

 with scoped_courses as(
   select c.id,c.provider_id from catalogue.courses c join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
   where (p_provider_id is null or c.provider_id=p_provider_id) and (p_country_code is null or upper(co.iso_alpha2::text)=upper(p_country_code))
 ), candidates as(
   select distinct s.id scholarship_id,c.id course_id,s.evidence_id
   from scholarship.scholarships s join scoped_courses c on c.provider_id=s.provider_id
   where s.provider_id is not null
     and not exists(select 1 from scholarship.scopes sc where sc.scholarship_id=s.id and sc.include_exclude='include' and sc.scope_type in('course','provider'))
 )
 insert into scholarship.course_mapping_candidates(scholarship_id,course_id,candidate_reason,evidence_id)
 select scholarship_id,course_id,'provider_owned_but_no_explicit_course_or_provider_scope',evidence_id from candidates
 on conflict(scholarship_id,course_id) do update set updated_at=now(),status='needs_review';
 get diagnostics v_written=row_count;
 return jsonb_build_object('ok',true,'status','review_candidates_queued','written_or_refreshed',v_written,
   'publication_changed',false,'eligibility_manufactured',false);
end $$;
revoke all on function public.scholarship_course_fill_service(uuid,text,text,uuid) from public,anon,authenticated;
grant execute on function public.scholarship_course_fill_service(uuid,text,text,uuid) to service_role;

create or replace function security.admin_course_scholarships(p_course_id uuid)
returns jsonb language plpgsql stable security definer
set search_path='pg_catalog','security','scholarship','catalogue','auth'
as $$
declare v_rank integer; v_items jsonb; v_candidates integer;
begin
 if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
 v_rank:=security.current_role_rank(); if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
 select coalesce(jsonb_agg(jsonb_build_object(
   'mapping_id',m.id,'scholarship_id',s.id,'name',s.name,'audience',s.audience,'award_value_text',s.award_value_text,
   'academic_year',s.academic_year,'source_url',s.source_url,'evidence_id',coalesce(m.evidence_id,s.evidence_id),
   'mapping_basis',m.mapping_basis,'mapping_state',m.mapping_state,'mapped_at',m.mapped_at
 ) order by s.name),'[]'::jsonb)
 into v_items
 from scholarship.course_mappings m join scholarship.scholarships s on s.id=m.scholarship_id
 where m.course_id=p_course_id and m.mapping_state='mapped';
 select count(*) into v_candidates from scholarship.course_mapping_candidates where course_id=p_course_id and status='needs_review';
 return jsonb_build_object('items',v_items,'mapped_count',jsonb_array_length(v_items),'needs_review_count',v_candidates,
   'state',case when jsonb_array_length(v_items)>0 then 'mapped' when v_candidates>0 then 'needs_review' else 'not_mapped' end);
end $$;
revoke all on function security.admin_course_scholarships(uuid) from public,anon,authenticated;
grant execute on function security.admin_course_scholarships(uuid) to authenticated,service_role;

create or replace function security.admin_layer_status_summary()
returns jsonb language plpgsql stable security definer
set search_path='pg_catalog','security','pipeline','catalogue','scholarship','auth'
as $$
declare v_rank integer;
begin
 if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
 v_rank:=security.current_role_rank(); if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
 return jsonb_build_object(
  'layer1',jsonb_build_object(
    'active_sources',(select count(*) from pipeline.sources where layer=1 and enabled),
    'running_jobs',(select count(*) from pipeline.jobs where job_type='regulatory_sync' and status='running'),
    'failed_24h',(select count(*) from pipeline.jobs where job_type='regulatory_sync' and status='failed' and created_at>now()-interval '24 hours'),
    'latest_activity',(select max(created_at) from pipeline.jobs where job_type='regulatory_sync')
  ),
  'layer2',jsonb_build_object(
    'active_batches',(select count(*) from pipeline.layer2_run_batches where status in('queued','running','partial')),
    'scheduled_wave_requests',(select count(*) from pipeline.layer2_scope_wave_requests where status in('scheduled','running','wave1_dispatched')),
    'wave_pending_courses',(select count(*) from pipeline.layer2_scope_wave_items where status='pending'),
    'processed_24h',(select count(*) from pipeline.layer2_run_items where completed_at>now()-interval '24 hours'),
    'evidence_24h',(select count(*) from pipeline.evidence_artifacts where layer=2 and captured_at>now()-interval '24 hours')
  ),
  'layer3',jsonb_build_object(
    'qualified_profiles',(select count(*) from pipeline.layer3_model_profiles where enabled and not paused and coalesce((quality_benchmark->>'pass')::boolean,false)),
    'pending_evidence_candidates',(select count(*) from security.layer3_evidence_candidates_read(200)),
    'interpretations_24h',(select count(*) from pipeline.layer3_interpretations where created_at>now()-interval '24 hours'),
    'calls_24h',(select coalesce(sum(external_call_count),0) from pipeline.layer3_interpretations where created_at>now()-interval '24 hours'),
    'tokens_24h',(select coalesce(sum(input_tokens+output_tokens),0) from pipeline.layer3_interpretations where created_at>now()-interval '24 hours'),
    'recorded_cost_24h',(select coalesce(sum(estimated_cost_usd),0) from pipeline.layer3_interpretations where created_at>now()-interval '24 hours')
  ),
  'layer4',jsonb_build_object(
    'pending_reviews',(select count(*) from pipeline.layer4_review_items where status='pending'),
    'active_overrides',(select count(*) from (
      select distinct on(entity_type,entity_id,field_code) event_type
      from pipeline.layer4_override_decisions order by entity_type,entity_id,field_code,created_at desc,id desc
    ) x where event_type<>'revert'),
    'publication_decisions',(select count(*) from pipeline.layer4_publication_decisions)
  ),
  'scholarships',jsonb_build_object(
    'scholarships',(select count(*) from scholarship.scholarships),
    'course_mappings',(select count(*) from scholarship.course_mappings where mapping_state='mapped'),
    'review_candidates',(select count(*) from scholarship.course_mapping_candidates where status='needs_review')
  )
 );
end $$;
revoke all on function security.admin_layer_status_summary() from public,anon;
grant execute on function security.admin_layer_status_summary() to authenticated,service_role;

do $$
declare v_oid oid; v_def text;
begin
 select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname='admin_read'
   and pg_get_function_identity_arguments(p.oid)='p_operation text, p_args jsonb' limit 1;
 if v_oid is null then raise exception 'public.admin_read(text,jsonb) not found'; end if;
 select pg_get_functiondef(v_oid) into v_def;
 if position('layer_status_summary' in v_def)=0 then
   v_def:=replace(v_def,'if p_operation=''publication_overview'' then',
     'if p_operation=''layer_status_summary'' then return security.admin_layer_status_summary(); end if;'||E'\n if p_operation=''publication_overview'' then');
 end if;
 if position('admin_course_scholarships' in v_def)=0 then
   v_def:=replace(v_def,
     'jsonb_build_object(''layer4_publication'',security.layer4_publication_state_read(''course'',v_id));',
     'jsonb_build_object(''layer4_publication'',security.layer4_publication_state_read(''course'',v_id))||jsonb_build_object(''course_scholarships'',security.admin_course_scholarships(v_id));');
 end if;
 execute v_def;
end $$;
