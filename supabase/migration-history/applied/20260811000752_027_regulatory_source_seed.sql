insert into integration.systems (code,name,system_type,base_url,status,config)
values
('au_cricos','Australia CRICOS','regulatory_dataset','https://data.gov.au/data/dataset/cricos','active',jsonb_build_object('acquisition_method','dataset_discovery','auth','none','authoritative',true,'coverage',jsonb_build_array('provider','course','location'),'live_register','https://cricos.education.gov.au/default.aspx','resource_strategy','resolve_current_export_from_dataset_page')),
('ca_ircc_dli','Canada IRCC Designated Learning Institutions','regulatory_web','https://www.canada.ca/en/immigration-refugees-citizenship/services/study-canada/study-permit/prepare/designated-learning-institutions-list.html','active',jsonb_build_object('acquisition_method','web_table','auth','none','authoritative',true,'coverage',jsonb_build_array('provider','campus','international_eligibility','pgwp_program_eligibility'),'full_course_catalogue',false)),
('de_hrk_hochschulkompass','Germany HRK Hochschulkompass','regulatory_web','https://www.hochschulkompass.hrk.de/home.html','active',jsonb_build_object('acquisition_method','web_discovery','auth','none','authoritative',true,'coverage',jsonb_build_array('provider','course'),'scope','state_and_state_recognised_higher_education','data_maintained_by','higher_education_institutions')),
('gb_ofs_register','UK Office for Students Register','regulatory_spreadsheet','https://www.officeforstudents.org.uk/for-providers/registering-with-the-ofs/guide-to-the-ofs-register/','active',jsonb_build_object('acquisition_method','spreadsheet_download','auth','none','authoritative',true,'coverage',jsonb_build_array('provider','regulatory_status'),'scope','England','full_uk_coverage',false)),
('gb_discover_uni','UK Discover Uni','regulatory_dataset','https://discoveruni.gov.uk/information-providers/','active',jsonb_build_object('acquisition_method','dataset_or_web','auth','none','authoritative',true,'coverage',jsonb_build_array('provider','undergraduate_course','course_outcomes'),'scope','United Kingdom','dataset_update','weekly')),
('ie_qqi_irq','Ireland QQI Irish Register of Qualifications','regulatory_web','https://www.qqi.ie/what-we-do/the-qualifications-system/irish-register-of-qualifications','active',jsonb_build_object('acquisition_method','register_web','auth','none','authoritative',true,'coverage',jsonb_build_array('provider','qualification','programme'),'scope','Ireland')),
('nz_nzqa','New Zealand NZQA Education Organisations','regulatory_web','https://www.nzqa.govt.nz/providers/index.do','active',jsonb_build_object('acquisition_method','register_web','auth','none','authoritative',true,'coverage',jsonb_build_array('provider','qualification','programme','code_of_practice'),'scope','New Zealand')),
('nz_education_counts','New Zealand Education Counts Tertiary Provider Directory','regulatory_download','https://www.educationcounts.govt.nz/directories/list-of-tertiary-providers','active',jsonb_build_object('acquisition_method','download','auth','none','authoritative',true,'coverage',jsonb_build_array('provider','institution_number','contact'),'scope','New Zealand','role','secondary_identity_source')),
('us_college_scorecard','US Department of Education College Scorecard','regulatory_api','https://api.data.gov/ed/collegescorecard/v1','active',jsonb_build_object('acquisition_method','api','auth','api_data_gov_key','secret_name','COLLEGE_SCORECARD_API_KEY','authoritative',true,'coverage',jsonb_build_array('provider','institution','field_of_study','cost','outcomes'),'full_course_catalogue',false,'endpoint','/schools'))
on conflict (code) do update set
  name=excluded.name,
  system_type=excluded.system_type,
  base_url=excluded.base_url,
  status=excluded.status,
  config=excluded.config,
  updated_at=now();

with desired(country_code,system_code,source_type,label,url,trust_rank,metadata) as (
 values
 ('AU','au_cricos','dataset','CRICOS Providers, Courses and Locations','https://data.gov.au/data/dataset/cricos',10,jsonb_build_object('coverage_role','primary','verified_on','2026-08-11')),
 ('CA','ca_ircc_dli','web','IRCC Designated Learning Institutions','https://www.canada.ca/en/immigration-refugees-citizenship/services/study-canada/study-permit/prepare/designated-learning-institutions-list.html',10,jsonb_build_object('coverage_role','primary_provider_identity','verified_on','2026-08-11')),
 ('DE','de_hrk_hochschulkompass','web','HRK Hochschulkompass','https://www.hochschulkompass.hrk.de/home.html',10,jsonb_build_object('coverage_role','primary','verified_on','2026-08-11')),
 ('GB','gb_ofs_register','spreadsheet','Office for Students Register','https://www.officeforstudents.org.uk/for-providers/registering-with-the-ofs/guide-to-the-ofs-register/',10,jsonb_build_object('coverage_role','primary_provider_regulatory','geographic_scope','England','verified_on','2026-08-11')),
 ('GB','gb_discover_uni','dataset','Discover Uni Dataset','https://discoveruni.gov.uk/information-providers/',20,jsonb_build_object('coverage_role','primary_course_data','geographic_scope','United Kingdom','verified_on','2026-08-11')),
 ('IE','ie_qqi_irq','web','Irish Register of Qualifications','https://www.qqi.ie/what-we-do/the-qualifications-system/irish-register-of-qualifications',10,jsonb_build_object('coverage_role','primary','verified_on','2026-08-11')),
 ('NZ','nz_nzqa','web','NZQA Education Organisations','https://www.nzqa.govt.nz/providers/index.do',10,jsonb_build_object('coverage_role','primary','verified_on','2026-08-11')),
 ('NZ','nz_education_counts','download','Education Counts Tertiary Providers Directory','https://www.educationcounts.govt.nz/directories/list-of-tertiary-providers',20,jsonb_build_object('coverage_role','secondary_identity','verified_on','2026-08-11')),
 ('US','us_college_scorecard','api','US College Scorecard Schools API','https://api.data.gov/ed/collegescorecard/v1/schools',10,jsonb_build_object('coverage_role','primary_provider_data','verified_on','2026-08-11'))
)
insert into pipeline.sources (source_type,system_id,provider_id,country_id,url,label,trust_rank,status,metadata)
select d.source_type,s.id,null,c.id,d.url,d.label,d.trust_rank,'active',d.metadata
from desired d
join ref.countries c on c.iso_alpha2=d.country_code
join integration.systems s on s.code=d.system_code
where not exists (
  select 1 from pipeline.sources x where x.country_id=c.id and x.provider_id is null and x.system_id=s.id
);

update pipeline.sources x
set status='active',updated_at=now()
from integration.systems s
where x.system_id=s.id and s.code in ('au_cricos','ca_ircc_dli','de_hrk_hochschulkompass','gb_ofs_register','gb_discover_uni','ie_qqi_irq','nz_nzqa','nz_education_counts','us_college_scorecard');
