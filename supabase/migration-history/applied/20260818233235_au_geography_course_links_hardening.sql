create or replace function ref.resolve_subdivision_exact(p_country_id uuid, p_source_state text)
returns uuid
language sql
stable
security invoker
set search_path = ref
as $$
  select s.id
  from ref.subdivisions s
  where s.country_id = p_country_id
    and nullif(btrim(p_source_state),'') is not null
    and (
      upper(s.code) = upper(btrim(p_source_state))
      or lower(s.name) = lower(btrim(p_source_state))
      or upper(regexp_replace(s.code, '^.*-', '')) = upper(btrim(p_source_state))
    )
  order by case
    when upper(s.code) = upper(btrim(p_source_state)) then 0
    when lower(s.name) = lower(btrim(p_source_state)) then 1
    else 2
  end, s.id
  limit 1
$$;

revoke all on function ref.resolve_subdivision_exact(uuid,text) from public, anon, authenticated;
grant execute on function ref.resolve_subdivision_exact(uuid,text) to service_role;

create table if not exists catalogue.course_links (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references catalogue.courses(id) on delete cascade,
  link_type text not null,
  url text not null,
  audience text,
  locale text,
  label text,
  is_primary boolean not null default false,
  status text not null default 'active' check (status in ('active','inactive','deprecated','unverified')),
  valid_from date,
  valid_to date,
  source_id uuid references pipeline.sources(id),
  evidence_id uuid references pipeline.evidence_artifacts(id),
  confidence numeric check (confidence is null or (confidence >= 0 and confidence <= 1)),
  last_verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint course_links_url_not_blank check (btrim(url) <> ''),
  constraint course_links_type_not_blank check (btrim(link_type) <> ''),
  constraint course_links_valid_range check (valid_to is null or valid_from is null or valid_to >= valid_from),
  unique(course_id, link_type, url)
);

create index if not exists course_links_course_idx on catalogue.course_links(course_id);
create index if not exists course_links_type_status_idx on catalogue.course_links(link_type,status);
create index if not exists course_links_source_idx on catalogue.course_links(source_id);
create index if not exists course_links_evidence_idx on catalogue.course_links(evidence_id);
create unique index if not exists course_links_one_primary_active_idx
  on catalogue.course_links(course_id)
  where is_primary and status='active';

alter table catalogue.course_links enable row level security;
revoke all on catalogue.course_links from public, anon, authenticated;
grant select,insert,update,delete on catalogue.course_links to service_role;

comment on table catalogue.course_links is 'Evidence-backed relational URLs for canonical Courses. courses.course_url remains a compatibility/current-primary field, not the multi-link source of truth.';
comment on column catalogue.course_links.link_type is 'Source-preserved semantic type such as primary, international, handbook, fees, apply or provider_course. Vocabulary is governed outside the physical table to allow future source types.';

