do $$
declare v_system uuid; v_provider uuid; v_country uuid; v_source uuid;
begin
  select id into v_country from ref.countries where upper(iso_alpha2::text)='CA';
  select provider_id into v_provider from catalogue.provider_identifiers where country_id=v_country and lower(scheme)='ircc_dli' and upper(identifier)='O19396019469' order by is_primary desc,verified_at desc nulls last limit 1;
  if v_provider is null then raise exception 'verified Niagara IRCC DLI Provider missing'; end if;
  insert into integration.systems(code,name,system_type,base_url,status,config)
  values('ca_on_niagara_availability','Niagara College First-Party Program Availability','institutional_catalogue','https://www.niagaracollege.ca','active',jsonb_build_object('country','CA','province','ON','provider_dli','O19396019469','local_identity_field','published programme code','title_identity_allowed',false,'lifecycle_aware',true))
  on conflict (code) do update set name=excluded.name,system_type=excluded.system_type,base_url=excluded.base_url,status='active',config=integration.systems.config||excluded.config,updated_at=now()
  returning id into v_system;
  select id into v_source from pipeline.sources where system_id=v_system and provider_id=v_provider and url='https://www.niagaracollege.ca/enrolmentservices/program-availability/' limit 1;
  if v_source is null then
    insert into pipeline.sources(source_type,system_id,provider_id,country_id,url,label,trust_rank,status,metadata)
    values('institutional_catalogue',v_system,v_provider,v_country,'https://www.niagaracollege.ca/enrolmentservices/program-availability/','Niagara College first-party program availability',12,'active',jsonb_build_object('layer','1','country','CA','province','ON','provider_dli','O19396019469','coverage_role','first_party_course_identity_lifecycle_aware','course_identity_scheme','niagara_program_code','title_identity_allowed',false,'lifecycle_aware',true,'regional_validation_source','Ontario APS','apply_gate','bounded_uat'));
  else
    update pipeline.sources set source_type='institutional_catalogue',country_id=v_country,label='Niagara College first-party program availability',trust_rank=12,status='active',metadata=metadata||jsonb_build_object('layer','1','country','CA','province','ON','provider_dli','O19396019469','coverage_role','first_party_course_identity_lifecycle_aware','course_identity_scheme','niagara_program_code','title_identity_allowed',false,'lifecycle_aware',true,'regional_validation_source','Ontario APS','apply_gate','bounded_uat'),updated_at=now() where id=v_source;
  end if;
end $$;
create or replace function pipeline.trg_submit_pilot_edge_execution()
returns trigger language plpgsql security definer set search_path to 'pipeline','public'
as $function$
begin
 if new.function_name not in ('layer1-ca-on-college-programs','layer1-ca-algonquin-catalogue','layer1-ca-conestoga-catalogue','layer1-ca-fanshawe-pgwp','layer1-ca-mohawk-catalogue','layer1-ca-durham-programs','layer1-ca-niagara-catalogue') then new.status:='failed'; new.error_text:='function not allowlisted'; return new; end if;
 begin new.net_request_id:=pipeline.svc_pilot_invoke_edge(new.function_name,new.body); new.status:='submitted'; new.submitted_at:=now(); exception when others then new.status:='failed'; new.error_text:=sqlerrm; end;
 return new;
end $function$;
