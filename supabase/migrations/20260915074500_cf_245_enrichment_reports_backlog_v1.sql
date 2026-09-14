-- CF-CHG-20260915-245 — Gate C/D reporting and backlog classification.
-- Read-only operational surfaces. No scheduler, routing, admission or publication mutation.

create or replace view pipeline.layer2_enrichment_hourly_v1
with (security_invoker = true)
as
select
  date_trunc('hour',coalesce(job_started_at,started_at,job_created_at,queued_at)) as hour_utc,
  country_code,
  profile_domain as domain,
  count(*)::integer as items,
  count(*) filter(where started_at is not null)::integer as started,
  count(*) filter(where provider_attempt_status='succeeded')::integer as fetched,
  count(*) filter(where provider_attempt_status='failed')::integer as fetch_failures,
  sum(evidence_count)::bigint as evidence_created,
  sum(coalesce(evidence_bytes_known,0))::bigint as evidence_bytes_known,
  bool_and(evidence_bytes_complete) as evidence_bytes_complete,
  count(*) filter(where extraction_status='normalised')::integer as extraction_attempted,
  count(*) filter(where coalesce(parsed_payload->>'official_course_url','')<>'')::integer as official_urls_found,
  count(*) filter(where coalesce(parsed_payload->'intakes','[]'::jsonb)<>'[]'::jsonb)::integer as intakes_found,
  count(*) filter(where coalesce(parsed_payload->'english_requirements','{}'::jsonb)<>'{}'::jsonb)::integer as english_requirements_found,
  count(*) filter(where parsed_payload->'provider_current_tuition' is not null and parsed_payload->'provider_current_tuition'<>'null'::jsonb)::integer as provider_current_tuition_found,
  0::integer as scholarships_found,
  sum(fields_admitted_lower_bound)::bigint as facts_admitted_lower_bound,
  count(*) filter(where content_changed=false)::integer as unchanged,
  count(*) filter(where stop_reason_code in('identity_mismatch','provider_or_runtime_blocker','runtime_blocked'))::integer as rejected_or_blocked,
  count(*) filter(where run_item_status='layer3_required')::integer as layer3_escalated,
  count(*) filter(where run_item_status ilike '%layer4%')::integer as layer4_referred,
  count(*) filter(where source_record_applied_at is not null)::integer as courses_improved_lower_bound,
  sum(coalesce(attempt_vendor_units,0))::numeric as vendor_units,
  sum(coalesce(attempt_vendor_cost_usd,0))::numeric as vendor_cost_usd,
  percentile_cont(.5) within group(order by response_ms) filter(where response_ms is not null) as p50_response_ms,
  percentile_cont(.95) within group(order by response_ms) filter(where response_ms is not null) as p95_response_ms,
  percentile_cont(.5) within group(order by extraction_ms) filter(where extraction_ms is not null) as p50_extraction_ms,
  percentile_cont(.95) within group(order by extraction_ms) filter(where extraction_ms is not null) as p95_extraction_ms,
  sum(coalesce(retry_count,0))::bigint as retries,
  count(*) filter(where response_http_status=429)::integer as http_429,
  count(*) filter(where response_http_status>=500)::integer as http_5xx,
  count(*) filter(where run_item_status='blocked' or failure_class is not null)::integer as other_runtime_failures
from pipeline.layer2_enrichment_operational_ledger_v1
group by 1,2,3;

revoke all on pipeline.layer2_enrichment_hourly_v1 from public,anon,authenticated;
grant select on pipeline.layer2_enrichment_hourly_v1 to service_role;

create or replace view pipeline.au_nz_enrichment_backlog_v1
with (security_invoker = true)
as
with search_base as (
  select course_id,country_code,has_link,has_intake,has_english,has_provider_current_tuition,has_scholarship
  from search.course_documents
  where country_code in('AU','NZ')
), scoped as (
  select 'AU'::text country_code,s.* from public.layer2_scope_courses('AU','country',null) s
  union all
  select 'NZ'::text country_code,s.* from public.layer2_scope_courses('NZ','country',null) s
), exec_policy as (
  select profile_id,bool_or(enabled) as enabled
  from pipeline.layer2_execution_policies
  group by profile_id
), joined as (
  select sb.*,sc.profile_id,sc.profile_key,sc.provider_id,sc.provider_name,sc.source_url,coalesce(ep.enabled,false) as execution_policy_enabled
  from search_base sb
  left join scoped sc on sc.country_code=sb.country_code and sc.course_id=sb.course_id
  left join exec_policy ep on ep.profile_id=sc.profile_id
), fields as (
  select j.*,f.field_key,f.covered
  from joined j
  cross join lateral (values
    ('official_course_url'::text,j.has_link),
    ('intake_availability',j.has_intake),
    ('english_requirements',j.has_english),
    ('provider_current_international_tuition',j.has_provider_current_tuition),
    ('scholarship',j.has_scholarship)
  ) f(field_key,covered)
)
select
  course_id,country_code,field_key,covered,profile_id,profile_key,provider_id,provider_name,source_url,execution_policy_enabled,
  case
    when covered then 'covered'
    when field_key='scholarship' then 'awaiting_source_profile_qualification'
    when profile_id is null then 'awaiting_source_profile_qualification'
    when source_url is not null and execution_policy_enabled then 'queueable'
    when source_url is not null and not execution_policy_enabled then 'blocked'
    when source_url is null and execution_policy_enabled then 'blocked'
    else 'awaiting_source_profile_qualification'
  end as backlog_state,
  case
    when covered then null
    when field_key='scholarship' then 'scholarship_requires_separate_qualified_scholarship_source_and_admission_path'
    when profile_id is null then 'no_qualified_course_fact_profile_in_current_scope'
    when source_url is not null and execution_policy_enabled then null
    when source_url is not null and not execution_policy_enabled then 'execution_policy_not_enabled_for_profile'
    when source_url is null and execution_policy_enabled then 'course_url_requires_governed_discovery'
    when source_url is null then 'course_url_requires_discovery_and_execution_policy'
    else 'not_queueable'
  end as blocker_reason,
  now() as observed_at
from fields;

revoke all on pipeline.au_nz_enrichment_backlog_v1 from public,anon,authenticated;
grant select on pipeline.au_nz_enrichment_backlog_v1 to service_role;

create or replace view pipeline.au_nz_enrichment_backlog_summary_v1
with (security_invoker = true)
as
select country_code,field_key,backlog_state,coalesce(blocker_reason,'') as blocker_reason,count(*)::bigint as courses
from pipeline.au_nz_enrichment_backlog_v1
group by country_code,field_key,backlog_state,coalesce(blocker_reason,'');

revoke all on pipeline.au_nz_enrichment_backlog_summary_v1 from public,anon,authenticated;
grant select on pipeline.au_nz_enrichment_backlog_summary_v1 to service_role;

comment on view pipeline.layer2_enrichment_hourly_v1 is 'CF-245 hourly enrichment outcome metrics; service-role only until governed Admin read projection is added.';
comment on view pipeline.au_nz_enrichment_backlog_v1 is 'CF-245 per-course/per-field AU/NZ enrichment demand classification. Missing values are never synthesized.';
comment on view pipeline.au_nz_enrichment_backlog_summary_v1 is 'CF-245 AU/NZ enrichment backlog summary by field/state/reason.';