create or replace function public.svc_layer1_apply_location_records(p_country_code text, p_source_id uuid, p_evidence_id uuid, p_registration_scheme text, p_records jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public','catalogue','ref','pipeline'
as $function$
declare
  r jsonb;
  v_country uuid;
  v_provider uuid;
  v_course uuid;
  v_campus uuid;
  v_subdivision uuid;
  v_scheme text;
  v_pcode text;
  v_ccode text;
  v_lcode text;
  v_lname text;
  v_city text;
  v_state text;
  v_delivery text;
  v_stable text;
  v_campus_created int := 0;
  v_campus_existing int := 0;
  v_link_created int := 0;
  v_link_existing int := 0;
  v_provider_missing int := 0;
  v_course_missing int := 0;
  v_campus_missing int := 0;
  v_conflicts int := 0;
  v_unmapped_subdivision int := 0;
  v_location_records int := 0;
  v_course_location_records int := 0;
begin
  if current_user <> 'postgres' and coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;
  v_scheme := lower(nullif(trim(p_registration_scheme),''));
  if v_scheme is null then raise exception 'registration scheme required'; end if;
  select id into v_country from ref.countries where upper(iso_alpha2::text)=upper(p_country_code);
  if v_country is null then raise exception 'country seed missing: %',p_country_code; end if;

  for r in select value from jsonb_array_elements(coalesce(p_records,'[]'::jsonb)) loop
    v_provider := null; v_course := null; v_campus := null; v_subdivision := null;
    v_pcode := upper(nullif(trim(r->>'provider_code'),''));
    v_ccode := upper(nullif(trim(r->>'course_code'),''));
    v_lcode := upper(nullif(trim(r->>'location_code'),''));
    v_lname := nullif(trim(r->>'location_name'),'');
    v_city := nullif(trim(r->>'city'),'');
    v_state := nullif(trim(r->>'state'),'');
    v_delivery := coalesce(nullif(trim(r->>'delivery_mode'),''),'on_campus');
    if v_pcode is null or v_lcode is null then v_conflicts:=v_conflicts+1; continue; end if;

    select pr.provider_id into v_provider
    from catalogue.provider_registrations pr
    join catalogue.providers p on p.id=pr.provider_id
    where p.country_id=v_country
      and lower(pr.registration_scheme)=v_scheme
      and upper(pr.registration_code)=v_pcode
    order by pr.checked_at desc nulls last, pr.id limit 1;
    if v_provider is null then v_provider_missing:=v_provider_missing+1; continue; end if;

    v_stable := 'campus:'||v_scheme||':'||lower(regexp_replace(v_pcode,'[^a-zA-Z0-9]+','-','g'))||':'||lower(regexp_replace(v_lcode,'[^a-zA-Z0-9]+','-','g'));
    select id into v_campus from catalogue.campuses where stable_key=v_stable limit 1;

    if v_ccode is null then
      v_location_records:=v_location_records+1;
      if v_state is not null then
        v_subdivision := ref.resolve_subdivision_exact(v_country,v_state);
        if v_subdivision is null then v_unmapped_subdivision:=v_unmapped_subdivision+1; end if;
      end if;
      if v_campus is null then
        insert into catalogue.campuses(stable_key,provider_id,name,campus_code,country_id,subdivision_id,city,address_line1,address_line2,postcode,status,publication_status,source_id,evidence_id,last_verified_at)
        values(v_stable,v_provider,coalesce(v_lname,v_lcode),v_lcode,v_country,v_subdivision,v_city,nullif(trim(r->>'address_line1'),''),nullif(trim(r->>'address_line2'),''),nullif(trim(r->>'postcode'),''),'active','unpublished',p_source_id,p_evidence_id,now())
        returning id into v_campus;
        v_campus_created:=v_campus_created+1;
      else
        update catalogue.campuses set
          name=coalesce(v_lname,name), subdivision_id=coalesce(v_subdivision,subdivision_id), city=coalesce(v_city,city),
          address_line1=coalesce(nullif(trim(r->>'address_line1'),''),address_line1),
          address_line2=coalesce(nullif(trim(r->>'address_line2'),''),address_line2),
          postcode=coalesce(nullif(trim(r->>'postcode'),''),postcode), status='active', source_id=p_source_id,
          evidence_id=coalesce(p_evidence_id,evidence_id), last_verified_at=now(), updated_at=now()
        where id=v_campus;
        v_campus_existing:=v_campus_existing+1;
      end if;
    else
      v_course_location_records:=v_course_location_records+1;
      if v_campus is null then v_campus_missing:=v_campus_missing+1; continue; end if;
      select cr.course_id into v_course
      from catalogue.course_registrations cr
      join catalogue.courses c on c.id=cr.course_id
      where c.provider_id=v_provider and lower(cr.scheme)=v_scheme and upper(cr.registration_code)=v_ccode
      order by cr.id limit 1;
      if v_course is null then v_course_missing:=v_course_missing+1; continue; end if;
      if exists(select 1 from catalogue.course_campuses where course_id=v_course and campus_id=v_campus and delivery_mode=v_delivery) then
        update catalogue.course_campuses set source_id=p_source_id,evidence_id=coalesce(p_evidence_id,evidence_id)
        where course_id=v_course and campus_id=v_campus and delivery_mode=v_delivery;
        v_link_existing:=v_link_existing+1;
      else
        insert into catalogue.course_campuses(course_id,campus_id,delivery_mode,is_primary,source_id,evidence_id)
        values(v_course,v_campus,v_delivery,false,p_source_id,p_evidence_id);
        v_link_created:=v_link_created+1;
      end if;
    end if;
  end loop;

  return jsonb_build_object(
    'location_records',v_location_records,'course_location_records',v_course_location_records,
    'campuses_created',v_campus_created,'campuses_existing',v_campus_existing,
    'course_links_created',v_link_created,'course_links_existing',v_link_existing,
    'provider_missing',v_provider_missing,'course_missing',v_course_missing,'campus_missing',v_campus_missing,
    'unmapped_subdivision',v_unmapped_subdivision,'conflicts',v_conflicts
  );
end $function$;

revoke all on function public.svc_layer1_apply_location_records(text,uuid,uuid,text,jsonb) from public, anon, authenticated;
grant execute on function public.svc_layer1_apply_location_records(text,uuid,uuid,text,jsonb) to service_role;

create or replace function public.svc_layer1_apply_register_records(p_country_code text, p_source_id uuid, p_evidence_id uuid, p_registration_scheme text, p_records jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public','catalogue','pim','ref','pipeline'
as $function$
declare
  r jsonb;
  v_country uuid;
  v_provider uuid;
  v_course uuid;
  v_family_provider uuid;
  v_family_course uuid;
  v_level uuid;
  v_subdivision uuid;
  v_provider_created int:=0;
  v_provider_linked int:=0;
  v_provider_existing int:=0;
  v_course_created int:=0;
  v_course_linked int:=0;
  v_course_existing int:=0;
  v_conflicts int:=0;
  v_provider_unmapped_subdivision int:=0;
  v_pcode text;
  v_ccode text;
  v_pname text;
  v_cname text;
  v_level_name text;
  v_weeks numeric;
  v_scheme text;
  v_website text;
  v_city text;
  v_state text;
  v_address1 text;
  v_address2 text;
  v_postcode text;
  v_provider_key text;
  v_course_key text;
begin
  if current_user <> 'postgres' and coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  v_scheme:=lower(nullif(trim(p_registration_scheme),''));
  if v_scheme is null then raise exception 'registration scheme required'; end if;
  select id into v_country from ref.countries where upper(iso_alpha2::text)=upper(p_country_code);
  select id into v_family_provider from pim.attribute_families where entity_type='provider' and status='active' order by case when code='provider_default' then 0 else 1 end limit 1;
  select id into v_family_course from pim.attribute_families where entity_type='course' and status='active' order by case when code='course_default' then 0 else 1 end limit 1;
  if v_country is null then raise exception 'country seed missing: %',p_country_code; end if;

  for r in select value from jsonb_array_elements(coalesce(p_records,'[]'::jsonb)) loop
    v_provider:=null; v_course:=null; v_level:=null; v_subdivision:=null;
    v_pcode:=upper(nullif(trim(r->>'provider_code'),''));
    v_ccode:=upper(nullif(trim(r->>'course_code'),''));
    v_pname:=nullif(trim(r->>'provider_name'),'');
    v_cname:=nullif(trim(r->>'course_name'),'');
    v_level_name:=lower(coalesce(r->>'course_level',''));
    v_website:=nullif(trim(r->>'website'),'');
    v_city:=nullif(trim(r->>'city'),'');
    v_state:=nullif(trim(r->>'state'),'');
    v_address1:=nullif(trim(r->>'address_line1'),'');
    v_address2:=nullif(trim(r->>'address_line2'),'');
    v_postcode:=nullif(trim(r->>'postcode'),'');
    v_weeks:=case when (r->>'duration_weeks') ~ '^[0-9]+(\.[0-9]+)?$' then (r->>'duration_weeks')::numeric else null end;
    if v_pcode is null or v_pname is null then v_conflicts:=v_conflicts+1; continue; end if;
    if v_state is not null then
      v_subdivision:=ref.resolve_subdivision_exact(v_country,v_state);
      if v_subdivision is null then v_provider_unmapped_subdivision:=v_provider_unmapped_subdivision+1; end if;
    end if;

    v_provider_key := 'provider:'||v_scheme||':'||lower(regexp_replace(v_pcode,'[^a-zA-Z0-9]+','-','g'));
    select pr.provider_id into v_provider from catalogue.provider_registrations pr join catalogue.providers p on p.id=pr.provider_id
      where p.country_id=v_country and lower(pr.registration_scheme)=v_scheme and upper(pr.registration_code)=v_pcode
      order by pr.checked_at desc nulls last, pr.id limit 1;
    if v_provider is null then
      select p.id into v_provider from catalogue.providers p where p.country_id=v_country and p.stable_key=v_provider_key limit 1;
      if v_provider is null then
        insert into pim.entity_registry(entity_type,stable_key,family_id) values('provider',v_provider_key,v_family_provider) returning id into v_provider;
        insert into catalogue.providers(id,stable_key,canonical_name,display_name,country_id,subdivision_id,website,primary_city,address_line1,address_line2,postcode,lifecycle_status,publication_status,canonical_source_id,last_verified_at)
        values(v_provider,v_provider_key,v_pname,v_pname,v_country,v_subdivision,v_website,v_city,v_address1,v_address2,v_postcode,'active','unpublished',p_source_id,now());
        v_provider_created:=v_provider_created+1;
      else v_provider_linked:=v_provider_linked+1; end if;
      insert into catalogue.provider_registrations(provider_id,source_id,registration_scheme,registration_code,status,checked_at,evidence_id)
      values(v_provider,p_source_id,v_scheme,v_pcode,'active',now(),p_evidence_id) on conflict do nothing;
    else v_provider_existing:=v_provider_existing+1; end if;

    update catalogue.provider_registrations set source_id=p_source_id,status='active',checked_at=now(),evidence_id=coalesce(p_evidence_id,evidence_id)
      where provider_id=v_provider and lower(registration_scheme)=v_scheme and upper(registration_code)=v_pcode;
    update catalogue.providers set canonical_source_id=p_source_id,last_verified_at=now(),website=coalesce(website,v_website),
      primary_city=coalesce(primary_city,v_city), subdivision_id=coalesce(v_subdivision,subdivision_id),
      address_line1=coalesce(address_line1,v_address1), address_line2=coalesce(address_line2,v_address2), postcode=coalesce(postcode,v_postcode), updated_at=now()
      where id=v_provider;

    if v_ccode is null or v_cname is null then continue; end if;
    v_course_key := 'course:'||v_scheme||':'||lower(regexp_replace(v_pcode,'[^a-zA-Z0-9]+','-','g'))||':'||lower(regexp_replace(v_ccode,'[^a-zA-Z0-9]+','-','g'));
    select cr.course_id into v_course from catalogue.course_registrations cr join catalogue.courses c on c.id=cr.course_id
      where c.provider_id=v_provider and lower(cr.scheme)=v_scheme and upper(cr.registration_code)=v_ccode order by cr.id limit 1;
    if v_course is null then
      select c.id into v_course from catalogue.courses c where c.provider_id=v_provider and c.stable_key=v_course_key limit 1;
      if v_course is null then
        insert into pim.entity_registry(entity_type,stable_key,family_id) values('course',v_course_key,v_family_course) returning id into v_course;
        insert into catalogue.courses(id,stable_key,provider_id,canonical_title,display_title,course_code,duration_value,duration_unit,lifecycle_status,publication_status,canonical_source_id,last_verified_at)
        values(v_course,v_course_key,v_provider,v_cname,v_cname,v_ccode,v_weeks,case when v_weeks is not null then 'weeks' end,'active','unpublished',p_source_id,now());
        v_course_created:=v_course_created+1;
      else v_course_linked:=v_course_linked+1; end if;
      insert into catalogue.course_registrations(course_id,scheme,registration_code,country_id,status,source_id,evidence_id)
      values(v_course,v_scheme,v_ccode,v_country,'active',p_source_id,p_evidence_id) on conflict do nothing;
    else v_course_existing:=v_course_existing+1; end if;

    select id into v_level from ref.study_levels where code=case
      when v_level_name like '%doctor%' or v_level_name like '%phd%' then 'doctorate'
      when v_level_name like '%master%' then 'masters'
      when v_level_name like '%graduate certificate%' then 'graduate_certificate'
      when v_level_name like '%graduate diploma%' then 'graduate_diploma'
      when v_level_name like '%bachelor%' then 'bachelor'
      when v_level_name like '%associate%' then 'associate_degree'
      when v_level_name like '%diploma%' then 'diploma'
      when v_level_name like '%certificate%' then 'certificate'
      when v_level_name like '%foundation%' then 'foundation' else null end;
    update catalogue.courses set study_level_id=coalesce(v_level,study_level_id),duration_value=coalesce(v_weeks,duration_value),
      duration_unit=case when v_weeks is not null then 'weeks' else duration_unit end,canonical_source_id=p_source_id,last_verified_at=now(),updated_at=now() where id=v_course;
    update catalogue.course_registrations set source_id=p_source_id,status='active',evidence_id=coalesce(p_evidence_id,evidence_id)
      where course_id=v_course and lower(scheme)=v_scheme and upper(registration_code)=v_ccode;
  end loop;

  return jsonb_build_object('provider_created',v_provider_created,'provider_linked',v_provider_linked,'provider_existing',v_provider_existing,
    'course_created',v_course_created,'course_linked',v_course_linked,'course_existing',v_course_existing,
    'provider_unmapped_subdivision',v_provider_unmapped_subdivision,'conflicts',v_conflicts,'records',jsonb_array_length(coalesce(p_records,'[]'::jsonb)));
end $function$;

revoke all on function public.svc_layer1_apply_register_records(text,uuid,uuid,text,jsonb) from public, anon, authenticated;
grant execute on function public.svc_layer1_apply_register_records(text,uuid,uuid,text,jsonb) to service_role;
