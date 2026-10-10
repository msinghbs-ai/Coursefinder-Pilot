-- Package 8.2 (Decision 153): hourly resource observations, compute profile, cost model and the
-- Resources read for Administration. The recorder reads database statistics and small time-bounded
-- sums only (no table scans), so it adds negligible load.
create table if not exists pipeline.platform_compute_profile(
  id int primary key default 1 check (id=1),
  compute_size text not null, memory_bytes bigint not null, max_connections int not null,
  baseline_iops int not null, baseline_mb_s int not null, notes text,
  updated_by uuid, updated_at timestamptz not null default now());
insert into pipeline.platform_compute_profile(id,compute_size,memory_bytes,max_connections,baseline_iops,baseline_mb_s,notes)
values (1,'Micro',1073741824,60,500,11,'Upgraded from Nano on 26 Sep 2026 (Decision 153)') on conflict (id) do nothing;

create table if not exists pipeline.platform_cost_model(
  item_key text primary key,
  label text not null,
  category text not null check (category in ('platform','compute','storage','acquisition','ai','other')),
  basis text not null check (basis in ('fixed_monthly','usage_actual','credit')),
  monthly_usd numeric(12,2) not null default 0,
  notes text,
  updated_by uuid, updated_at timestamptz not null default now());
insert into pipeline.platform_cost_model(item_key,label,category,basis,monthly_usd,notes) values
 ('supabase_plan','Supabase Pro plan','platform','fixed_monthly',25,'Organisation plan'),
 ('supabase_compute','Supabase compute (Micro)','compute','fixed_monthly',10,'Hourly-billed; ~US$10/month'),
 ('supabase_compute_credit','Supabase compute credit','compute','credit',-10,'Included with the Pro plan'),
 ('supabase_storage','Supabase storage (evidence files)','storage','fixed_monthly',0,'Within the plan allowance; review as evidence grows'),
 ('firecrawl_plan','Firecrawl plan','acquisition','fixed_monthly',0,'Set to your Firecrawl subscription price'),
 ('openrouter_usage','OpenRouter AI usage','ai','usage_actual',0,'Actual cost recorded from Layer 3 calls')
on conflict (item_key) do nothing;

create table if not exists pipeline.platform_resource_observations(
  observed_at timestamptz primary key,
  db_bytes bigint not null, memory_bytes bigint not null, compute_size text not null,
  cache_hit_pct numeric(6,2), connections int, active_connections int,
  cron_runs int, cron_failures int, cron_max_seconds numeric(10,1), cron_max_concurrent int,
  http_requests int,
  acquisition jsonb not null default '[]'::jsonb, acquisition_units_mtd numeric, acquisition_cost_mtd_usd numeric(12,4),
  ai_calls int, ai_tokens bigint, ai_cost_usd numeric(12,4), ai_cost_mtd_usd numeric(12,4),
  largest_tables jsonb not null default '[]'::jsonb);
alter table pipeline.platform_compute_profile enable row level security;
alter table pipeline.platform_cost_model enable row level security;
alter table pipeline.platform_resource_observations enable row level security;
revoke all on pipeline.platform_compute_profile, pipeline.platform_cost_model, pipeline.platform_resource_observations from public, anon, authenticated;

create or replace function security.platform_resource_observe_v1()
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline','cron','net'
as $$
declare h timestamptz := date_trunc('hour', now()); h0 timestamptz := date_trunc('hour', now()) - interval '1 hour';
  m timestamptz := date_trunc('month', now()); cp pipeline.platform_compute_profile%rowtype; r pipeline.platform_resource_observations%rowtype;
begin
  select * into cp from pipeline.platform_compute_profile where id=1;
  r.observed_at := h; r.memory_bytes := cp.memory_bytes; r.compute_size := cp.compute_size;
  r.db_bytes := pg_database_size(current_database());
  select round(100.0*sum(blks_hit)/nullif(sum(blks_hit)+sum(blks_read),0),2) into r.cache_hit_pct from pg_stat_database where datname=current_database();
  select count(*), count(*) filter (where state='active') into r.connections, r.active_connections from pg_stat_activity where backend_type='client backend';
  select count(*), count(*) filter (where status not in ('succeeded','running')), round(max(extract(epoch from coalesce(end_time,now())-start_time))::numeric,1)
    into r.cron_runs, r.cron_failures, r.cron_max_seconds from cron.job_run_details where start_time >= h0 and start_time < h;
  select coalesce(max(c),0) into r.cron_max_concurrent from (
    select (select count(*) from cron.job_run_details b where b.start_time >= h0 - interval '1 hour' and b.start_time <= a.start_time and coalesce(b.end_time,now()) > a.start_time) c
    from cron.job_run_details a where a.start_time >= h0 and a.start_time < h) z;
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
end $$;
revoke all on function security.platform_resource_observe_v1() from public, anon, authenticated;

