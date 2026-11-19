DO $$
DECLARE v_source uuid;
BEGIN
  SELECT id INTO v_source FROM pipeline.sources WHERE label='Ontario public college programmes / APS' LIMIT 1;
  IF v_source IS NULL THEN RAISE EXCEPTION 'Ontario APS source missing'; END IF;

  WITH ca AS (SELECT id FROM ref.countries WHERE iso_alpha2='CA'),
  codes(code, expected_name) AS (
    VALUES
    ('ALGO','Algonquin College'),('BORE','Collège Boréal'),('CAMB','Cambrian College of Applied Arts and Technology'),('CANA','Canadore College'),
    ('CENT','Centennial College'),('CONF','Confederation College'),('CONS','Conestoga College'),('DURH','Durham College'),('FANS','Fanshawe College'),
    ('GEOR','Georgian College'),('GRBR','George Brown College'),('HUMB','Humber College'),('LACI','La Cité collégiale'),('LAMB','Lambton College'),
    ('LOYT','Loyalist College'),('MOHA','Mohawk College'),('NIAG','Niagara College Canada'),('NORT','Northern College'),('SAUL','Sault College'),
    ('SENE','Seneca College'),('SHER','Sheridan College'),('SLAW','St. Lawrence College'),('SSFL','Fleming College'),('STCL','St. Clair College')
  ), resolved AS (
    SELECT c.code,c.expected_name,p.id provider_id,pi.identifier dli
    FROM codes c CROSS JOIN ca
    JOIN catalogue.providers p ON p.country_id=ca.id AND lower(p.canonical_name)=lower(c.expected_name)
    JOIN catalogue.provider_identifiers pi ON pi.provider_id=p.id AND pi.scheme='ircc_dli'
  )
  INSERT INTO pipeline.source_provider_mappings(source_id,source_entity_key,source_entity_name,provider_id,match_method,match_confidence,status,verified_at,metadata)
  SELECT v_source,'on-college:'||lower(code),code,provider_id,'official_ontario_college_code_to_verified_ircc_dli',1.0,'verified',now(),
         jsonb_build_object('ontario_college_code',code,'expected_name',expected_name,'ircc_dli',dli,'identity_write_allowed',false,'verified_scope','Ontario public college ministry code -> canonical IRCC DLI Provider')
  FROM resolved
  ON CONFLICT(source_id,source_entity_key) DO UPDATE SET
    source_entity_name=excluded.source_entity_name,provider_id=excluded.provider_id,match_method=excluded.match_method,
    match_confidence=excluded.match_confidence,status='verified',verified_at=excluded.verified_at,metadata=excluded.metadata,updated_at=now();
END $$;
