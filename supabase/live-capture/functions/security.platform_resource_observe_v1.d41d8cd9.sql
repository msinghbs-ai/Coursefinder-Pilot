CREATE OR REPLACE FUNCTION security.platform_resource_observe_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'cron', 'net'
AS $function$
declare h timestamptz := date_trunc('hour', now()); h0 timestamptz := date_trunc('hour', now()) - interval '1 hour';
  m timestamptz := date_trunc('month', now()); cp pipeline.platform_compute_profile%rowtype; r pipeline.platform_resource_observations%rowtype;
begin
  select * into cp from pipeline.platform_compute_profile where id=1;
  r.observed_at := h; r.memory_bytes := cp.memory_bytes; r.compute_size := cp.compute_size;
  r.db_bytes := pg_database_size(current_database());
  select round(100.0*sum(blks_hit)/nullif(sum(blks_hit)+sum(blks_read),0),2) into r.cache_hit_pct from pg_stat_database where datname=current_database();
  select count(*), count(*) filter (where state='active') into r.connections, r.active_connections from pg_stat_activity where backend_type='client backend';
  select count(*), count(*) filter (where status not in ('succeeded','running')), round(max(extract(epoch from coalesce(end_time, case when status in ('running','starting','sending','connecting') then now() end)-start_time))::numeric,1)
    into r.cron_runs, r.cron_failures, r.cron_max_seconds from cron.job_run_details where start_time >= h0 and start_time < h;
  select coalesce(max(c) filter (where t >= h0 and t < h and d = 1),0) into r.cron_max_concurrent from (
    select e.t, e.d, sum(e.d) over (order by e.t, e.d desc) c from (
      select b.start_time t, 1 d from cron.job_run_details b where b.start_time >= h0 - interval '1 hour' and b.start_time < h
      union all
      select coalesce(b.end_time, case when b.status in ('running','starting','sending','connecting') then now() else b.start_time end), -1
        from cron.job_run_details b where b.start_time >= h0 - interval '1 hour' and b.start_time < h) e) z;
  select count(*) into r.http_requests from net._http_response where created >= h0 and created < h;
  select coalesce(jsonb_agg(jsonb_build_object('provider',coalesce(ap.provider_key,'unknown'),'units',u,'cost_usd',cst)),'[]'::jsonb) into r.acquisition
    from (select ri.selected_provider_id, sum(coalesce(ri.vendor_units,0)) u, sum(coalesce(ri.vendor_cost_usd,0)) cst
          from pipeline.layer2_run_items ri where ri.completed_at >= h0 and ri.completed_at < h group by 1) x
    left join pipeline.layer2_acquisition_providers ap on ap.id=x.selected_provider_id;
  select sum(coalesce(vendor_units,0)), sum(coalesce(vendor_cost_usd,0)) into r.acquisition_units_mtd, r.acquisition_cost_mtd_usd
    from pipeline.layer2_run_items where completed_at >= m;
  select count(*), sum(coalesce(input_tokens,0)+coalesce(output_tokens,0)), sum(coalesce(estimated_cost_usd,0)) into r.ai_calls, r.ai_tokens, r.ai_cost_usd
    from (select input_tokens, output_tokens, estimated_cost_usd from pipeline.layer3_interpretations where call_completed_at >= h0 and call_completed_at < h
          union all select input_tokens, output_tokens, estimated_cost_usd from pipeline.layer3_quality_benchmark_runs where completed_at >= h0 and completed_at < h) z;
  select coalesce(sum(estimated_cost_usd),0) into r.ai_cost_mtd_usd
    from (select estimated_cost_usd from pipeline.layer3_interpretations where call_completed_at >= m
          union all select estimated_cost_usd from pipeline.layer3_quality_benchmark_runs where completed_at >= m) z;
  select coalesce(jsonb_agg(jsonb_build_object('table',t,'bytes',b) order by b desc),'[]'::jsonb) into r.largest_tables
    from (select n.nspname||'.'||c.relname t, pg_total_relation_size(c.oid) b from pg_class c join pg_namespace n on n.oid=c.relnamespace
          where c.relkind='r' and n.nspname not in ('pg_catalog','information_schema') order by 2 desc limit 5) z;
  insert into pipeline.platform_resource_observations select r.* on conflict (observed_at) do update set
    db_bytes=excluded.db_bytes, cache_hit_pct=excluded.cache_hit_pct, connections=excluded.connections, active_connections=excluded.active_connections,
    cron_runs=excluded.cron_runs, cron_failures=excluded.cron_failures, cron_max_seconds=excluded.cron_max_seconds, cron_max_concurrent=excluded.cron_max_concurrent,
    http_requests=excluded.http_requests, acquisition=excluded.acquisition, acquisition_units_mtd=excluded.acquisition_units_mtd, acquisition_cost_mtd_usd=excluded.acquisition_cost_mtd_usd,
    ai_calls=excluded.ai_calls, ai_tokens=excluded.ai_tokens, ai_cost_usd=excluded.ai_cost_usd, ai_cost_mtd_usd=excluded.ai_cost_mtd_usd, largest_tables=excluded.largest_tables;
  delete from pipeline.platform_resource_observations where observed_at < now() - interval '180 days';
  return to_jsonb(r);
end $function$
