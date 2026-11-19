do $$
declare v_system uuid; v_provider uuid; v_country uuid; v_source uuid;
begin
 select id into v_country from ref.countries where upper(iso_alpha2::text)='CA';
 select provider_id into v_provider from catalogue.provider_identifiers where country_id=v_country and lower(scheme)='ircc_dli' and upper(identifier)='O19385946782' order by is_primary desc,verified_at desc nulls last limit 1;
 if v_provider is null then raise exception 'verified Sheridan IRCC DLI Provider missing'; end if;
 insert into integration.systems(code,name,system_type,base_url,status,config)
 values('ca_on_sheridan_sitecore_programs','Sheridan College First-Party Sitecore Program Search','institutional_catalogue','https://www.sheridancollege.ca','active',jsonb_build_object('country','CA','province','ON','provider_dli','O19385946782','local_identity_field','Sitecore program item Id','title_identity_allowed',false,'lifecycle_aware',true))
 on conflict(code) do update set name=excluded.name,system_type=excluded.system_type,base_url=excluded.base_url,status='active',config=integration.systems.config||excluded.config,updated_at=now() returning id into v_system;
 select id into v_source from pipeline.sources where system_id=v_system and provider_id=v_provider limit 1;
 if v_source is null then
   insert into pipeline.sources(source_type,system_id,provider_id,country_id,url,label,trust_rank,status,metadata)
   values('institutional_catalogue',v_system,v_provider,v_country,'https://www.sheridancollege.ca/sxa/search/results/','Sheridan College first-party Sitecore program search',12,'active',jsonb_build_object('layer','1','country','CA','province','ON','provider_dli','O19385946782','coverage_role','first_party_course_identity_lifecycle_aware','course_identity_scheme','sheridan_program_item_id','title_identity_allowed',false,'lifecycle_aware',true,'active_facet','Program active','regional_validation_source','Ontario APS','apply_gate','bounded_uat'));
 else
   update pipeline.sources set country_id=v_country,url='https://www.sheridancollege.ca/sxa/search/results/',label='Sheridan College first-party Sitecore program search',trust_rank=12,status='active',metadata=metadata||jsonb_build_object('layer','1','country','CA','province','ON','provider_dli','O19385946782','coverage_role','first_party_course_identity_lifecycle_aware','course_identity_scheme','sheridan_program_item_id','title_identity_allowed',false,'lifecycle_aware',true,'active_facet','Program active','regional_validation_source','Ontario APS','apply_gate','bounded_uat'),updated_at=now() where id=v_source;
 end if;
end $$;