-- Resources read for Administration (PIM Admin and above); editing the cost model and compute profile is Platform Admin.
create or replace function public.admin_platform_resources_read_v1(p_days int default 30)
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog','security','pipeline','public'
as $$
declare v jsonb; d int := greatest(7,least(coalesce(p_days,30),180)); cp pipeline.platform_compute_profile%rowtype; growth numeric; latest pipeline.platform_resource_observations%rowtype;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if security.current_role_rank() < 5 then raise exception 'PIM Admin role is required' using errcode='42501'; end if;
  select * into cp from pipeline.platform_compute_profile where id=1;
  select * into latest from pipeline.platform_resource_observations order by observed_at desc limit 1;
  with daily as (select date_trunc('day',observed_at) dd, max(db_bytes) b from pipeline.platform_resource_observations where observed_at >= now()-make_interval(days=>d) group by 1)
  select regr_slope(b, extract(epoch from dd)/86400.0) into growth from daily;
  select jsonb_build_object(
    'compute', to_jsonb(cp) - 'updated_by',
    'latest', to_jsonb(latest),
    'memory_ratio', round(latest.db_bytes::numeric/nullif(cp.memory_bytes,0),2),
    'growth_bytes_per_day', round(coalesce(growth,0)),
    'days_until_memory', case when coalesce(growth,0) > 0 and latest.db_bytes < cp.memory_bytes then floor((cp.memory_bytes-latest.db_bytes)/growth) end,
    'thresholds', (select to_jsonb(p) - 'notification_target' from pipeline.platform_capacity_policy p where environment='pilot'),
    'daily', coalesce((select jsonb_agg(x order by x->>'day') from (
        select jsonb_build_object('day',date_trunc('day',observed_at)::date,'db_bytes',max(db_bytes),'cache_hit_pct',min(cache_hit_pct),
          'cron_failures',sum(cron_failures),'cron_max_seconds',max(cron_max_seconds),'cron_max_concurrent',max(cron_max_concurrent),
          'acquisition_units',sum(coalesce((select sum((a->>'units')::numeric) from jsonb_array_elements(acquisition) a),0)),
          'ai_cost_usd',sum(ai_cost_usd)) x
        from pipeline.platform_resource_observations where observed_at >= now()-make_interval(days=>d) group by date_trunc('day',observed_at)) z),'[]'::jsonb),
    'storage', (select jsonb_build_object('evidence_object_bytes',evidence_object_bytes,'evidence_objects',evidence_object_count,'orphans',orphan_object_count,'observed_at',observed_at)
                from pipeline.platform_capacity_observations order by observed_at desc limit 1),
    'costs', (select jsonb_build_object(
        'items', coalesce(jsonb_agg(jsonb_build_object('key',item_key,'label',label,'category',category,'basis',basis,
                 'monthly_usd', case when basis='usage_actual' and category='ai' then coalesce(latest.ai_cost_mtd_usd,0) else monthly_usd end,'notes',notes) order by category, item_key),'[]'::jsonb),
        'total_monthly_usd', sum(case when basis='usage_actual' and category='ai' then coalesce(latest.ai_cost_mtd_usd,0) else monthly_usd end),
        'acquisition_units_mtd', latest.acquisition_units_mtd, 'acquisition_cost_mtd_usd', latest.acquisition_cost_mtd_usd)
      from pipeline.platform_cost_model),
    'can_edit', security.current_role_rank() >= 6)
  into v;
  return v;
end $$;
revoke all on function public.admin_platform_resources_read_v1(int) from public, anon;
grant execute on function public.admin_platform_resources_read_v1(int) to authenticated, service_role;

create or replace function public.admin_platform_cost_model_save_v1(p_item_key text, p_monthly_usd numeric, p_notes text default null)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','security','pipeline','public'
as $$
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if security.current_role_rank() < 6 then raise exception 'Platform Admin role is required' using errcode='42501'; end if;
  if p_monthly_usd is null or p_monthly_usd < -100000 or p_monthly_usd > 100000 then raise exception 'monthly amount out of range' using errcode='22023'; end if;
  update pipeline.platform_cost_model set monthly_usd=p_monthly_usd, notes=coalesce(p_notes,notes), updated_by=auth.uid(), updated_at=now()
   where item_key=p_item_key and basis<>'usage_actual';
  if not found then raise exception 'unknown or usage-based cost item' using errcode='22023'; end if;
  return public.admin_platform_resources_read_v1(30);
end $$;
revoke all on function public.admin_platform_cost_model_save_v1(text,numeric,text) from public, anon;
grant execute on function public.admin_platform_cost_model_save_v1(text,numeric,text) to authenticated, service_role;

select cron.unschedule(jobid) from cron.job where jobname='platform-resource-observe';
select cron.schedule('platform-resource-observe','0 * * * *',$c$select security.platform_resource_observe_v1();$c$);

-- Runs cut off by a restart have no end time: count only finished runs, or runs still in progress.
do $patch$
declare d text; n int;
  a1 constant text := 'round(max(extract(epoch from coalesce(end_time,now())-start_time))::numeric,1)';
  b1 constant text := 'round(max(extract(epoch from coalesce(end_time, case when status in (''running'',''starting'',''sending'',''connecting'') then now() end)-start_time))::numeric,1)';
  a2 constant text := 'and coalesce(b.end_time,now()) > a.start_time';
  b2 constant text := 'and coalesce(b.end_time, case when b.status in (''running'',''starting'',''sending'',''connecting'') then now() else b.start_time end) > a.start_time';
begin
  select pg_get_functiondef('security.platform_resource_observe_v1()'::regprocedure) into d;
  n := (length(d)-length(replace(d,a1,'')))/length(a1); if n<>1 then raise exception 'a1 found % times', n; end if;
  n := (length(d)-length(replace(d,a2,'')))/length(a2); if n<>1 then raise exception 'a2 found % times', n; end if;
  execute replace(replace(d,a1,b1),a2,b2);
end $patch$;
