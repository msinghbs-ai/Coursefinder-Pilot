-- P5a (tool-neutral Evidence), step 1: acquisition provenance for every web-fetched Evidence item.
-- The acquisition layer is already multi-tool (pipeline.layer2_acquisition_providers with
-- per-tool response adapters). This view records, per Evidence item, which tool and adapter
-- fetched it, from where, when and with what result, so downstream consumers never depend on
-- a specific vendor and tool changes stay traceable. Read-only; service role only.
create or replace view pipeline.evidence_acquisition_provenance_v1 as
select distinct on (e.id)
  e.id as evidence_id, e.evidence_type, e.source_url, e.mime_type, e.captured_at, e.capture_version,
  ap.provider_key as acquisition_tool, ap.display_name as acquisition_tool_name, ap.adapter_type,
  ap.request_template->>'response_adapter' as response_adapter,
  a.id as attempt_id, a.status as attempt_status, a.response_http_status, a.response_mime_type,
  a.runtime_platform, a.runtime_region, a.started_at, a.completed_at,
  case when e.id=a.raw_evidence_id then 'raw' when e.id=a.html_evidence_id then 'html' when e.id=a.screenshot_evidence_id then 'screenshot' end as evidence_role
from pipeline.evidence_artifacts e
join pipeline.layer2_provider_attempts a on e.id in (a.raw_evidence_id,a.html_evidence_id,a.screenshot_evidence_id)
join pipeline.layer2_acquisition_providers ap on ap.id=a.acquisition_provider_id
order by e.id, a.completed_at desc nulls last;
revoke all on pipeline.evidence_acquisition_provenance_v1 from public, anon, authenticated;
grant select on pipeline.evidence_acquisition_provenance_v1 to service_role;
