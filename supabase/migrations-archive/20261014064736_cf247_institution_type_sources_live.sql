-- CF-247 v2.15.276 (14 Oct 2026) Decision 258: institution type sources go live.
-- 1. NZQA organisation types. The NZQA register reader only sends a type when it applies a changed register (next due in
--    November), so a third provider facts source reads the NZQA provider search once per organisation type (layer1-provider-facts
--    v1.1.0, format nzqa_type_listing) and records nzqa_org_type against each provider by its NZQA number.
-- 2. The reader is deployed and its first applies passed (TEQSA 200 codes, CRICOS Institutions 1,542 of 1,545 matched), so the
--    three sources are resumed and read like the other registers: verified on their cadence and applied when the file changes.
--    The cadence and the automatic apply stay settings on Layer 1 > Sources.
-- Nothing is dropped or deleted.
insert into pipeline.sources (source_type, country_id, url, label, trust_rank, status, metadata)
select 'web', c.id, 'https://www.nzqa.govt.nz/providers/', 'NZQA provider search: organisation type', 100, 'active',
  jsonb_build_object('source_system', 'PROVIDER_FACTS', 'publisher', 'NZQA', 'layer', '1', 'operational_surface', 'layer1_register',
    'format', 'nzqa_type_listing', 'types', jsonb_build_array('UNI', 'POLLY', 'WANA', 'PTE', 'GTE'),
    'listing_url', 'https://www.nzqa.govt.nz/providers/results.do?regionCode=0&typeCode={type}&category=&copApprovalStatus=&nameQuery=',
    'scheme', 'nzqa', 'facts', jsonb_build_object('nzqa_org_type', 'organisation type'), 'decision', 'Decision 258')
from ref.countries c
where trim(c.iso_alpha2::text) = 'NZ'
  and not exists (select 1 from pipeline.sources s where s.metadata->>'source_system' = 'PROVIDER_FACTS' and s.label = 'NZQA provider search: organisation type');

insert into pipeline.layer1_source_operations (source_id, authority_name, authority_domains, expected_format, expected_count_kind, active, paused,
  verification_cadence_days, ingestion_cadence_days, auto_ingest, change_reason, next_verification_at)
select s.id, 'New Zealand Qualifications Authority (NZQA)', array['nzqa.govt.nz'], 'NZQA provider search result pages, one per organisation type', 'providers',
  true, false, 7, 7, true, 'Decision 258: NZQA organisation type for the institution type rules (Platform Admin, 14 Oct 2026)', now()
from pipeline.sources s
where s.metadata->>'source_system' = 'PROVIDER_FACTS' and s.label = 'NZQA provider search: organisation type'
  and not exists (select 1 from pipeline.layer1_source_operations o where o.source_id = s.id);

update pipeline.layer1_source_operations o
   set paused = false, auto_ingest = true, updated_at = now(),
       change_reason = 'Decision 258: reader deployed and first apply passed (14 Oct 2026). Verified on its cadence and applied when the file changes'
  from pipeline.sources s
 where s.id = o.source_id and s.metadata->>'source_system' = 'PROVIDER_FACTS' and o.paused;
