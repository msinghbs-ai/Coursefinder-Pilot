-- A15 service-role bridge for private contact intelligence tables.

create or replace function public.provider_contact_profiles_service(
  p_provider_id uuid default null,
  p_limit integer default 2
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','pipeline','catalogue','ref'
as $$
declare v jsonb;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  with rows as (
    select jsonb_build_object(
      'id',pcp.id,'provider_id',pcp.provider_id,'country_id',pcp.country_id,
      'base_url',pcp.base_url,'domain',pcp.domain,'enabled',pcp.enabled,'paused',pcp.paused,
      'title_terms',pcp.title_terms,'last_run_at',pcp.last_run_at,'last_success_at',pcp.last_success_at,
      'provider_name',p.canonical_name
    ) row_json
    from pipeline.provider_contact_profiles pcp
    join catalogue.providers p on p.id=pcp.provider_id
    where pcp.enabled=true and pcp.paused=false
      and (p_provider_id is null or pcp.provider_id=p_provider_id)
    order by pcp.last_run_at nulls first, lower(p.canonical_name)
    limit greatest(1,least(coalesce(p_limit,2),5))
  )
  select coalesce(jsonb_agg(row_json),'[]'::jsonb) into v from rows;
  return v;
end $$;

create or replace function public.provider_contact_source_service(
  p_provider_id uuid,
  p_country_id uuid,
  p_base_url text,
  p_label text
) returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog','public','pipeline'
as $$
declare v_id uuid;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  select id into v_id
  from pipeline.sources
  where provider_id=p_provider_id and source_type='provider_contact_first_party'
  order by created_at
  limit 1;
  if v_id is null then
    insert into pipeline.sources(source_type,provider_id,country_id,url,label,trust_rank,metadata)
    values('provider_contact_first_party',p_provider_id,p_country_id,p_base_url,p_label,80,
      jsonb_build_object('layer',2,'contact_intelligence',true))
    returning id into v_id;
  end if;
  return v_id;
end $$;

create or replace function public.provider_contact_observation_upsert_service(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','pipeline'
as $$
declare
  v_prior pipeline.provider_contact_observations%rowtype;
  v_id uuid;
  v_event text;
  v_before jsonb;
  v_after jsonb;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  select * into v_prior from pipeline.provider_contact_observations
  where identity_hash=p_payload->>'identity_hash'
  limit 1 for update;

  v_after=jsonb_build_object(
    'job_title',nullif(p_payload->>'job_title',''),
    'territory_text',nullif(p_payload->>'territory_text',''),
    'work_email',nullif(p_payload->>'work_email',''),
    'work_phone',nullif(p_payload->>'work_phone',''),
    'professional_profile_url',nullif(p_payload->>'professional_profile_url','')
  );

  if v_prior.id is null then
    insert into pipeline.provider_contact_observations(
      provider_id,profile_id,source_class,source_provider,source_url,external_person_id,
      full_name,job_title,team_name,territory_text,territory_codes,work_email,work_phone,
      professional_profile_url,evidence_id,identity_hash,verification_state,observed_at,last_verified_at,
      is_current,confidence,metadata
    ) values(
      (p_payload->>'provider_id')::uuid,nullif(p_payload->>'profile_id','')::uuid,
      p_payload->>'source_class',nullif(p_payload->>'source_provider',''),nullif(p_payload->>'source_url',''),
      nullif(p_payload->>'external_person_id',''),nullif(p_payload->>'full_name',''),nullif(p_payload->>'job_title',''),
      nullif(p_payload->>'team_name',''),nullif(p_payload->>'territory_text',''),
      coalesce(array(select jsonb_array_elements_text(coalesce(p_payload->'territory_codes','[]'::jsonb))),'{}'::text[]),
      nullif(p_payload->>'work_email',''),nullif(p_payload->>'work_phone',''),nullif(p_payload->>'professional_profile_url',''),
      nullif(p_payload->>'evidence_id','')::uuid,p_payload->>'identity_hash',
      coalesce(nullif(p_payload->>'verification_state',''),'unverified'),
      coalesce((p_payload->>'observed_at')::timestamptz,now()),coalesce((p_payload->>'last_verified_at')::timestamptz,now()),
      coalesce((p_payload->>'is_current')::boolean,true),nullif(p_payload->>'confidence','')::numeric,
      coalesce(p_payload->'metadata','{}'::jsonb)
    ) returning id into v_id;
    insert into pipeline.provider_contact_watch_events(provider_id,observation_id,event_type,source_class,after_state,metadata)
    values((p_payload->>'provider_id')::uuid,v_id,'new_contact',p_payload->>'source_class',v_after,
      jsonb_build_object('worker_version',p_payload#>>'{metadata,worker_version}','source_provider',p_payload->>'source_provider'));
    return jsonb_build_object('id',v_id,'created',true,'event_type','new_contact');
  end if;

  v_before=jsonb_build_object(
    'job_title',v_prior.job_title,'territory_text',v_prior.territory_text,'work_email',v_prior.work_email,
    'work_phone',v_prior.work_phone,'professional_profile_url',v_prior.professional_profile_url
  );
  if v_prior.job_title is distinct from nullif(p_payload->>'job_title','') then v_event='title_changed';
  elsif v_prior.territory_text is distinct from nullif(p_payload->>'territory_text','') then v_event='territory_changed';
  elsif v_prior.work_email is distinct from nullif(p_payload->>'work_email','')
     or v_prior.work_phone is distinct from nullif(p_payload->>'work_phone','')
     or v_prior.professional_profile_url is distinct from nullif(p_payload->>'professional_profile_url','') then v_event='contact_changed';
  end if;

  update pipeline.provider_contact_observations set
    profile_id=coalesce(nullif(p_payload->>'profile_id','')::uuid,profile_id),
    source_provider=coalesce(nullif(p_payload->>'source_provider',''),source_provider),
    source_url=coalesce(nullif(p_payload->>'source_url',''),source_url),
    external_person_id=coalesce(nullif(p_payload->>'external_person_id',''),external_person_id),
    full_name=coalesce(nullif(p_payload->>'full_name',''),full_name),
    job_title=nullif(p_payload->>'job_title',''),
    team_name=nullif(p_payload->>'team_name',''),
    territory_text=nullif(p_payload->>'territory_text',''),
    territory_codes=coalesce(array(select jsonb_array_elements_text(coalesce(p_payload->'territory_codes','[]'::jsonb))),territory_codes),
    work_email=nullif(p_payload->>'work_email',''),
    work_phone=nullif(p_payload->>'work_phone',''),
    professional_profile_url=nullif(p_payload->>'professional_profile_url',''),
    evidence_id=coalesce(nullif(p_payload->>'evidence_id','')::uuid,evidence_id),
    verification_state=coalesce(nullif(p_payload->>'verification_state',''),verification_state),
    observed_at=coalesce((p_payload->>'observed_at')::timestamptz,observed_at),
    last_verified_at=coalesce((p_payload->>'last_verified_at')::timestamptz,now()),
    is_current=coalesce((p_payload->>'is_current')::boolean,true),
    confidence=coalesce(nullif(p_payload->>'confidence','')::numeric,confidence),
    metadata=metadata||coalesce(p_payload->'metadata','{}'::jsonb),
    updated_at=now()
  where id=v_prior.id;

  if v_event is not null then
    insert into pipeline.provider_contact_watch_events(provider_id,observation_id,event_type,source_class,before_state,after_state,metadata)
    values(v_prior.provider_id,v_prior.id,v_event,p_payload->>'source_class',v_before,v_after,
      jsonb_build_object('worker_version',p_payload#>>'{metadata,worker_version}','source_provider',p_payload->>'source_provider'));
  end if;
  return jsonb_build_object('id',v_prior.id,'created',false,'event_type',v_event);
end $$;

create or replace function public.provider_contact_profile_finish_service(
  p_profile_id uuid,
  p_status text,
  p_error text default null
) returns boolean
language plpgsql
security definer
set search_path to 'pg_catalog','public','pipeline'
as $$
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  update pipeline.provider_contact_profiles set
    last_run_at=now(),
    last_success_at=case when p_status='succeeded' then now() else last_success_at end,
    last_error=case when p_status='succeeded' then null else left(p_error,1000) end,
    updated_at=now()
  where id=p_profile_id;
  return found;
end $$;

create or replace function public.provider_contact_enrichment_attempt_service(p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog','public','pipeline'
as $$
declare v_id uuid;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  insert into pipeline.provider_contact_enrichment_attempts(
    provider_id,source_provider,request_type,domain,requested_titles,status,external_call_count,
    vendor_units,estimated_cost_usd,latency_ms,error,metadata
  ) values(
    (p_payload->>'provider_id')::uuid,p_payload->>'source_provider',p_payload->>'request_type',
    nullif(p_payload->>'domain',''),
    coalesce(array(select jsonb_array_elements_text(coalesce(p_payload->'requested_titles','[]'::jsonb))),'{}'::text[]),
    p_payload->>'status',coalesce((p_payload->>'external_call_count')::integer,0),
    nullif(p_payload->>'vendor_units','')::numeric,nullif(p_payload->>'estimated_cost_usd','')::numeric,
    nullif(p_payload->>'latency_ms','')::integer,nullif(p_payload->>'error',''),coalesce(p_payload->'metadata','{}'::jsonb)
  ) returning id into v_id;
  return v_id;
end $$;

revoke all on function public.provider_contact_profiles_service(uuid,integer) from public,anon,authenticated;
revoke all on function public.provider_contact_source_service(uuid,uuid,text,text) from public,anon,authenticated;
revoke all on function public.provider_contact_observation_upsert_service(jsonb) from public,anon,authenticated;
revoke all on function public.provider_contact_profile_finish_service(uuid,text,text) from public,anon,authenticated;
revoke all on function public.provider_contact_enrichment_attempt_service(jsonb) from public,anon,authenticated;

grant execute on function public.provider_contact_profiles_service(uuid,integer) to service_role,postgres;
grant execute on function public.provider_contact_source_service(uuid,uuid,text,text) to service_role,postgres;
grant execute on function public.provider_contact_observation_upsert_service(jsonb) to service_role,postgres;
grant execute on function public.provider_contact_profile_finish_service(uuid,text,text) to service_role,postgres;
grant execute on function public.provider_contact_enrichment_attempt_service(jsonb) to service_role,postgres;
