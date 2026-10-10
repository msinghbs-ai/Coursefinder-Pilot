-- CF-CHG-20260915-245 — Gate F Enrichment Operations Admin reporting.
-- Adds outcome telemetry/read surfaces only. No enrichment scheduler frequency,
-- routing, concurrency, provider budget, Layer authority or publication policy changes.

create table if not exists pipeline.enrichment_coverage_snapshots(
  id uuid primary key default gen_random_uuid(),
  snapshot_hour timestamptz not null,
  country_code text not null,
  field_key text not null,
  covered_count bigint not null,
  total_courses bigint not null,
  queueable_count bigint not null default 0,
  blocked_count bigint not null default 0,
  awaiting_qualification_count bigint not null default 0,
  not_applicable_count bigint not null default 0,
  change_control_ref text not null default 'CF-CHG-20260915-245',
  observed_at timestamptz not null default now(),
  unique(snapshot_hour,country_code,field_key)
);
alter table pipeline.enrichment_coverage_snapshots enable row level security;
revoke all on pipeline.enrichment_coverage_snapshots from public,anon,authenticated;
grant select,insert,update on pipeline.enrichment_coverage_snapshots to service_role;
create index if not exists enrichment_coverage_snapshots_recent_idx
  on pipeline.enrichment_coverage_snapshots(snapshot_hour desc,country_code,field_key);

