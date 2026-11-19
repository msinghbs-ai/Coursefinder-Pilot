do $$
declare v_gb uuid; v_de uuid; v_sys uuid;
begin
 select id into v_gb from ref.countries where iso_alpha2='GB';
 select id into v_de from ref.countries where iso_alpha2='DE';
 insert into integration.systems(code,name,system_type,base_url,status,config)
 values('gb_ukvi_student_sponsors','UKVI Student Sponsor Register','regulatory_register','https://www.gov.uk/government/publications/register-of-licensed-sponsors-students','active',jsonb_build_object('acquisition_method','spreadsheet_download','coverage',jsonb_build_array('provider','international_student_sponsor_eligibility'),'auth','none'))
 on conflict(code) do update set name=excluded.name,system_type=excluded.system_type,base_url=excluded.base_url,status='active',config=excluded.config
 returning id into v_sys;
 if not exists(select 1 from pipeline.sources where country_id=v_gb and provider_id is null and system_id=v_sys) then
   insert into pipeline.sources(country_id,system_id,source_type,label,url,trust_rank,status,metadata)
   values(v_gb,v_sys,'spreadsheet_download','UKVI Register of Licensed Student Sponsors','https://www.gov.uk/government/publications/register-of-licensed-sponsors-students',5,'active','{}'::jsonb);
 end if;

 insert into integration.systems(code,name,system_type,base_url,status,config)
 values('de_daad_programmes','DAAD International Programmes','official_catalogue_api','https://www2.daad.de/deutschland/studienangebote/international-programmes/en/','active',jsonb_build_object('acquisition_method','api','coverage',jsonb_build_array('provider','course','programme'),'auth','none','api_url','https://www2.daad.de/deutschland/studienangebote/international-programmes/api/solr'))
 on conflict(code) do update set name=excluded.name,system_type=excluded.system_type,base_url=excluded.base_url,status='active',config=excluded.config
 returning id into v_sys;
 if not exists(select 1 from pipeline.sources where country_id=v_de and provider_id is null and system_id=v_sys) then
   insert into pipeline.sources(country_id,system_id,source_type,label,url,trust_rank,status,metadata)
   values(v_de,v_sys,'api','DAAD International Programmes','https://www2.daad.de/deutschland/studienangebote/international-programmes/en/',20,'active','{}'::jsonb);
 end if;
end $$;
