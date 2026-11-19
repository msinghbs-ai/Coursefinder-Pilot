create or replace function public.svc_layer1_apply_cricos_records(p_source_id uuid, p_evidence_id uuid, p_records jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public','catalogue','pim','ref','pipeline'
as $function$
declare
  r jsonb; v_country uuid; v_provider uuid; v_course uuid; v_family_provider uuid; v_family_course uuid; v_level uuid;
  v_pmatches int; v_cmatches int; v_provider_created int:=0; v_course_created int:=0; v_provider_linked int:=0; v_course_linked int:=0; v_conflicts int:=0;
  v_pcode text; v_ccode text; v_pname text; v_cname text; v_level_name text; v_weeks numeric;
begin
  if current_user <> 'postgres' and coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  select id into v_country from ref.countries where iso_alpha2='AU';
  select id into v_family_provider from pim.attribute_families where entity_type='provider' and status='active' order by case when code='provider_default' then 0 else 1 end limit 1;
  select id into v_family_course from pim.attribute_families where entity_type='course' and status='active' order by case when code='course_default' then 0 else 1 end limit 1;
  if v_country is null then raise exception 'AU country seed missing'; end if;

  for r in select value from jsonb_array_elements(coalesce(p_records,'[]'::jsonb)) loop
    v_pcode:=upper(nullif(trim(r->>'provider_code'),'')); v_ccode:=upper(nullif(trim(r->>'course_code'),''));
    v_pname:=nullif(trim(r->>'provider_name'),''); v_cname:=nullif(trim(r->>'course_name'),''); v_level_name:=coalesce(r->>'course_level','');
    v_weeks:=case when (r->>'duration_weeks') ~ '^[0-9]+(\.[0-9]+)?$' then (r->>'duration_weeks')::numeric else null end;
    if v_pcode is null or v_pname is null then v_conflicts:=v_conflicts+1; continue; end if;

    select pr.provider_id into v_provider from catalogue.provider_registrations pr where lower(pr.registration_scheme)='cricos' and upper(pr.registration_code)=v_pcode order by pr.checked_at desc nulls last limit 1;
    if v_provider is null then
      select count(*), (array_agg(p.id order by p.id))[1]
      into v_pmatches,v_provider
      from catalogue.providers p
      where p.country_id=v_country and lower(regexp_replace(p.canonical_name,'[^a-z0-9]+','','g'))=lower(regexp_replace(v_pname,'[^a-z0-9]+','','g'));
      if v_pmatches=1 then
        insert into catalogue.provider_registrations(provider_id,source_id,registration_scheme,registration_code,status,checked_at,evidence_id)
        values(v_provider,p_source_id,'CRICOS',v_pcode,'active',now(),p_evidence_id) on conflict do nothing;
        update catalogue.providers set canonical_source_id=p_source_id,last_verified_at=now(),updated_at=now() where id=v_provider;
        v_provider_linked:=v_provider_linked+1;
      elsif v_pmatches=0 then
        insert into pim.entity_registry(entity_type,stable_key,family_id) values('provider','provider:cricos:'||lower(v_pcode),v_family_provider) returning id into v_provider;
        insert into catalogue.providers(id,stable_key,canonical_name,display_name,country_id,lifecycle_status,publication_status,canonical_source_id,last_verified_at)
        values(v_provider,'provider:cricos:'||lower(v_pcode),v_pname,v_pname,v_country,'active','unpublished',p_source_id,now());
        insert into catalogue.provider_registrations(provider_id,source_id,registration_scheme,registration_code,status,checked_at,evidence_id)
        values(v_provider,p_source_id,'CRICOS',v_pcode,'active',now(),p_evidence_id);
        v_provider_created:=v_provider_created+1;
      else v_conflicts:=v_conflicts+1; v_provider:=null; end if;
    else
      update catalogue.provider_registrations set source_id=p_source_id,status='active',checked_at=now(),evidence_id=p_evidence_id where provider_id=v_provider and lower(registration_scheme)='cricos' and upper(registration_code)=v_pcode;
      update catalogue.providers set canonical_source_id=p_source_id,last_verified_at=now(),updated_at=now() where id=v_provider;
    end if;

    if v_provider is null or v_ccode is null or v_cname is null then continue; end if;
    v_course:=null;
    select cr.course_id into v_course from catalogue.course_registrations cr where lower(cr.scheme)='cricos' and upper(cr.registration_code)=v_ccode order by cr.id limit 1;
    if v_course is null then
      select count(*), (array_agg(c.id order by c.id))[1]
      into v_cmatches,v_course
      from catalogue.courses c
      where c.provider_id=v_provider and lower(regexp_replace(c.canonical_title,'[^a-z0-9]+','','g'))=lower(regexp_replace(v_cname,'[^a-z0-9]+','','g'));
      if v_cmatches=1 then
        insert into catalogue.course_registrations(course_id,scheme,registration_code,country_id,status,source_id,evidence_id)
        values(v_course,'CRICOS',v_ccode,v_country,'active',p_source_id,p_evidence_id) on conflict do nothing;
        v_course_linked:=v_course_linked+1;
      elsif v_cmatches=0 then
        insert into pim.entity_registry(entity_type,stable_key,family_id) values('course','course:cricos:'||lower(v_ccode),v_family_course) returning id into v_course;
        insert into catalogue.courses(id,stable_key,provider_id,canonical_title,display_title,course_code,duration_value,duration_unit,lifecycle_status,publication_status,canonical_source_id,last_verified_at)
        values(v_course,'course:cricos:'||lower(v_ccode),v_provider,v_cname,v_cname,v_ccode,v_weeks,case when v_weeks is not null then 'weeks' end,'active','unpublished',p_source_id,now());
        insert into catalogue.course_registrations(course_id,scheme,registration_code,country_id,status,source_id,evidence_id)
        values(v_course,'CRICOS',v_ccode,v_country,'active',p_source_id,p_evidence_id);
        v_course_created:=v_course_created+1;
      else v_conflicts:=v_conflicts+1; v_course:=null; end if;
    end if;
    if v_course is not null then
      select id into v_level from ref.study_levels where code=case
        when lower(v_level_name) like '%doctor%' or lower(v_level_name) like '%phd%' then 'doctorate'
        when lower(v_level_name) like '%master%' then 'masters'
        when lower(v_level_name) like '%graduate certificate%' then 'graduate_certificate'
        when lower(v_level_name) like '%graduate diploma%' then 'graduate_diploma'
        when lower(v_level_name) like '%bachelor%' then 'bachelor'
        when lower(v_level_name) like '%associate%' then 'associate_degree'
        when lower(v_level_name) like '%diploma%' then 'diploma'
        when lower(v_level_name) like '%certificate%' then 'certificate'
        when lower(v_level_name) like '%foundation%' then 'foundation' else null end;
      update catalogue.courses set study_level_id=coalesce(v_level,study_level_id), duration_value=coalesce(v_weeks,duration_value), duration_unit=case when v_weeks is not null then 'weeks' else duration_unit end, canonical_source_id=p_source_id,last_verified_at=now(),updated_at=now() where id=v_course;
      update catalogue.course_registrations set source_id=p_source_id,status='active',evidence_id=p_evidence_id where course_id=v_course and lower(scheme)='cricos' and upper(registration_code)=v_ccode;
    end if;
  end loop;
  return jsonb_build_object('provider_created',v_provider_created,'provider_linked',v_provider_linked,'course_created',v_course_created,'course_linked',v_course_linked,'conflicts',v_conflicts,'records',jsonb_array_length(coalesce(p_records,'[]'::jsonb)));
end $function$;