create or replace function public.svc_cf245_capture_coverage_snapshot()
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','pipeline','search','ref','catalogue'
as $$
declare v_hour timestamptz:=date_trunc('hour',now()); v_rows integer:=0;
begin
  if current_user not in('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;
  with countries as (
    select trim(c.iso_alpha2)::text country_code,count(*)::bigint total_courses
    from search.course_documents d join ref.countries c on c.id=d.country_id
    where trim(c.iso_alpha2) in('AU','NZ') group by 1
  ), coverage as (
    select trim(c.iso_alpha2)::text country_code,'official_course_url'::text field_key,count(*) filter(where d.official_course_url is not null)::bigint covered_count
    from search.course_documents d join ref.countries c on c.id=d.country_id where trim(c.iso_alpha2) in('AU','NZ') group by 1
    union all
    select trim(c.iso_alpha2)::text,'intake_availability',count(*) filter(where jsonb_array_length(coalesce(d.intake_options,'[]'::jsonb))>0)::bigint
    from search.course_documents d join ref.countries c on c.id=d.country_id where trim(c.iso_alpha2) in('AU','NZ') group by 1
    union all
    select trim(c.iso_alpha2)::text,'english_requirements',count(*) filter(where jsonb_array_length(coalesce(d.english_requirement_options,'[]'::jsonb))>0)::bigint
    from search.course_documents d join ref.countries c on c.id=d.country_id where trim(c.iso_alpha2) in('AU','NZ') group by 1
    union all
    select trim(c.iso_alpha2)::text,'provider_current_international_tuition',count(*) filter(where d.has_provider_current_tuition)::bigint
    from search.course_documents d join ref.countries c on c.id=d.country_id where trim(c.iso_alpha2) in('AU','NZ') group by 1
    union all
    select trim(c.iso_alpha2)::text,'scholarship',count(*) filter(where jsonb_array_length(coalesce(d.scholarship_options,'[]'::jsonb))>0)::bigint
    from search.course_documents d join ref.countries c on c.id=d.country_id where trim(c.iso_alpha2) in('AU','NZ') group by 1
  ), backlog as (
    select country_code,field_key,
      count(*) filter(where backlog_state='queueable')::bigint queueable_count,
      count(*) filter(where backlog_state='blocked')::bigint blocked_count,
      count(*) filter(where backlog_state='awaiting_source_profile_qualification')::bigint awaiting_count
    from pipeline.au_nz_enrichment_backlog_v1 group by country_code,field_key
  )
  insert into pipeline.enrichment_coverage_snapshots(
    snapshot_hour,country_code,field_key,covered_count,total_courses,queueable_count,blocked_count,awaiting_qualification_count,not_applicable_count
  )
  select v_hour,cv.country_code,cv.field_key,cv.covered_count,co.total_courses,
         coalesce(b.queueable_count,0),coalesce(b.blocked_count,0),coalesce(b.awaiting_count,0),0
  from coverage cv join countries co using(country_code)
  left join backlog b using(country_code,field_key)
  on conflict(snapshot_hour,country_code,field_key) do update set
    covered_count=excluded.covered_count,total_courses=excluded.total_courses,
    queueable_count=excluded.queueable_count,blocked_count=excluded.blocked_count,
    awaiting_qualification_count=excluded.awaiting_qualification_count,
    not_applicable_count=excluded.not_applicable_count,observed_at=now();
  get diagnostics v_rows=row_count;
  return jsonb_build_object('ok',true,'snapshot_hour',v_hour,'rows',v_rows,'change_control_ref','CF-CHG-20260915-245');
end $$;
revoke all on function public.svc_cf245_capture_coverage_snapshot() from public,anon,authenticated;
grant execute on function public.svc_cf245_capture_coverage_snapshot() to service_role;

-- Hourly telemetry snapshots are independent of enrichment work scheduling.
do $$
begin
  if exists(select 1 from cron.job where jobname='coursefinder-cf245-enrichment-coverage-snapshot') then
    perform cron.unschedule((select jobid from cron.job where jobname='coursefinder-cf245-enrichment-coverage-snapshot' limit 1));
  end if;
  perform cron.schedule(
    'coursefinder-cf245-enrichment-coverage-snapshot',
    '7 * * * *',
    'select public.svc_cf245_capture_coverage_snapshot();'
  );
end $$;

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

  with current_cov as (
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
      'country_code',c.country_code,'field_key',c.field_key,
      'current',c.covered_count,'total',c.total_courses,
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
    ) value from pipeline.layer2_enrichment_operational_ledger_v1
    where v_country is null or country_code=v_country
  ), hourly as (
    select coalesce(jsonb_agg(to_jsonb(h) order by h.hour_utc),'[]'::jsonb) value
    from (select * from pipeline.layer2_enrichment_hourly_v1
          where hour_utc>=date_trunc('hour',now())-(v_hours||' hours')::interval
            and (v_country is null or country_code=v_country)
          order by hour_utc desc limit v_hours*4) h
  ), blockers as (
    select coalesce(jsonb_agg(jsonb_build_object('country_code',country_code,'field_key',field_key,'state',backlog_state,'reason',blocker_reason,'courses',courses)
      order by courses desc,country_code,field_key),'[]'::jsonb) value
    from (select * from pipeline.au_nz_enrichment_backlog_summary_v1
          where backlog_state<>'covered' and (v_country is null or country_code=v_country)
          order by courses desc limit 50) b
  ), reasons as (
    select coalesce(jsonb_agg(jsonb_build_object('reason',stop_reason_code,'items',items,'fields_targeted',fields_targeted,'fields_resolved',fields_resolved)
      order by items desc),'[]'::jsonb) value
    from (
      select stop_reason_code,count(*)::bigint items,sum(coalesce(fields_targeted,0))::bigint fields_targeted,sum(coalesce(fields_resolved,0))::bigint fields_resolved
      from pipeline.layer2_enrichment_operational_ledger_v1
      where operational_event_at>=now()-interval '7 days' and (v_country is null or country_code=v_country)
      group by stop_reason_code order by items desc limit 30
    ) q
  ), providers as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'provider',acquisition_provider_key,'attempts',attempts,'succeeded',succeeded,'failed',failed,
      'vendor_units',vendor_units,'cost_usd',cost_usd,'p50_ms',p50_ms,'p95_ms',p95_ms,'retries',retries
    ) order by attempts desc),'[]'::jsonb) value
    from (
      select coalesce(acquisition_provider_key,'unknown') acquisition_provider_key,count(*)::bigint attempts,
        count(*) filter(where provider_attempt_status='succeeded')::bigint succeeded,
        count(*) filter(where provider_attempt_status='failed')::bigint failed,
        coalesce(sum(attempt_vendor_units),0)::numeric vendor_units,coalesce(sum(attempt_vendor_cost_usd),0)::numeric cost_usd,
        percentile_cont(.5) within group(order by response_ms) filter(where response_ms is not null) p50_ms,
        percentile_cont(.95) within group(order by response_ms) filter(where response_ms is not null) p95_ms,
        coalesce(sum(retry_count),0)::bigint retries
      from pipeline.layer2_enrichment_operational_ledger_v1
      where operational_event_at>=now()-interval '7 days' and (v_country is null or country_code=v_country)
      group by acquisition_provider_key order by attempts desc limit 20
    ) q
  ), admissions as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id',a.id,'course_id',a.course_id,'field_key',a.field_key,'status',a.status,'reason_code',a.reason_code,
      'canonical_changed',a.canonical_changed,'search_admission_eligible',a.search_admission_eligible,
      'evidence_id',a.evidence_id,'decided_at',a.decided_at,'provider_name',p.display_name,'course_title',c.display_title
    ) order by a.decided_at desc),'[]'::jsonb) value
    from (select * from pipeline.layer2_field_admissions order by decided_at desc limit v_limit) a
    join catalogue.courses c on c.id=a.course_id join catalogue.providers p on p.id=c.provider_id
    join ref.countries co on co.id=p.country_id
    where v_country is null or trim(co.iso_alpha2)=v_country
  ), recent_items as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'run_item_id',run_item_id,'job_id',job_id,'course_id',course_id,'course_code',course_code,'provider_name',provider_name,
      'country_code',country_code,'status',run_item_status,'stop_reason',stop_reason_code,'fields_targeted',fields_targeted,
      'fields_resolved',fields_resolved,'evidence_count',evidence_count,'source_record_id',source_record_id,
      'evidence_id',parsed_payload->>'evidence_id','event_at',operational_event_at
    ) order by operational_event_at desc),'[]'::jsonb) value
    from (select * from pipeline.layer2_enrichment_operational_ledger_v1
          where (v_country is null or country_code=v_country) order by operational_event_at desc nulls last limit v_limit) q
  )
  select jsonb_build_object(
    'observed_at',now(),'country_code',v_country,'coverage',(select value from coverage_json),
    'work',(select value from work),'hourly',(select value from hourly),'blockers',(select value from blockers),
    'stop_reasons',(select value from reasons),'providers',(select value from providers),
    'admissions',(select value from admissions),'recent_items',(select value from recent_items),
    'authority_note','Acquisition, admission and Search/publication are measured separately. Metrics do not authorise mutation.',
    'change_control_ref','CF-CHG-20260915-245'
  ) into v_result;
  return v_result;
