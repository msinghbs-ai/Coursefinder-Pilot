-- Canada dual-authority identity contract
-- Provider business identity: IRCC DLI only.
-- Course business identity: deterministic UUIDv5(DLI + namespaced stable local programme key).
-- Provincial/classification codes such as APS/MTCU/CIP are validation metadata only.
-- Titles are mutable metadata and never participate in identity.

create or replace function public.svc_layer1_apply_scoped_course_records(
  p_country_code text,
  p_provider_source_id uuid,
  p_course_source_id uuid,
  p_evidence_id uuid,
  p_provider_scheme text,
  p_course_scheme text,
  p_records jsonb
) returns jsonb
language plpgsql
security definer
set search_path to 'public','catalogue','pim','ref','pipeline','extensions'
as $function$
declare
  r jsonb; v_country uuid; v_provider uuid; v_course uuid;
  v_family_provider uuid; v_family_course uuid;
  v_pcode text; v_ccode text; v_pname text; v_cname text;
  v_provider_key text; v_course_key text; v_course_identity_name text;
  v_provider_created int:=0; v_provider_existing int:=0;
  v_course_created int:=0; v_course_existing int:=0; v_conflicts int:=0;
  v_reg_scheme text; v_reg_code text;
begin
  if lower(coalesce(current_setting('request.jwt.claim.role', true),'')) <> 'service_role' and session_user <> 'postgres' then raise exception 'service_role required'; end if;
  if nullif(trim(p_provider_scheme),'') is null or nullif(trim(p_course_scheme),'') is null then raise exception 'provider and course identity schemes are required'; end if;
  if upper(p_country_code)='CA' and lower(trim(p_provider_scheme)) <> 'ircc_dli' then raise exception 'Canada Provider identity must use IRCC DLI'; end if;
  if upper(p_country_code)='CA' and lower(trim(p_course_scheme)) in ('on_aps','aps','mtcu','cip','cip_2021') then raise exception 'Canada Course base identity must use a stable local programme key; provincial/classification identifiers are validation metadata only'; end if;

  select id into v_country from ref.countries where upper(iso_alpha2::text)=upper(p_country_code);
  if v_country is null then raise exception 'country seed missing: %', p_country_code; end if;
  select id into v_family_provider from pim.attribute_families where entity_type='provider' and status='active' order by case when code='provider_default' then 0 else 1 end limit 1;
  select id into v_family_course from pim.attribute_families where entity_type='course' and status='active' order by case when code='course_default' then 0 else 1 end limit 1;

  for r in select value from jsonb_array_elements(coalesce(p_records,'[]'::jsonb)) loop
    v_pcode:=upper(nullif(trim(r->>'provider_code'),''));
    v_ccode:=nullif(trim(coalesce(r->>'local_program_id',r->>'course_code')),'');
    v_pname:=nullif(trim(r->>'provider_name'),'');
    v_cname:=nullif(trim(coalesce(r->>'course_title',r->>'course_name')),'');
    v_reg_scheme:=lower(nullif(trim(r->>'regional_reg_scheme'),''));
    v_reg_code:=nullif(trim(r->>'regional_reg_code'),'');
    if v_pcode is null or v_pname is null or v_ccode is null or v_cname is null then v_conflicts:=v_conflicts+1; continue; end if;

    v_provider_key:='provider:'||lower(p_country_code)||':'||lower(p_provider_scheme)||':'||lower(regexp_replace(v_pcode,'[^a-zA-Z0-9]+','-','g'));
    select pi.provider_id into v_provider from catalogue.provider_identifiers pi where pi.country_id=v_country and lower(pi.scheme)=lower(p_provider_scheme) and upper(pi.identifier)=v_pcode order by pi.is_primary desc, pi.verified_at desc nulls last limit 1;
    if v_provider is null then select id into v_provider from catalogue.providers where stable_key=v_provider_key limit 1; end if;
    if v_provider is null then
      insert into pim.entity_registry(entity_type,stable_key,family_id) values('provider',v_provider_key,v_family_provider) returning id into v_provider;
      insert into catalogue.providers(id,stable_key,canonical_name,display_name,country_id,lifecycle_status,publication_status,canonical_source_id,last_verified_at) values(v_provider,v_provider_key,v_pname,v_pname,v_country,'active','unpublished',p_provider_source_id,now());
      v_provider_created:=v_provider_created+1;
    else
      update catalogue.providers set canonical_name=v_pname,display_name=v_pname,canonical_source_id=p_provider_source_id,last_verified_at=now(),updated_at=now() where id=v_provider;
      v_provider_existing:=v_provider_existing+1;
    end if;
    insert into catalogue.provider_identifiers(provider_id,scheme,identifier,country_id,issuing_authority,is_primary,source_id,evidence_id,verified_at) values(v_provider,lower(p_provider_scheme),v_pcode,v_country,'IRCC',true,p_provider_source_id,p_evidence_id,now()) on conflict (provider_id,scheme,identifier) do update set source_id=excluded.source_id,evidence_id=excluded.evidence_id,verified_at=excluded.verified_at,is_primary=true;
    insert into catalogue.provider_registrations(provider_id,source_id,registration_scheme,registration_code,status,checked_at,evidence_id) values(v_provider,p_provider_source_id,lower(p_provider_scheme),v_pcode,'active',now(),p_evidence_id) on conflict do nothing;

    v_course_key:='course:'||lower(p_country_code)||':'||lower(p_provider_scheme)||':'||lower(regexp_replace(v_pcode,'[^a-zA-Z0-9]+','-','g'))||':'||lower(p_course_scheme)||':'||lower(regexp_replace(v_ccode,'[^a-zA-Z0-9]+','-','g'));
    v_course_identity_name:='coursefinder:'||lower(p_country_code)||':'||lower(v_pcode)||':'||lower(p_course_scheme)||':'||lower(v_ccode);
    select ci.course_id into v_course from catalogue.course_identifiers ci where ci.provider_id=v_provider and lower(ci.scheme)=lower(p_course_scheme) and ci.identifier=v_ccode limit 1;
    if v_course is null then select id into v_course from catalogue.courses where stable_key=v_course_key limit 1; end if;
    if v_course is null then
      if upper(p_country_code)='CA' then
        v_course:=extensions.uuid_generate_v5(extensions.uuid_ns_url(),v_course_identity_name);
        insert into pim.entity_registry(id,entity_type,stable_key,family_id) values(v_course,'course',v_course_key,v_family_course);
      else
        insert into pim.entity_registry(entity_type,stable_key,family_id) values('course',v_course_key,v_family_course) returning id into v_course;
      end if;
      insert into catalogue.courses(id,stable_key,provider_id,canonical_title,display_title,course_code,lifecycle_status,publication_status,canonical_source_id,last_verified_at) values(v_course,v_course_key,v_provider,v_cname,v_cname,v_ccode,'active','unpublished',p_course_source_id,now());
      v_course_created:=v_course_created+1;
    else
      update catalogue.courses set canonical_title=v_cname,display_title=v_cname,course_code=v_ccode,canonical_source_id=p_course_source_id,last_verified_at=now(),updated_at=now() where id=v_course;
      v_course_existing:=v_course_existing+1;
    end if;
    insert into catalogue.course_identifiers(course_id,provider_id,scheme,identifier,country_id,issuing_authority,is_primary,source_id,evidence_id,verified_at) values(v_course,v_provider,lower(p_course_scheme),v_ccode,v_country,coalesce(nullif(trim(r->>'issuing_authority'),''),'Authoritative local course source'),true,p_course_source_id,p_evidence_id,now()) on conflict (provider_id,scheme,identifier) do update set course_id=excluded.course_id,source_id=excluded.source_id,evidence_id=excluded.evidence_id,verified_at=excluded.verified_at,is_primary=true;
    if v_reg_scheme is not null and v_reg_code is not null then insert into catalogue.course_registrations(course_id,scheme,registration_code,country_id,status,source_id,evidence_id) values(v_course,v_reg_scheme,v_reg_code,v_country,'active',p_course_source_id,p_evidence_id) on conflict do nothing; end if;
  end loop;
  return jsonb_build_object('provider_created',v_provider_created,'provider_existing',v_provider_existing,'course_created',v_course_created,'course_existing',v_course_existing,'conflicts',v_conflicts,'records',jsonb_array_length(coalesce(p_records,'[]'::jsonb)),'identity_contract',case when upper(p_country_code)='CA' then 'provider=IRCC_DLI; course=UUIDv5(DLI+local_source_key); regional_codes=validation_metadata; title=mutable' else 'country_scoped' end);
end $function$;

revoke all on function public.svc_layer1_apply_scoped_course_records(text,uuid,uuid,uuid,text,text,jsonb) from public, anon, authenticated;
grant execute on function public.svc_layer1_apply_scoped_course_records(text,uuid,uuid,uuid,text,text,jsonb) to service_role;

update pipeline.sources set metadata = metadata || jsonb_build_object('coverage_role','provincial_course_validation','identity_scheme',null,'course_identity_role','validation_only','regional_registration_scheme','on_aps','base_course_identity_required','verified DLI + stable institutional/source-local programme key','title_identity_allowed',false,'verified_on','2026-08-12') where label='Ontario public college programmes / APS' and country_id=(select id from ref.countries where upper(iso_alpha2::text)='CA');
update integration.systems set config = config || jsonb_build_object('course_identity','provider DLI + stable institutional/source-local programme key','regional_registration','APS','aps_role','validation_metadata_only','title_identity_allowed',false) where code='ca_on_public_college_programs';
