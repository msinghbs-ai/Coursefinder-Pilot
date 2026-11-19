do $$
declare
  v_country uuid;
  v_system uuid;
  v_source uuid;
  v_missing int;
begin
  select id into v_country from ref.countries where iso_alpha2='CA';
  if v_country is null then raise exception 'CA country seed missing'; end if;

  insert into integration.systems(code,name,system_type,base_url,status,config)
  values(
    'ca_bc_epbc_programs',
    'EducationPlannerBC provincial post-secondary programme catalogue',
    'provincial_application_data_exchange_hub',
    'https://www.educationplannerbc.ca',
    'active',
    jsonb_build_object(
      'country','CA','jurisdiction','BC','authority','EducationPlannerBC',
      'authority_basis','Province of British Columbia directs users to EducationPlannerBC to find authorised post-secondary programs; EPBC operates the provincial post-secondary application/data exchange hub',
      'acquisition_method','server-rendered Next.js __NEXT_DATA__ searchResults',
      'provider_identity','approved EPBC institution UUID -> IRCC DLI crosswalk',
      'course_identity_scheme','bc_epbc_program_guid',
      'course_identity','stable EPBC programme GUID',
      'title_identity_allowed',false,
      'coverage_scope','24 current public-postsecondary institutions with verified IRCC DLI mappings; NVIT excluded because absent from current live IRCC register'
    )
  )
  on conflict(code) do update set
    name=excluded.name,system_type=excluded.system_type,base_url=excluded.base_url,status='active',config=excluded.config,updated_at=now()
  returning id into v_system;
  if v_system is null then select id into v_system from integration.systems where code='ca_bc_epbc_programs'; end if;

  select id into v_source from pipeline.sources where system_id=v_system and country_id=v_country and provider_id is null order by created_at limit 1;
  if v_source is null then
    insert into pipeline.sources(source_type,system_id,provider_id,country_id,url,label,trust_rank,status,metadata)
    values(
      'provincial_catalogue',v_system,null,v_country,'https://www.educationplannerbc.ca/institutions',
      'EducationPlannerBC public post-secondary programme catalogue',98,'active',
      jsonb_build_object('layer','1','country','CA','province','BC','jurisdiction','BC','coverage_role','provincial_public_postsecondary_course_identity','course_identity_scheme','bc_epbc_program_guid','provider_source_key','epbc_institution_uuid','title_identity_allowed',false,'raw_evidence_private',true)
    ) returning id into v_source;
  else
    update pipeline.sources set url='https://www.educationplannerbc.ca/institutions',label='EducationPlannerBC public post-secondary programme catalogue',trust_rank=98,status='active',metadata=metadata||jsonb_build_object('layer','1','country','CA','province','BC','jurisdiction','BC','coverage_role','provincial_public_postsecondary_course_identity','course_identity_scheme','bc_epbc_program_guid','provider_source_key','epbc_institution_uuid','title_identity_allowed',false,'raw_evidence_private',true),updated_at=now() where id=v_source;
  end if;

  with x(epbc_id,source_name,dli) as (values
    ('5B7C9834-D996-4A2F-A947-8F713AD8019D','British Columbia Institute of Technology','O19330128542'),
    ('587482D5-F5F5-418A-9476-31C24C864958','Camosun College','O19361235542'),
    ('25B97516-B4DE-4F58-A0F0-AA04FE3487FC','Capilano University','O19280078102'),
    ('F5FBD3BD-7C2C-4A12-9951-A8E07A787EAE','Coast Mountain College','O110095977911'),
    ('E1DDD25D-7358-4BDE-9DFE-087296D7AD8D','College of New Caledonia','O19360977332'),
    ('BBDE561E-7C33-459E-9228-D053B52BDF19','College of the Rockies','O19377233362'),
    ('F11BB76F-1540-4C02-8CD1-3E81D533C3A4','Douglas College','O19360973702'),
    ('B3FDF911-0056-49F3-BE88-4F371BD3D64F','Emily Carr University of Art + Design','O19361259712'),
    ('09EFCCC5-3BC7-496B-A120-B8B21CD82691','Justice Institute of British Columbia','O19394941140'),
    ('441050C1-8839-4AE9-9693-795E4E4FA875','Kwantlen Polytechnic University','O19350676872'),
    ('48ED5338-4D90-4A22-A97D-CB9659487689','Langara College','O19319074622'),
    ('5C929328-0FCA-455A-BF60-4E24782876E0','North Island College','O19301182602'),
    ('BA6DA940-F10F-411B-858A-C3B567C7E769','Northern Lights College','O19395299444'),
    ('14E1A820-68DA-473F-AA59-5DAB39813952','Okanagan College','O19395299488'),
    ('BD3CFCF3-826F-4538-9FC4-2138A003A9E2','Royal Roads University','O19330635812'),
    ('732C29EA-3F8F-4000-9EA8-88FC296AF049','Selkirk College','O19360990072'),
    ('155B49CF-5B64-4A39-A197-643A6A0762E0','Simon Fraser University','O18781994282'),
    ('279CCE3F-3E9F-40FA-83B2-B43B456CABF0','Thompson Rivers University','O19395299610'),
    ('539E2475-0215-44C3-A4D0-EA806CF9AB9F','University of British Columbia','O19330231062'),
    ('C119CDC4-DE88-42AB-84FE-685E227D72C0','University of Northern British Columbia','O19283889692'),
    ('50447012-FBFD-45CA-BF81-BA110B7C3004','University of the Fraser Valley','O19395299642'),
    ('196EE363-A5A3-4C47-8FDB-2E8DA8DBE2E9','University of Victoria','O19280533442'),
    ('6C0E98F4-97D4-44BD-AF8A-E87B8FD48418','Vancouver Community College','O19279717512'),
    ('239AAB57-4C3D-4890-907A-1C7D0F52CA29','Vancouver Island University','O19395299688')
  ), resolved as (
    select x.*,pi.provider_id
    from x left join catalogue.provider_identifiers pi
      on pi.country_id=v_country and lower(pi.scheme)='ircc_dli' and upper(pi.identifier)=upper(x.dli)
  )
  select count(*) filter(where provider_id is null) into v_missing from resolved;
  if v_missing<>0 then raise exception 'BC EPBC DLI crosswalk has % unresolved Providers',v_missing; end if;

  with x(epbc_id,source_name,dli) as (values
    ('5B7C9834-D996-4A2F-A947-8F713AD8019D','British Columbia Institute of Technology','O19330128542'),('587482D5-F5F5-418A-9476-31C24C864958','Camosun College','O19361235542'),('25B97516-B4DE-4F58-A0F0-AA04FE3487FC','Capilano University','O19280078102'),('F5FBD3BD-7C2C-4A12-9951-A8E07A787EAE','Coast Mountain College','O110095977911'),('E1DDD25D-7358-4BDE-9DFE-087296D7AD8D','College of New Caledonia','O19360977332'),('BBDE561E-7C33-459E-9228-D053B52BDF19','College of the Rockies','O19377233362'),('F11BB76F-1540-4C02-8CD1-3E81D533C3A4','Douglas College','O19360973702'),('B3FDF911-0056-49F3-BE88-4F371BD3D64F','Emily Carr University of Art + Design','O19361259712'),('09EFCCC5-3BC7-496B-A120-B8B21CD82691','Justice Institute of British Columbia','O19394941140'),('441050C1-8839-4AE9-9693-795E4E4FA875','Kwantlen Polytechnic University','O19350676872'),('48ED5338-4D90-4A22-A97D-CB9659487689','Langara College','O19319074622'),('5C929328-0FCA-455A-BF60-4E24782876E0','North Island College','O19301182602'),('BA6DA940-F10F-411B-858A-C3B567C7E769','Northern Lights College','O19395299444'),('14E1A820-68DA-473F-AA59-5DAB39813952','Okanagan College','O19395299488'),('BD3CFCF3-826F-4538-9FC4-2138A003A9E2','Royal Roads University','O19330635812'),('732C29EA-3F8F-4000-9EA8-88FC296AF049','Selkirk College','O19360990072'),('155B49CF-5B64-4A39-A197-643A6A0762E0','Simon Fraser University','O18781994282'),('279CCE3F-3E9F-40FA-83B2-B43B456CABF0','Thompson Rivers University','O19395299610'),('539E2475-0215-44C3-A4D0-EA806CF9AB9F','University of British Columbia','O19330231062'),('C119CDC4-DE88-42AB-84FE-685E227D72C0','University of Northern British Columbia','O19283889692'),('50447012-FBFD-45CA-BF81-BA110B7C3004','University of the Fraser Valley','O19395299642'),('196EE363-A5A3-4C47-8FDB-2E8DA8DBE2E9','University of Victoria','O19280533442'),('6C0E98F4-97D4-44BD-AF8A-E87B8FD48418','Vancouver Community College','O19279717512'),('239AAB57-4C3D-4890-907A-1C7D0F52CA29','Vancouver Island University','O19395299688')
  ), resolved as (
    select x.*,pi.provider_id from x join catalogue.provider_identifiers pi on pi.country_id=v_country and lower(pi.scheme)='ircc_dli' and upper(pi.identifier)=upper(x.dli)
  )
  insert into pipeline.source_provider_mappings(source_id,source_entity_key,source_entity_name,provider_id,match_method,match_confidence,status,verified_at,metadata)
  select v_source,upper(epbc_id),source_name,provider_id,'governance_approved_epbc_uuid_to_ircc_dli',1.0,'verified',now(),jsonb_build_object('epbc_id',upper(epbc_id),'ircc_dli',dli,'identity_power','EPBC UUID and IRCC DLI only; names are descriptive evidence','jurisdiction','BC') from resolved
  on conflict(source_id,source_entity_key) do update set source_entity_name=excluded.source_entity_name,provider_id=excluded.provider_id,match_method=excluded.match_method,match_confidence=excluded.match_confidence,status='verified',verified_at=now(),metadata=excluded.metadata,updated_at=now();

  insert into pipeline.ca_source_qualifications(source_id,jurisdiction_code,authority_role,provider_identity_scheme,course_identity_scheme,stable_program_id_proof,provider_dli_mapping_status,runtime_fetch_status,evidence_status,dry_run_status,apply_status,idempotency_status,integrity_status,performance_status,coverage_scope,notes,metadata)
  values(
    v_source,'BC','provincial post-secondary application and data-exchange hub endorsed by Province of British Columbia','ircc_dli','bc_epbc_program_guid',
    'Programme search results expose a stable GUID independent of title-derived slug; first-page audit shows 20/20 unique GUIDs for every participating institution.',
    'verified_24_epbc_uuid_to_ircc_dli','pass','pending','pending','pending','pending','pending','pending',
    '24 current DLI-mapped B.C. public post-secondary institutions; 4,115 current EPBC programme records across 215 deterministic pages. NVIT excluded because current live IRCC register contains no NVIT row.',
    'Runtime Provider resolution uses verified EPBC institution UUID crosswalk only. Names and slugs have zero identity power. Royal Roads is included from EPBC public institution listing despite a source public-flag anomaly.',
    jsonb_build_object('mapped_institutions',24,'audited_programmes',4115,'audited_pages',215,'results_per_page',20,'course_identity','EPBC programme GUID','provider_source_identity','EPBC institution UUID','title_identity_allowed',false,'nvit_excluded_current_ircc',true,'coverage_complete_for_jurisdiction',false)
  )
  on conflict(source_id) do update set jurisdiction_code=excluded.jurisdiction_code,authority_role=excluded.authority_role,provider_identity_scheme=excluded.provider_identity_scheme,course_identity_scheme=excluded.course_identity_scheme,stable_program_id_proof=excluded.stable_program_id_proof,provider_dli_mapping_status=excluded.provider_dli_mapping_status,runtime_fetch_status=excluded.runtime_fetch_status,coverage_scope=excluded.coverage_scope,notes=excluded.notes,metadata=pipeline.ca_source_qualifications.metadata||excluded.metadata,updated_at=now();
end $$;
