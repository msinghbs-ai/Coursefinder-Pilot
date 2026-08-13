insert into integration.systems(code,name,system_type,base_url,status,config)
select 'ca_algonquin_catalogue','Algonquin College First-Party Programme Catalogue','institutional_catalogue','https://www.algonquincollege.com','active',
jsonb_build_object('country','CA','province','ON','provider_dli','O19358971022','catalogue_scope','AC Online programmes','acquisition_method','html','local_identity_field','published program code','title_identity_allowed',false,'canonical_identity_write',true)
where not exists(select 1 from integration.systems where code='ca_algonquin_catalogue');

insert into pipeline.sources(source_type,system_id,provider_id,country_id,url,label,trust_rank,status,metadata)
select 'institutional_catalogue',i.id,p.id,c.id,'https://www.algonquincollege.com/online/programs/list/all/','Algonquin College first-party programme catalogue',15,'active',
jsonb_build_object('layer','1','country','CA','province','ON','provider_dli','O19358971022','coverage_role','first_party_course_identity','course_identity_scheme','algonquin_program_code','title_identity_allowed',false,'regional_validation_source','Ontario APS','apply_gate','bounded_uat')
from integration.systems i
join ref.countries c on upper(c.iso_alpha2::text)='CA'
join catalogue.provider_identifiers pi on pi.country_id=c.id and lower(pi.scheme)='ircc_dli' and upper(pi.identifier)='O19358971022'
join catalogue.providers p on p.id=pi.provider_id
where i.code='ca_algonquin_catalogue'
and not exists(select 1 from pipeline.sources s where s.system_id=i.id and s.provider_id=p.id);