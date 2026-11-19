do $$
declare
  v_country uuid;
  v_system uuid;
  v_source uuid;
  v_url text := 'https://cdn-contenu.quebec.ca/cdn-contenu/enseignement-superieur/EtudierauQuebec/PTPD-tableau-programmes-etudes-universitaire-20-credits.pdf';
begin
  select id into v_country from ref.countries where iso_alpha2='CA';
  if v_country is null then raise exception 'CA country seed missing'; end if;

  insert into integration.systems(code,name,system_type,base_url,status,config)
  values(
    'ca_qc_mes_university_programs',
    'Quebec MES current university non-degree programme table',
    'provincial_regulator',
    'https://www.quebec.ca',
    'active',
    jsonb_build_object(
      'country','CA','jurisdiction','QC','authority','Ministère de l''Enseignement supérieur du Québec',
      'format','pdf','acquisition_method','authoritative_pdf_text',
      'identity','embedded IRCC DLI + Quebec ministry institution number + stable programme code',
      'course_identity_scheme','qc_mes_program_code','title_identity_allowed',false,
      'coverage_scope','university programmes over 20 credits not leading to a degree; degree programmes are omitted by source design'
    )
  )
  on conflict(code) do update set
    name=excluded.name,system_type=excluded.system_type,base_url=excluded.base_url,status='active',config=excluded.config,updated_at=now()
  returning id into v_system;

  if v_system is null then select id into v_system from integration.systems where code='ca_qc_mes_university_programs'; end if;

  select id into v_source from pipeline.sources
  where system_id=v_system and country_id=v_country and provider_id is null
  order by created_at limit 1;

  if v_source is null then
    insert into pipeline.sources(source_type,system_id,provider_id,country_id,url,label,trust_rank,status,metadata)
    values(
      'provincial_regulator',v_system,null,v_country,v_url,
      'Quebec MES university programmes >20 credits (non-degree)',99,'active',
      jsonb_build_object('layer','1','country','CA','province','QC','jurisdiction','QC','coverage_role','provincial_regulator_partial_course_identity','course_identity_scheme','qc_mes_program_code','title_identity_allowed',false,'raw_evidence_private',true)
    ) returning id into v_source;
  else
    update pipeline.sources set url=v_url,label='Quebec MES university programmes >20 credits (non-degree)',trust_rank=99,status='active',metadata=metadata||jsonb_build_object('layer','1','country','CA','province','QC','jurisdiction','QC','coverage_role','provincial_regulator_partial_course_identity','course_identity_scheme','qc_mes_program_code','title_identity_allowed',false,'raw_evidence_private',true),updated_at=now() where id=v_source;
  end if;

  insert into pipeline.ca_source_qualifications(source_id,jurisdiction_code,authority_role,provider_identity_scheme,course_identity_scheme,stable_program_id_proof,provider_dli_mapping_status,runtime_fetch_status,evidence_status,dry_run_status,apply_status,idempotency_status,integrity_status,performance_status,coverage_scope,notes,metadata)
  values(
    v_source,'QC','authoritative provincial regulator current programme table','ircc_dli','qc_mes_program_code',
    'Each accepted row embeds IRCC DLI, Quebec ministry institution number, and one stable programme code; reused/multi-code rows are rejected, not synthesized.',
    'embedded_dli_in_authoritative_row','pass','pending','pending','pending','pending','pending','pending',
    'Current Quebec university programmes over 20 credits not leading to a degree; degree programmes omitted by source design.',
    'Strict parser quarantines ambiguous multi-code/reused-code rows and DLI O19359201245 pending Provider mismatch resolution. Titles have zero identity power.',
    jsonb_build_object('source_segments',1424,'strict_expected_accepted',1363,'quarantined_dli','O19359201245','title_identity_allowed',false,'coverage_complete_for_jurisdiction',false)
  )
  on conflict(source_id) do update set
    jurisdiction_code=excluded.jurisdiction_code,authority_role=excluded.authority_role,provider_identity_scheme=excluded.provider_identity_scheme,course_identity_scheme=excluded.course_identity_scheme,stable_program_id_proof=excluded.stable_program_id_proof,provider_dli_mapping_status=excluded.provider_dli_mapping_status,runtime_fetch_status=excluded.runtime_fetch_status,coverage_scope=excluded.coverage_scope,notes=excluded.notes,metadata=pipeline.ca_source_qualifications.metadata||excluded.metadata,updated_at=now();
end $$;
