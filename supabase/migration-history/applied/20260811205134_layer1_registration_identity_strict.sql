create or replace function public.svc_layer1_apply_register_records(
  p_country_code text,
  p_source_id uuid,
  p_evidence_id uuid,
  p_registration_scheme text,
  p_records jsonb
) returns jsonb
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
  v_provider_created int:=0;
  v_provider_linked int:=0;
  v_provider_existing int:=0;
  v_course_created int:=0;
  v_course_linked int:=0;
  v_course_existing int:=0;
  v_conflicts int:=0;
  v_pcode text;
  v_ccode text;
  v_pname text;
  v_cname text;
  v_level_name text;
  v_weeks numeric;
  v_scheme text;
  v_website text;
  v_city text;
  v_provider_key text;
  v_course_key text;
begin
  if current_user <> 'postgres' and coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;

  v_scheme:=lower(nullif(trim(p_registration_scheme),''));
  if v_scheme is null then raise exception 'registration scheme required'; end if;

  select id into v_country from ref.countries where upper(iso_alpha2::text)=upper(p_country_code);
  select id into v_family_provider from pim.attribute_families where entity_type='provider' and status='active' order by case when code='provider_default' then 0 else 1 end limit 1;
  select id into v_family_course from pim.attribute_families where entity_type='course' and status='active' order by case when code='course_default' then 0 else 1 end limit 1;
  if v_country is null then raise exception 'country seed missing: %',p_country_code; end if;

  for r in select value from jsonb_array_elements(coalesce(p_records,'[]'::jsonb)) loop
    v_provider:=null; v_course:=null; v_level:=null;
    v_pcode:=upper(nullif(trim(r->>'provider_code'),''));
    v_ccode:=upper(nullif(trim(r->>'course_code'),''));
    v_pname:=nullif(trim(r->>'provider_name'),'');
    v_cname:=nullif(trim(r->>'course_name'),'');
    v_level_name:=lower(coalesce(r->>'course_level',''));
    v_website:=nullif(trim(r->>'website'),'');
    v_city:=nullif(trim(r->>'city'),'');
    v_weeks:=case when (r->>'duration_weeks') ~ '^[0-9]+(\.[0-9]+)?$' then (r->>'duration_weeks')::numeric else null end;

    if v_pcode is null or v_pname is null then
      v_conflicts:=v_conflicts+1;
      continue;
    end if;

    v_provider_key := 'provider:'||v_scheme||':'||lower(regexp_replace(v_pcode,'[^a-zA-Z0-9]+','-','g'));

    select pr.provider_id into v_provider
    from catalogue.provider_registrations pr
    join catalogue.providers p on p.id=pr.provider_id
    where p.country_id=v_country
      and lower(pr.registration_scheme)=v_scheme
      and upper(pr.registration_code)=v_pcode
    order by pr.checked_at desc nulls last, pr.id
    limit 1;

    if v_provider is null then
      select p.id into v_provider
      from catalogue.providers p
      where p.country_id=v_country and p.stable_key=v_provider_key
      limit 1;

      if v_provider is null then
        insert into pim.entity_registry(entity_type,stable_key,family_id)
        values('provider',v_provider_key,v_family_provider)
        returning id into v_provider;

        insert into catalogue.providers(
          id,stable_key,canonical_name,display_name,country_id,website,primary_city,
          lifecycle_status,publication_status,canonical_source_id,last_verified_at
        ) values(
          v_provider,v_provider_key,v_pname,v_pname,v_country,v_website,v_city,
          'active','unpublished',p_source_id,now()
        );
        v_provider_created:=v_provider_created+1;
      else
        v_provider_linked:=v_provider_linked+1;
      end if;

      insert into catalogue.provider_registrations(
        provider_id,source_id,registration_scheme,registration_code,status,checked_at,evidence_id
      ) values(
        v_provider,p_source_id,v_scheme,v_pcode,'active',now(),p_evidence_id
      ) on conflict do nothing;
    else
      v_provider_existing:=v_provider_existing+1;
    end if;

    update catalogue.provider_registrations
      set source_id=p_source_id,status='active',checked_at=now(),evidence_id=coalesce(p_evidence_id,evidence_id)
    where provider_id=v_provider and lower(registration_scheme)=v_scheme and upper(registration_code)=v_pcode;

    update catalogue.providers
      set canonical_source_id=p_source_id,last_verified_at=now(),website=coalesce(website,v_website),
          primary_city=coalesce(primary_city,v_city),updated_at=now()
    where id=v_provider;

    if v_ccode is null or v_cname is null then continue; end if;

    v_course_key := 'course:'||v_scheme||':'||lower(regexp_replace(v_pcode,'[^a-zA-Z0-9]+','-','g'))||':'||lower(regexp_replace(v_ccode,'[^a-zA-Z0-9]+','-','g'));

    select cr.course_id into v_course
    from catalogue.course_registrations cr
    join catalogue.courses c on c.id=cr.course_id
    where c.provider_id=v_provider
      and lower(cr.scheme)=v_scheme
      and upper(cr.registration_code)=v_ccode
    order by cr.id
    limit 1;

    if v_course is null then
      select c.id into v_course
      from catalogue.courses c
      where c.provider_id=v_provider and c.stable_key=v_course_key
      limit 1;

      if v_course is null then
        insert into pim.entity_registry(entity_type,stable_key,family_id)
        values('course',v_course_key,v_family_course)
        returning id into v_course;

        insert into catalogue.courses(
          id,stable_key,provider_id,canonical_title,display_title,course_code,
          duration_value,duration_unit,lifecycle_status,publication_status,
          canonical_source_id,last_verified_at
        ) values(
          v_course,v_course_key,v_provider,v_cname,v_cname,v_ccode,
          v_weeks,case when v_weeks is not null then 'weeks' end,'active','unpublished',
          p_source_id,now()
        );
        v_course_created:=v_course_created+1;
      else
        v_course_linked:=v_course_linked+1;
      end if;

      insert into catalogue.course_registrations(
        course_id,scheme,registration_code,country_id,status,source_id,evidence_id
      ) values(
        v_course,v_scheme,v_ccode,v_country,'active',p_source_id,p_evidence_id
      ) on conflict do nothing;
    else
      v_course_existing:=v_course_existing+1;
    end if;

    select id into v_level from ref.study_levels where code=case
      when v_level_name like '%doctor%' or v_level_name like '%phd%' then 'doctorate'
      when v_level_name like '%master%' then 'masters'
      when v_level_name like '%graduate certificate%' then 'graduate_certificate'
      when v_level_name like '%graduate diploma%' then 'graduate_diploma'
      when v_level_name like '%bachelor%' then 'bachelor'
      when v_level_name like '%associate%' then 'associate_degree'
      when v_level_name like '%diploma%' then 'diploma'
      when v_level_name like '%certificate%' then 'certificate'
      when v_level_name like '%foundation%' then 'foundation'
      else null end;

    update catalogue.courses
      set study_level_id=coalesce(v_level,study_level_id),duration_value=coalesce(v_weeks,duration_value),
          duration_unit=case when v_weeks is not null then 'weeks' else duration_unit end,
          canonical_source_id=p_source_id,last_verified_at=now(),updated_at=now()
    where id=v_course;

    update catalogue.course_registrations
      set source_id=p_source_id,status='active',evidence_id=coalesce(p_evidence_id,evidence_id)
    where course_id=v_course and lower(scheme)=v_scheme and upper(registration_code)=v_ccode;
  end loop;

  return jsonb_build_object(
    'provider_created',v_provider_created,
    'provider_linked',v_provider_linked,
    'provider_existing',v_provider_existing,
    'course_created',v_course_created,
    'course_linked',v_course_linked,
    'course_existing',v_course_existing,
    'conflicts',v_conflicts,
    'records',jsonb_array_length(coalesce(p_records,'[]'::jsonb))
  );
end
$function$;

revoke all on function public.svc_layer1_apply_register_records(text,uuid,uuid,text,jsonb) from public, anon, authenticated;
grant execute on function public.svc_layer1_apply_register_records(text,uuid,uuid,text,jsonb) to service_role;
