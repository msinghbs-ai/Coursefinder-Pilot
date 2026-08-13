do $$
declare
  v_provider uuid;
  v_system uuid;
begin
  select pi.provider_id into v_provider
  from catalogue.provider_identifiers pi
  join ref.countries c on c.id=pi.country_id
  where upper(c.iso_alpha2::text)='CA' and lower(pi.scheme)='ircc_dli' and upper(pi.identifier)='O19376045902'
  order by pi.is_primary desc, pi.verified_at desc nulls last limit 1;
  if v_provider is null then raise exception 'Mohawk IRCC DLI Provider missing'; end if;

  insert into integration.systems(code,name,system_type,base_url,status,config)
  values('ca_on_mohawk_catalogue','Mohawk College Open Programme Catalogue','institutional_catalogue','https://www.mohawkcollege.ca','active',jsonb_build_object(
    'country','CA','province','ON','provider_dli','O19376045902','catalogue_scope','current open programmes',
    'acquisition_method','html','local_identity_field','published programme code','title_identity_allowed',false,'canonical_identity_write',true))
  on conflict (code) do update set name=excluded.name,system_type=excluded.system_type,base_url=excluded.base_url,status='active',config=excluded.config,updated_at=now()
  returning id into v_system;

  insert into pipeline.sources(system_id,provider_id,source_type,url,label,trust_rank,status,metadata)
  values(v_system,v_provider,'institutional_catalogue','https://www.mohawkcollege.ca/programs/search?filter-field-program-status=open','Mohawk College current open programme catalogue',15,'active',jsonb_build_object(
    'layer','1','country','CA','province','ON','provider_dli','O19376045902','coverage_role','first_party_course_identity',
    'catalogue_coverage','current_open_programmes','course_identity_scheme','mohawk_program_code','title_identity_allowed',false,
    'regional_validation_source','Ontario APS','apply_gate','bounded_uat'))
  on conflict do nothing;
end $$;
