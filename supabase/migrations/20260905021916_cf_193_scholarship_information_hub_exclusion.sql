-- CF-193 — information/funding hubs are Evidence, not individual Scholarship roots.
update pipeline.scholarship_source_records
set status='unmapped',error_text='CF-193 information/funding hub retained as Evidence; not an individual Scholarship'
where status='captured' and lower(coalesce(payload->>'name','')) in('funding and grant opportunities','scholarship information');
update pipeline.layer2_scholarship_discovery_candidates d
set classification='support_or_navigation',classification_reason='CF-193 information/funding hub excluded from individual Scholarship reconciliation',classified_at=now()
from pipeline.sources ds where ds.id=d.source_id and d.status='discovered' and exists(
 select 1 from pipeline.scholarship_source_records sr join pipeline.sources ss on ss.id=sr.source_id
 where ss.provider_id=ds.provider_id and rtrim(lower(sr.source_record_url),'/')=rtrim(lower(coalesce(nullif(d.detail_target_url,''),nullif(d.scholarship_url,''))),'/') and sr.status='unmapped' and sr.error_text like 'CF-193%'
);
