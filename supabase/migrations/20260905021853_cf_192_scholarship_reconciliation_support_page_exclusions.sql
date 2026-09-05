-- CF-192 — keep filter/support/non-individual pages as Evidence only.
update pipeline.scholarship_source_records sr
set status='unmapped',error_text='CF-192 support/filter/non-individual page retained as Evidence; excluded from Scholarship canonical reconciliation'
where sr.status='captured' and (
  lower(sr.source_record_url) ~ '[?&](combine|field_[a-z0-9_]+)='
  or lower(sr.source_record_url) ~ '/scholarships/domestic(\.html)?/?([?#].*)?$'
  or lower(coalesce(sr.payload->>'name','')) ~ '^(understand your fees|scholarship conditions|scholarship guide|prizes and awards)$'
  or length(coalesce(sr.payload->>'name',''))>180
  or lower(coalesce(sr.payload->>'name','')) like '%<div%'
  or lower(coalesce(sr.payload->>'name','')) like '%cmp-text%'
);
update pipeline.layer2_scholarship_discovery_candidates d
set classification='support_or_navigation',classification_reason='CF-192 source-record reconciliation identified support/filter/non-individual page',classified_at=now()
from pipeline.sources ds where ds.id=d.source_id and d.status='discovered' and exists(
 select 1 from pipeline.scholarship_source_records sr join pipeline.sources ss on ss.id=sr.source_id
 where ss.provider_id=ds.provider_id and rtrim(lower(sr.source_record_url),'/')=rtrim(lower(coalesce(nullif(d.detail_target_url,''),nullif(d.scholarship_url,''))),'/') and sr.status='unmapped' and sr.error_text like 'CF-192%'
);
comment on view pipeline.scholarship_verified_detail_reconciliation_candidates is 'CF-192 reconciliation boundary: only captured/applied first-party international individual Scholarship details are eligible; support/filter/non-individual Evidence is held unmapped.';
