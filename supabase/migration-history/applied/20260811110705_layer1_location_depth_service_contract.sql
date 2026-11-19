alter table catalogue.campuses
  add column if not exists source_id uuid references pipeline.sources(id),
  add column if not exists evidence_id uuid references pipeline.evidence_artifacts(id),
  add column if not exists last_verified_at timestamptz;

create index if not exists idx_campuses_source_id on catalogue.campuses(source_id);
create index if not exists idx_campuses_evidence_id on catalogue.campuses(evidence_id);

create or replace function public.svc_layer1_apply_location_records(
  p_country_code text,
  p_source_id uuid,
  p_evidence_id uuid,
  p_registration_scheme text,
  p_records jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public,catalogue,ref,pipeline
as $$
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
        select s.id into v_subdivision from ref.subdivisions s
        where s.country_id=v_country and (upper(s.code)=upper(v_state) or lower(s.name)=lower(v_state)) limit 1;
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
    'provider_missing',v_provider_missing,'course_missing',v_course_missing,'campus_missing',v_campus_missing,'conflicts',v_conflicts
  );
end $$;

revoke all on function public.svc_layer1_apply_location_records(text,uuid,uuid,text,jsonb) from public, anon, authenticated;
grant execute on function public.svc_layer1_apply_location_records(text,uuid,uuid,text,jsonb) to service_role;
