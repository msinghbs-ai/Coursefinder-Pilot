insert into integration.systems(code,name,system_type,base_url,status,config)
select 'ca_on_fanshawe_pgwp','Fanshawe College First-Party PGWP Programmes','first_party_catalogue','https://www.fanshawec.ca','active',jsonb_build_object(
 'country','CA','province','ON','provider_dli','O19361039982','course_identity_scheme','fanshawe_program_code',
 'identity_contract','verified DLI + stable institutional programme code','title_identity_allowed',false,
 'acquisition_method','official_server_rendered_html_table','coverage',jsonb_build_array('course_identity','course_title','credential','cip'),
 'catalogue_coverage','partial_pgwp_aligned_only')
where not exists(select 1 from integration.systems where code='ca_on_fanshawe_pgwp');

insert into pipeline.sources(source_type,system_id,provider_id,country_id,url,label,trust_rank,status,metadata)
select 'first_party_programme',i.id,p.id,c.id,
 'https://www.fanshawec.ca/international/applicants/international-programs/pgwp-programs',
 'Fanshawe College PGWP-aligned first-party programme codes',10,'active',jsonb_build_object(
 'layer','1','country','CA','province','ON','provider_dli','O19361039982','coverage_role','first_party_course_identity_partial',
 'course_identity_scheme','fanshawe_program_code','title_identity_allowed',false,'regional_validation_source','Ontario APS',
 'catalogue_coverage','partial_pgwp_aligned_only','apply_gate','bounded_uat')
from integration.systems i
join ref.countries c on upper(c.iso_alpha2::text)='CA'
join catalogue.provider_identifiers pi on pi.country_id=c.id and lower(pi.scheme)='ircc_dli' and upper(pi.identifier)='O19361039982'
join catalogue.providers p on p.id=pi.provider_id
where i.code='ca_on_fanshawe_pgwp'
and not exists(select 1 from pipeline.sources s where s.system_id=i.id and s.provider_id=p.id);