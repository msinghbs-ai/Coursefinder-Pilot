-- Reproducibility marker for the Algonquin first-party Course identity source.
-- Data rows were registered using stable natural keys (integration.systems.code and pipeline.sources label/provider DLI).
-- No generated UUID is embedded in this migration.
DO $$
DECLARE v_system uuid; v_provider uuid; v_country uuid;
BEGIN
  SELECT id INTO v_country FROM ref.countries WHERE iso_alpha2='CA';
  SELECT p.id INTO v_provider
  FROM catalogue.providers p
  JOIN catalogue.provider_identifiers pi ON pi.provider_id=p.id
  WHERE p.country_id=v_country AND pi.scheme='ircc_dli' AND pi.identifier='O19358971022'
  LIMIT 1;
  IF v_provider IS NULL THEN RAISE EXCEPTION 'Algonquin verified IRCC DLI Provider missing'; END IF;

  INSERT INTO integration.systems(code,name,system_type,base_url,status,config)
  VALUES('ca_algonquin_catalogue','Algonquin College First-Party Programme Catalogue','institutional_catalogue','https://www.algonquincollege.com','active',
    jsonb_build_object('country','CA','province','ON','provider_dli','O19358971022','acquisition_method','html','catalogue_scope','AC Online programmes','local_identity_field','published program code','title_identity_allowed',false,'canonical_identity_write',true))
  ON CONFLICT(code) DO UPDATE SET name=excluded.name,system_type=excluded.system_type,base_url=excluded.base_url,status=excluded.status,config=excluded.config,updated_at=now()
  RETURNING id INTO v_system;

  IF NOT EXISTS (SELECT 1 FROM pipeline.sources WHERE label='Algonquin College first-party programme catalogue') THEN
    INSERT INTO pipeline.sources(source_type,system_id,provider_id,country_id,url,label,trust_rank,status,metadata)
    VALUES('institutional_catalogue',v_system,v_provider,v_country,'https://www.algonquincollege.com/online/programs/list/all/','Algonquin College first-party programme catalogue',15,'active',
      jsonb_build_object('layer','1','country','CA','province','ON','provider_dli','O19358971022','coverage_role','first_party_course_identity','course_identity_scheme','algonquin_program_code','title_identity_allowed',false,'regional_validation_source','Ontario APS','apply_gate','bounded_uat'));
  END IF;
END $$;
