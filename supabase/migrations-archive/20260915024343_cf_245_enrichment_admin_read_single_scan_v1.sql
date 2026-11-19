begin;

create or replace function security.admin_enrichment_operations_read(p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','security','pipeline','search','catalogue','ref'
as $$
declare
  v_rank integer:=security.current_role_rank();
  v_country text:=upper(nullif(btrim(coalesce(p_args->>'country_code','')),''));
  v_hours integer:=least(greatest(coalesce(nullif(p_args->>'hours','')::integer,24),1),168);
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,30),1),100);
  v_result jsonb;
begin
  if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
  if v_country is not null and v_country not in('AU','NZ') then raise exception 'unsupported country' using errcode='22023'; end if;

  with
  ledger as materialized (
    select *
    from pipeline.layer2_enrichment_operational_ledger_v1
    where v_country is null or country_code=v_country
  ),
  current_cov as (
    select country_code,field_key,max(covered_count)::bigint covered_count,max(total_courses)::bigint total_courses,
           max(queueable_count)::bigint queueable_count,max(blocked_count)::bigint blocked_count,
           max(awaiting_qualification_count)::bigint awaiting_count,max(snapshot_hour) snapshot_hour
    from pipeline.enrichment_coverage_snapshots s
    where s.snapshot_hour=(select max(s2.snapshot_hour) from pipeline.enrichment_coverage_snapshots s2)
      and (v_country is null or s.country_code=v_country)
    group by country_code,field_key
  ), prior_hour as (
    select distinct on(country_code,field_key) country_code,field_key,covered_count,snapshot_hour
    from pipeline.enrichment_coverage_snapshots
    where snapshot_hour < date_trunc('hour',now()) and (v_country is null or country_code=v_country)
    order by country_code,field_key,snapshot_hour desc
  ), prior_day as (
    select distinct on(country_code,field_key) country_code,field_key,covered_count,snapshot_hour
    from pipeline.enrichment_coverage_snapshots
    where snapshot_hour <= date_trunc('hour',now())-interval '24 hours' and (v_country is null or country_code=v_country)
    order by country_code,field_key,snapshot_hour desc
  ), coverage_json as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'country_code',c.country_code,'field_key',c.field_key,'current',c.covered_count,'total',c.total_courses,
      'coverage_pct',case when c.total_courses>0 then round((100*c.covered_count::numeric/c.total_courses),2) else 0 end,
      'remaining',greatest(c.total_courses-c.covered_count,0),
      'added_hour',case when ph.covered_count is null then null else c.covered_count-ph.covered_count end,
      'added_day',case when pd.covered_count is null then null else c.covered_count-pd.covered_count end,
      'queueable',c.queueable_count,'blocked',c.blocked_count,'awaiting_qualification',c.awaiting_count,
      'snapshot_hour',c.snapshot_hour,'hour_baseline_at',ph.snapshot_hour,'day_baseline_at',pd.snapshot_hour
    ) order by c.country_code,c.field_key),'[]'::jsonb) value
    from current_cov c left join prior_hour ph using(country_code,field_key) left join prior_day pd using(country_code,field_key)
  ), work as (
    select jsonb_build_object(
      'queued',count(*) filter(where run_item_status='queued'),
      'processing',count(*) filter(where run_item_status='running'),
      'fetched',count(*) filter(where provider_attempt_status='succeeded' and operational_event_at>=now()-interval '24 hours'),
      'fetch_failures',count(*) filter(where provider_attempt_status='failed' and operational_event_at>=now()-interval '24 hours'),
      'evidence_24h',coalesce(sum(evidence_count) filter(where operational_event_at>=now()-interval '24 hours'),0),
      'layer3_24h',count(*) filter(where run_item_status='layer3_required' and operational_event_at>=now()-interval '24 hours'),
      'admitted_source_records_24h',count(*) filter(where source_record_applied_at>=now()-interval '24 hours'),
      'http_429_24h',count(*) filter(where response_http_status=429 and operational_event_at>=now()-interval '24 hours'),
      'http_5xx_24h',count(*) filter(where response_http_status>=500 and operational_event_at>=now()-interval '24 hours'),
      'vendor_units_24h',coalesce(sum(attempt_vendor_units) filter(where operational_event_at>=now()-interval '24 hours'),0),
      'vendor_cost_usd_24h',coalesce(sum(attempt_vendor_cost_usd) filter(where operational_event_at>=now()-interval '24 hours'),0)
    ) value from ledger
  ), hourly_rows as (
    select date_trunc('hour',coalesce(job_started_at,started_at,job_created_at,queued_at)) hour_utc,
           country_code,profile_domain domain,count(*)::integer items,
           count(*) filter(where started_at is not null)::integer started,
           count(*) filter(where provider_attempt_status='succeeded')::integer fetched,
           count(*) filter(where provider_attempt_status='failed')::integer fetch_failures,
           sum(evidence_count)::bigint evidence_created,
           sum(coalesce(evidence_bytes_known,0))::bigint evidence_bytes_known,
           bool_and(evidence_bytes_complete) evidence_bytes_complete,
           count(*) filter(where extraction_status='normalised')::integer extraction_attempted,
           count(*) filter(where coalesce(parsed_payload->>'official_course_url','')<>'')::integer official_urls_found,
           count(*) filter(where coalesce(parsed_payload->'intakes','[]'::jsonb)<>'[]'::jsonb)::integer intakes_found,
           count(*) filter(where coalesce(parsed_payload->'english_requirements','{}'::jsonb)<>'{}'::jsonb)::integer english_requirements_found,
           count(*) filter(where parsed_payload->'provider_current_tuition' is not null and parsed_payload->'provider_current_tuition'<>'null'::jsonb)::integer provider_current_tuition_found,
           0::integer scholarships_found,sum(fields_admitted_lower_bound)::bigint facts_admitted_lower_bound,
           count(*) filter(where content_changed=false)::integer unchanged,
           count(*) filter(where stop_reason_code in('identity_mismatch','provider_or_runtime_blocker','runtime_blocked'))::integer rejected_or_blocked,
           count(*) filter(where run_item_status='layer3_required')::integer layer3_escalated,
           count(*) filter(where run_item_status ilike '%layer4%')::integer layer4_referred,
           count(*) filter(where source_record_applied_at is not null)::integer courses_improved_lower_bound,
           sum(coalesce(attempt_vendor_units,0))::numeric vendor_units,sum(coalesce(attempt_vendor_cost_usd,0))::numeric vendor_cost_usd,
           percentile_cont(.5) within group(order by response_ms) filter(where response_ms is not null) p50_response_ms,
           percentile_cont(.95) within group(order by response_ms) filter(where response_ms is not null) p95_response_ms,
           percentile_cont(.5) within group(order by extraction_ms) filter(where extraction_ms is not null) p50_extraction_ms,
           percentile_cont(.95) within group(order by extraction_ms) filter(where extraction_ms is not null) p95_extraction_ms,
           sum(coalesce(retry_count,0))::bigint retries,count(*) filter(where response_http_status=429)::integer http_429,
           count(*) filter(where response_http_status>=500)::integer http_5xx,
           count(*) filter(where run_item_status='blocked' or failure_class is not null)::integer other_runtime_failures
    from ledger
    where coalesce(job_started_at,started_at,job_created_at,queued_at)>=date_trunc('hour',now())-(v_hours||' hours')::interval
    group by 1,2,3
    order by 1 desc
    limit v_hours*4
  ), hourly as (
    select coalesce(jsonb_agg(to_jsonb(h) order by h.hour_utc),'[]'::jsonb) value from hourly_rows h
  ), blockers as (
    select coalesce(jsonb_agg(x order by (x->>'courses')::bigint desc,x->>'country_code',x->>'field_key'),'[]'::jsonb) value
    from (
      select jsonb_build_object('country_code',country_code,'field_key',field_key,'state','queueable','reason','ready_under_current_qualified_scope','courses',queueable_count) x from current_cov where queueable_count>0
      union all
      select jsonb_build_object('country_code',country_code,'field_key',field_key,'state','blocked','reason','blocked_under_current_scope','courses',blocked_count) from current_cov where blocked_count>0
      union all
      select jsonb_build_object('country_code',country_code,'field_key',field_key,'state','awaiting_source_profile_qualification','reason','source_profile_qualification_required','courses',awaiting_count) from current_cov where awaiting_count>0
    ) b
  ), reasons as (
    select coalesce(jsonb_agg(jsonb_build_object('reason',stop_reason_code,'items',items,'fields_targeted',fields_targeted,'fields_resolved',fields_resolved) order by items desc),'[]'::jsonb) value
    from (select stop_reason_code,count(*)::bigint items,sum(coalesce(fields_targeted,0))::bigint fields_targeted,sum(coalesce(fields_resolved,0))::bigint fields_resolved from ledger where operational_event_at>=now()-interval '7 days' group by stop_reason_code order by items desc limit 30) q
  ), providers as (
    select coalesce(jsonb_agg(jsonb_build_object('provider',acquisition_provider_key,'attempts',attempts,'succeeded',succeeded,'failed',failed,'vendor_units',vendor_units,'cost_usd',cost_usd,'p50_ms',p50_ms,'p95_ms',p95_ms,'retries',retries) order by attempts desc),'[]'::jsonb) value
    from (select coalesce(acquisition_provider_key,'unknown') acquisition_provider_key,count(*)::bigint attempts,count(*) filter(where provider_attempt_status='succeeded')::bigint succeeded,count(*) filter(where provider_attempt_status='failed')::bigint failed,coalesce(sum(attempt_vendor_units),0)::numeric vendor_units,coalesce(sum(attempt_vendor_cost_usd),0)::numeric cost_usd,percentile_cont(.5) within group(order by response_ms) filter(where response_ms is not null) p50_ms,percentile_cont(.95) within group(order by response_ms) filter(where response_ms is not null) p95_ms,coalesce(sum(retry_count),0)::bigint retries from ledger where operational_event_at>=now()-interval '7 days' group by acquisition_provider_key order by attempts desc limit 20) q
  ), admissions as (
    select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'course_id',a.course_id,'field_key',a.field_key,'status',a.status,'reason_code',a.reason_code,'canonical_changed',a.canonical_changed,'search_admission_eligible',a.search_admission_eligible,'evidence_id',a.evidence_id,'decided_at',a.decided_at,'provider_name',p.display_name,'course_title',c.display_title) order by a.decided_at desc),'[]'::jsonb) value
    from (select * from pipeline.layer2_field_admissions order by decided_at desc limit v_limit) a join catalogue.courses c on c.id=a.course_id join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id where v_country is null or trim(co.iso_alpha2)=v_country
  ), recent_items as (
    select coalesce(jsonb_agg(jsonb_build_object('run_item_id',run_item_id,'job_id',job_id,'course_id',course_id,'course_code',course_code,'provider_name',provider_name,'country_code',country_code,'status',run_item_status,'stop_reason',stop_reason_code,'fields_targeted',fields_targeted,'fields_resolved',fields_resolved,'evidence_count',evidence_count,'source_record_id',source_record_id,'evidence_id',parsed_payload->>'evidence_id','event_at',operational_event_at) order by operational_event_at desc),'[]'::jsonb) value
    from (select * from ledger order by operational_event_at desc nulls last limit v_limit) q
  )
  select jsonb_build_object('observed_at',now(),'country_code',v_country,'coverage',(select value from coverage_json),'work',(select value from work),'hourly',(select value from hourly),'blockers',(select value from blockers),'stop_reasons',(select value from reasons),'providers',(select value from providers),'admissions',(select value from admissions),'recent_items',(select value from recent_items),'authority_note','Acquisition, admission and Search/publication are measured separately. Metrics do not authorise mutation.','change_control_ref','CF-CHG-20260915-245') into v_result;
  return v_result;
end $$;

revoke all on function security.admin_enrichment_operations_read(jsonb) from public,anon;
grant execute on function security.admin_enrichment_operations_read(jsonb) to authenticated,service_role;

commit;
