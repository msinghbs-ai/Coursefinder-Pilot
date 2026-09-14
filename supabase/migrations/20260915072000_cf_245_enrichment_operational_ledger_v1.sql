-- CF-CHG-20260915-245 — Enrichment Operations, Metrics & Coverage Expansion
-- Gate B: derive a common operational ledger from the governed Layer 2 batch/item path.
-- This migration is read-only/observability-only: it does not change Layer 1–4 authority,
-- Search/Publication admission, scheduler cadence, provider routing, concurrency or budgets.

create or replace view pipeline.layer2_enrichment_operational_ledger_v1
with (security_invoker = true)
as
with evidence_by_job as (
  select
    e.job_id,
    count(*)::integer as evidence_count,
    count(*) filter (where e.evidence_type = 'layer2_screenshot')::integer as screenshot_evidence_count,
    count(*) filter (where e.evidence_type = 'layer2_extraction_input')::integer as normalized_evidence_count
  from pipeline.evidence_artifacts e
  where e.job_id is not null
  group by e.job_id
),
base as (
  select
    ri.id as run_item_id,
    ri.batch_id,
    rb.profile_id,
    ri.entity_type,
    ri.entity_id,
    ri.source_url,
    ri.status as run_item_status,
    ri.outcome_code,
    ri.failure_class,
    ri.blocker,
    ri.fields_targeted,
    ri.fields_resolved,
    greatest(coalesce(ri.fields_targeted,0) - coalesce(ri.fields_resolved,0),0) as fields_unresolved,
    ri.vendor_units,
    ri.vendor_cost_usd,
    ri.retry_count,
    ri.response_ms,
    ri.extraction_ms,
    ri.evidence_bytes as recorded_evidence_bytes,
    ri.created_at as queued_at,
    ri.started_at,
    ri.completed_at,
    ri.updated_at,
    case when ri.started_at is not null
      then greatest(0,round(extract(epoch from (ri.started_at-ri.created_at))*1000)::bigint)
      else null end as queue_wait_ms,
    case when ri.started_at is not null and coalesce(ri.completed_at,ri.updated_at) is not null
      then greatest(0,round(extract(epoch from (coalesce(ri.completed_at,ri.updated_at)-ri.started_at))*1000)::bigint)
      else null end as execution_ms,
    j.id as job_id,
    j.job_type,
    j.domain,
    j.status as job_status,
    j.created_at as job_created_at,
    j.started_at as job_started_at,
    j.completed_at as job_completed_at,
    j.result as job_result,
    pa.id as provider_attempt_id,
    pa.profile_version_id as source_profile_version_id,
    pa.acquisition_provider_id,
    ap.provider_key as acquisition_provider_key,
    pa.attempt_no,
    pa.status as provider_attempt_status,
    pa.response_http_status,
    pa.extraction_status,
    pa.blocker as provider_attempt_blocker,
    pa.metrics as provider_attempt_metrics,
    coalesce(ebj.evidence_count,0) as evidence_count,
    coalesce(ebj.screenshot_evidence_count,0) as screenshot_evidence_count,
    coalesce(ebj.normalized_evidence_count,0) as normalized_evidence_count,
    nullif(pa.metrics->>'bytes','')::bigint as known_response_bytes,
    nullif(pa.metrics->>'latency_ms','')::integer as provider_response_ms,
    nullif(pa.metrics->>'vendor_units','')::numeric as attempt_vendor_units,
    nullif(pa.metrics->>'estimated_request_cost_usd','')::numeric as attempt_vendor_cost_usd,
    coalesce((pa.metrics->>'content_changed')::boolean,(j.result->>'content_changed')::boolean) as content_changed,
    sr.id as source_record_id,
    sr.status as source_record_status,
    sr.applied_at as source_record_applied_at,
    sr.parsed_payload,
    sp.profile_key,
    sp.domain as profile_domain,
    c.id as course_id,
    c.course_code,
    c.provider_id,
    p.display_name as provider_name,
    trim(rc.iso_alpha2)::text as country_code,
    sd.has_link as search_has_official_link,
    sd.has_intake as search_has_intake,
    sd.has_english as search_has_english,
    sd.has_provider_current_tuition as search_has_provider_current_tuition,
    sd.has_scholarship as search_has_scholarship
  from pipeline.layer2_run_items ri
  join pipeline.layer2_run_batches rb on rb.id=ri.batch_id
  left join pipeline.jobs j on j.id=ri.job_id
  left join pipeline.layer2_provider_attempts pa on pa.job_id=j.id
  left join pipeline.layer2_acquisition_providers ap on ap.id=pa.acquisition_provider_id
  left join evidence_by_job ebj on ebj.job_id=j.id
  left join pipeline.course_fact_source_records sr
    on sr.evidence_id::text = pa.metrics->>'normalised_evidence_id'
  left join pipeline.layer2_source_profile_versions spv on spv.id=coalesce(pa.profile_version_id,j.source_profile_version_id)
  left join pipeline.layer2_source_profiles sp on sp.id=coalesce(spv.profile_id,rb.profile_id)
  left join catalogue.courses c on ri.entity_type='course' and c.id=ri.entity_id
  left join catalogue.providers p on p.id=c.provider_id
  left join ref.countries rc on rc.id=p.country_id
  left join search.course_documents sd on sd.course_id=c.id
),
classified as (
  select
    b.*,
    array_remove(array[
      case when b.parsed_payload->'baseline_factual'->>'course_url'='not_yet_enriched'
             and coalesce(b.parsed_payload->>'official_course_url','')='' then 'official_course_url' end,
      case when b.parsed_payload->'baseline_factual'->>'intakes'='not_yet_enriched'
             and coalesce(b.parsed_payload->'intakes','[]'::jsonb)='[]'::jsonb then 'intakes' end,
      case when b.parsed_payload->'baseline_factual'->>'english_requirements'='not_yet_enriched'
             and coalesce(b.parsed_payload->'english_requirements','{}'::jsonb)='{}'::jsonb then 'english_requirements' end,
      case when b.parsed_payload->'baseline_factual'->>'provider_current_tuition'='not_yet_enriched'
             and (b.parsed_payload->'provider_current_tuition' is null or b.parsed_payload->'provider_current_tuition'='null'::jsonb)
             then 'provider_current_tuition' end,
      case when b.parsed_payload->'baseline_factual'->>'description'='not_yet_enriched'
             and (b.parsed_payload->'description_candidate' is null or b.parsed_payload->'description_candidate'='null'::jsonb)
             then 'description' end
    ],null)::text[] as unresolved_domains
  from base b
)
select
  c.*,
  case
    when c.run_item_status='blocked' then coalesce(nullif(c.failure_class,''),'runtime_blocked')
    when c.provider_attempt_id is null then 'capture_or_attempt_not_started'
    when c.provider_attempt_status='failed' then 'provider_or_runtime_blocker'
    when c.extraction_status in ('not_attempted','acquired') and c.source_record_id is null then 'extraction_not_completed'
    when coalesce((c.parsed_payload->>'identity_match')::boolean,true)=false then 'identity_mismatch'
    when c.run_item_status='layer3_required' and cardinality(c.unresolved_domains)>0 then 'layer3_unresolved_target_fields'
    when c.run_item_status='layer3_required' then 'layer3_required'
    when c.source_record_applied_at is null and c.run_item_status='resolved_l2' then 'resolved_candidate_not_admitted'
    when c.source_record_applied_at is not null then 'admitted'
    else coalesce(nullif(c.outcome_code,''),c.run_item_status,'unknown')
  end as stop_reason_code,
  nullif(c.parsed_payload->>'fee_rejection_reason','') as fee_rejection_reason,
  coalesce((c.parsed_payload->>'identity_match')::boolean,true) as identity_match,
  coalesce((c.parsed_payload->>'canonical_mutation_authorised')::boolean,
           (c.job_result->>'canonical_mutation_authorised')::boolean,false) as canonical_mutation_authorised,
  case when c.source_record_applied_at is not null then coalesce(c.fields_resolved,0) else 0 end as fields_admitted_lower_bound,
  case when c.source_record_applied_at is null then 0 else null end as fields_rejected_known,
  coalesce(c.recorded_evidence_bytes,c.known_response_bytes) as evidence_bytes_known,
  (c.recorded_evidence_bytes is not null) as evidence_bytes_complete,
  coalesce(c.updated_at,c.completed_at,c.job_completed_at,c.started_at,c.job_started_at,c.queued_at) as operational_event_at
from classified c;

revoke all on pipeline.layer2_enrichment_operational_ledger_v1 from public, anon, authenticated;
grant select on pipeline.layer2_enrichment_operational_ledger_v1 to service_role;

comment on view pipeline.layer2_enrichment_operational_ledger_v1 is
'CF-245 governed operational ledger derived from Layer 2 run items, jobs, attempts, Evidence, candidates and Search state. Observability only; no mutation authority.';
