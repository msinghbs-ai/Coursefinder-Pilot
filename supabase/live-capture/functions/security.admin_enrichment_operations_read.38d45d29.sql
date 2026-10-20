CREATE OR REPLACE FUNCTION security.admin_enrichment_operations_read(p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline', 'search', 'catalogue', 'ref'
AS $function$
declare
  v_rank integer:=security.current_role_rank();
  v_country text:=upper(nullif(btrim(coalesce(p_args->>'country_code','')),''));
  v_hours integer:=least(greatest(coalesce(nullif(p_args->>'hours','')::integer,24),1),168);
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,30),1),100);
  v_result jsonb;
begin
  if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
  if v_country is not null and not (v_country = any(security.catalogue_country_codes_v1())) then raise exception 'unsupported country' using errcode='22023'; end if;

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
      'country_code',c.country_code,'field_key',c.field_key,'current',c.covered_count,'total',c.total_courses,
      'coverage_pct',case when c.total_courses>0 then round((100*c.covered_count::numeric/c.total_courses),2) else 0 end,
      'remaining',greatest(c.total_courses-c.covered_count,0),
      'added_hour',case when ph.covered_count is null then null else c.covered_count-ph.covered_count end,
      'added_day',case when pd.covered_count is null then null else c.covered_count-pd.covered_count end,
      'queueable',c.queueable_count,'blocked',c.blocked_count,'awaiting_qualification',c.awaiting_count,
      'snapshot_hour',c.snapshot_hour,'hour_baseline_at',ph.snapshot_hour,'day_baseline_at',pd.snapshot_hour
    ) order by c.country_code,c.field_key),'[]'::jsonb) value
    from current_cov c left join prior_hour ph using(country_code,field_key) left join prior_day pd using(country_code,field_key)
  ), scoped_recent_items as (
    select ri.*
    from pipeline.layer2_run_items ri
    join catalogue.courses c on ri.entity_type='course' and c.id=ri.entity_id
    join catalogue.providers p on p.id=c.provider_id
    join ref.countries co on co.id=p.country_id
    where (v_country is null or trim(co.iso_alpha2)=v_country)
  ), work as (
    select jsonb_build_object(
      'queued',(select count(*) from scoped_recent_items where status='queued'),
      'processing',(select count(*) from scoped_recent_items where status in('running','discovering','acquiring','extracting')),
      'fetched',(select count(*) from pipeline.layer2_provider_attempts pa where pa.status in('completed','success','succeeded') and coalesce(pa.completed_at,pa.started_at,pa.created_at)>=now()-interval '24 hours'),
      'fetch_failures',(select count(*) from pipeline.layer2_provider_attempts pa where pa.status in('failed','error','blocked') and coalesce(pa.completed_at,pa.started_at,pa.created_at)>=now()-interval '24 hours'),
      'evidence_24h',(select count(*) from pipeline.evidence_artifacts e where e.job_id is not null and e.captured_at>=now()-interval '24 hours' and exists(select 1 from pipeline.layer2_run_items x where x.job_id=e.job_id)),
      'layer3_24h',(select count(*) from scoped_recent_items where status='layer3_required' and coalesce(completed_at,updated_at,created_at)>=now()-interval '24 hours'),
      'admitted_source_records_24h',(select count(*) from pipeline.course_fact_source_records sr where sr.applied_at>=now()-interval '24 hours'),
      'http_429_24h',(select count(*) from pipeline.layer2_provider_attempts pa where pa.response_http_status=429 and coalesce(pa.completed_at,pa.started_at,pa.created_at)>=now()-interval '24 hours'),
      'http_5xx_24h',(select count(*) from pipeline.layer2_provider_attempts pa where pa.response_http_status>=500 and coalesce(pa.completed_at,pa.started_at,pa.created_at)>=now()-interval '24 hours'),
      'vendor_units_24h',(select coalesce(sum(coalesce((nullif(pa.metrics->>'vendor_units',''))::numeric,0)),0) from pipeline.layer2_provider_attempts pa where coalesce(pa.completed_at,pa.started_at,pa.created_at)>=now()-interval '24 hours'),
      'vendor_cost_usd_24h',(select coalesce(sum(coalesce((nullif(pa.metrics->>'estimated_request_cost_usd',''))::numeric,0)),0) from pipeline.layer2_provider_attempts pa where coalesce(pa.completed_at,pa.started_at,pa.created_at)>=now()-interval '24 hours')
    ) value
  ), hourly as (
    select coalesce(jsonb_agg(to_jsonb(h) order by h.hour_utc),'[]'::jsonb) value
    from (select * from pipeline.layer2_enrichment_hourly_admin_cache_v1
          where hour_utc>=date_trunc('hour',now())-(v_hours||' hours')::interval
            and (v_country is null or country_code=v_country)
          order by hour_utc desc limit v_hours*4) h
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
    select coalesce(jsonb_agg(jsonb_build_object('reason',reason,'items',items,'fields_targeted',fields_targeted,'fields_resolved',fields_resolved) order by items desc),'[]'::jsonb) value
    from (
      select case when status='blocked' then coalesce(nullif(failure_class,''),'runtime_blocked') when status='layer3_required' then 'layer3_required' when status='resolved_l2' then 'resolved_l2' else coalesce(nullif(outcome_code,''),status,'unknown') end reason,
             count(*)::bigint items,sum(coalesce(fields_targeted,0))::bigint fields_targeted,sum(coalesce(fields_resolved,0))::bigint fields_resolved
      from scoped_recent_items
      where coalesce(completed_at,updated_at,created_at)>=now()-interval '7 days'
      group by 1 order by items desc limit 30
    ) q
  ), providers as (
    select coalesce(jsonb_agg(jsonb_build_object('provider',provider_key,'attempts',attempts,'succeeded',succeeded,'failed',failed,'vendor_units',vendor_units,'cost_usd',cost_usd,'p50_ms',p50_ms,'p95_ms',p95_ms,'retries',retries) order by attempts desc),'[]'::jsonb) value
    from (
      select coalesce(ap.provider_key,'unknown') provider_key,count(*)::bigint attempts,
        count(*) filter(where pa.status in('completed','success','succeeded'))::bigint succeeded,
        count(*) filter(where pa.status in('failed','error','blocked'))::bigint failed,
        coalesce(sum(coalesce((nullif(pa.metrics->>'vendor_units',''))::numeric,0)),0)::numeric vendor_units,
        coalesce(sum(coalesce((nullif(pa.metrics->>'estimated_request_cost_usd',''))::numeric,0)),0)::numeric cost_usd,
        percentile_cont(.5) within group(order by extract(epoch from (pa.completed_at-pa.started_at))*1000) filter(where pa.completed_at is not null and pa.started_at is not null) p50_ms,
        percentile_cont(.95) within group(order by extract(epoch from (pa.completed_at-pa.started_at))*1000) filter(where pa.completed_at is not null and pa.started_at is not null) p95_ms,
        0::bigint retries
      from pipeline.layer2_provider_attempts pa left join pipeline.layer2_acquisition_providers ap on ap.id=pa.acquisition_provider_id
      where coalesce(pa.completed_at,pa.started_at,pa.created_at)>=now()-interval '7 days'
      group by ap.provider_key order by attempts desc limit 20
    ) q
  ), admissions as (
    select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'course_id',a.course_id,'field_key',a.field_key,'status',a.status,'reason_code',a.reason_code,'canonical_changed',a.canonical_changed,'search_admission_eligible',a.search_admission_eligible,'evidence_id',a.evidence_id,'decided_at',a.decided_at,'provider_name',p.display_name,'course_title',c.display_title) order by a.decided_at desc),'[]'::jsonb) value
    from (select * from pipeline.layer2_field_admissions order by decided_at desc limit v_limit) a join catalogue.courses c on c.id=a.course_id join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id where v_country is null or trim(co.iso_alpha2)=v_country
  ), recent_items as (
    select coalesce(jsonb_agg(jsonb_build_object('run_item_id',r.id,'job_id',r.job_id,'course_id',c.id,'course_code',c.course_code,'provider_name',p.display_name,'country_code',trim(co.iso_alpha2),'status',r.status,'stop_reason',case when r.status='blocked' then coalesce(nullif(r.failure_class,''),'runtime_blocked') when r.status='layer3_required' then 'layer3_required' when r.status='resolved_l2' then 'resolved_l2' else coalesce(nullif(r.outcome_code,''),r.status,'unknown') end,'fields_targeted',r.fields_targeted,'fields_resolved',r.fields_resolved,'evidence_count',(select count(*) from pipeline.evidence_artifacts e where e.job_id=r.job_id),'source_record_id',null,'evidence_id',(select e.id from pipeline.evidence_artifacts e where e.job_id=r.job_id order by e.captured_at desc limit 1),'event_at',coalesce(r.completed_at,r.updated_at,r.created_at)) order by coalesce(r.completed_at,r.updated_at,r.created_at) desc),'[]'::jsonb) value
    from (select * from scoped_recent_items order by coalesce(completed_at,updated_at,created_at) desc nulls last limit v_limit) r
    join catalogue.courses c on c.id=r.entity_id join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
  )
  select jsonb_build_object('observed_at',now(),'country_code',v_country,'coverage',(select value from coverage_json),'work',(select value from work),'hourly',(select value from hourly),'blockers',(select value from blockers),'stop_reasons',(select value from reasons),'providers',(select value from providers),'admissions',(select value from admissions),'recent_items',(select value from recent_items),'authority_note','Acquisition, admission and Search/publication are measured separately. Metrics do not authorise mutation.','metrics_note','Current work, stop reasons and provider summaries are bounded from persisted Layer 2 base tables; hourly historical funnel remains the governed CF-245 operational ledger projection.','change_control_ref','CF-CHG-20260915-245') into v_result;
  return v_result;
end $function$