end $$;
revoke all on function security.admin_enrichment_operations_read(jsonb) from public,anon;
grant execute on function security.admin_enrichment_operations_read(jsonb) to authenticated,service_role;

-- Preserve the current authoritative admin_read router and add one governed operation.
create or replace function public.admin_read(p_operation text,p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable set search_path='pg_catalog','public','security' as $$
declare v_result jsonb;v_id uuid;
begin
 if p_operation='platform_health' then return security.admin_platform_health_cf221(); end if;
 if p_operation='scholarship_ai' then return security.scholarship_ai_control_read_impl(coalesce(nullif(p_args->>'country_code',''),'AU')); end if;
 if p_operation='scholarship_runtime' then return security.admin_scholarship_runtime_read(p_args); end if;
 if p_operation='scholarship_runtime_uat' then return security.admin_scholarship_runtime_uat(coalesce(nullif(p_args->>'country_code',''),'AU')); end if;
 if p_operation='admin_filter_option_page' then return security.admin_filter_option_page(p_args); end if;
 if p_operation='dashboard' then return security.admin_dashboard_maturity(); end if;
 if p_operation='layer_status_summary' then return security.admin_layer_status_summary(); end if;
 if p_operation='catalogue_filter_page' then return security.admin_catalogue_filter_page(p_args); end if;
 if p_operation in ('provider_filters','course_filters') then return security.admin_catalogue_filter_options(p_operation,p_args); end if;
 if p_operation='evidence_page' then return security.admin_evidence_page(p_args); end if;
 if p_operation in ('evidence_filters','evidence_detail','evidence_observations','evidence_entities') then return security.admin_evidence_read(p_operation,p_args); end if;
 if p_operation='courses_page' then return security.admin_course_page_fast(p_args); end if;
 if p_operation='campuses_page' then return security.admin_campus_page_fast(p_args); end if;
 if p_operation in ('providers_page','scholarships_page') then return security.admin_catalogue_page(p_operation,p_args); end if;
 if p_operation in ('qilt_outcomes','qilt_filters','prisms_student_flow','prisms_filters') then return security.admin_insights_read(p_operation,p_args); end if;
 if p_operation='ranking_imports' then return security.admin_ranking_imports_read(p_args); end if;
 if p_operation in ('ranking_summary','ranking_filters','ranking_observations') then return security.admin_ranking_read(p_operation,p_args); end if;
 if p_operation in ('provider_asset_summary','provider_asset_coverage','provider_asset_context') then return security.admin_provider_asset_read(p_operation,p_args); end if;
 if p_operation in ('provider_contacts_page','provider_contact_detail','provider_contact_imports','provider_contact_import_detail') then return security.admin_provider_contact_read(p_operation,p_args); end if;
 if p_operation='contextual_compare' then return security.admin_contextual_compare(p_args); end if;
 if p_operation='reviews_page' then return security.admin_operational_page(p_operation,p_args); end if;
 if p_operation='layer2_dispatcher_tuning' then return security.admin_layer2_dispatcher_tuning_read_v1(p_args); end if;
 if p_operation='enrichment_operations' then return security.admin_enrichment_operations_read(p_args); end if;
 if p_operation='jobs_runtime' then return security.admin_jobs_runtime_read_v1(p_args); end if;
 if p_operation in ('reviews','jobs','sources') then return security.admin_operations_read(p_operation,p_args); end if;
 if p_operation='layer1_operations' then return security.admin_layer1_operations_read(p_args); end if;
 if p_operation='layer2_ops_alerts' then return security.layer2_operational_alerts_read(); end if;
 if p_operation='layer2_parent_runs' then return security.admin_layer2_parent_runs(coalesce(nullif(p_args->>'limit','')::integer,10)); end if;
 if p_operation='layer2_ops_overview' then return security.admin_layer2_ops_read('layer2_ops_overview',p_args); end if;
 if p_operation='layer2_ops_run_detail' then return security.admin_layer2_ops_read(p_operation,p_args); end if;
 if p_operation='layer2_profiles' and (p_args ? 'limit' or p_args ? 'offset' or p_args ? 'query' or p_args ? 'country' or p_args ? 'method' or p_args ? 'health') then return security.admin_layer2_profiles_page(p_args); end if;
 if p_operation in ('layer2_profiles','layer2_profile_detail') then return security.admin_layer2_config_read(p_operation,p_args); end if;
 if p_operation in ('layer2_acquisition_providers','layer2_provider_routes','layer2_provider_attempts') then return security.admin_layer2_provider_read(p_operation,p_args); end if;
 if p_operation='attributes' then return security.admin_pim_governance_read(p_args); end if;
 if p_operation in ('pipeline_overview','pipeline_jobs_page','pipeline_job_detail','pipeline_sources_page','pipeline_filters') then v_result:=security.admin_pipeline_ops_read(p_operation,p_args);return security.admin_pipeline_ops_sanitise_result(p_operation,v_result);end if;
 if p_operation in ('data_quality_overview','data_quality_exceptions','data_quality_quarantine') then return security.admin_data_quality_read(p_operation,p_args); end if;
 if p_operation in ('platform_readiness','platform_capacity','platform_environment_gates','platform_uat_catalogue','platform_workloads','platform_retention','platform_active_blocks') then return security.admin_platform_maturity_read(p_operation,p_args); end if;
 if p_operation='publication_overview' then return security.admin_publication_overview(); end if;
 if p_operation='provider_detail' then v_id:=nullif(p_args->>'id','')::uuid;return security.admin_provider_detail(v_id)||jsonb_build_object('contextual_insights',security.admin_contextual_insights_v2('provider',v_id))||jsonb_build_object('ranking_context',security.admin_provider_rankings(v_id,10))||jsonb_build_object('provider_asset_context',security.admin_provider_asset_read('provider_asset_context',jsonb_build_object('provider_id',v_id)))||jsonb_build_object('scholarship_context',security.admin_provider_scholarships(v_id));end if;
 if p_operation='campus_detail' then v_id:=nullif(p_args->>'id','')::uuid;return security.admin_campus_detail(v_id);end if;
 v_result:=security.admin_read_impl(p_operation,p_args);
 if p_operation='course_detail' then v_id:=nullif(p_args->>'id','')::uuid;return v_result||jsonb_build_object('fee_summary',security.admin_course_fee_summary(v_id))||jsonb_build_object('entry_summary',security.admin_course_entry_summary(v_id))||jsonb_build_object('taxonomy_summary',security.admin_course_taxonomy_summary(v_id))||jsonb_build_object('state_summary',security.admin_course_state_summary(v_id))||jsonb_build_object('contextual_insights',security.admin_contextual_insights_v2('course',v_id))||jsonb_build_object('ranking_context',security.admin_course_rankings(v_id,10));end if;
 if p_operation='scholarship_detail' then v_id:=nullif(p_args->>'id','')::uuid;return v_result||jsonb_build_object('semantic_summary',security.admin_scholarship_semantic_summary(v_id));end if;
 return v_result;
end $$;

revoke all on function public.admin_read(text,jsonb) from public,anon;
grant execute on function public.admin_read(text,jsonb) to authenticated,service_role;

comment on function security.admin_enrichment_operations_read(jsonb) is
'CF-245 rank-gated Enrichment Operations read bundle. Observability only; does not grant Layer 2, Layer 3, Layer 4, Search or Publication mutation authority.';
