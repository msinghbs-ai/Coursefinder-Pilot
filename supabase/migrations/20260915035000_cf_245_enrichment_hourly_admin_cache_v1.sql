-- CF-CHG-20260915-245 — deployed UAT recovery for Enrichment Operations reporting.
-- Root cause: the governed layer2_enrichment_hourly_v1 projection takes ~5.4s by
-- itself on current Pilot data. When the Layer 2 workspace loads concurrent reads,
-- authenticated RPCs can exceed the 8s statement timeout and return HTTP 500.
--
-- This migration changes reporting mechanics only. It does not alter enrichment
-- scheduling, concurrency, provider routing/budgets, Layer authority, canonical
-- admission, Search/publication policy, or Evidence access controls.

create table if not exists pipeline.layer2_enrichment_hourly_admin_cache_v1
as select * from pipeline.layer2_enrichment_hourly_v1 with no data;

alter table pipeline.layer2_enrichment_hourly_admin_cache_v1 enable row level security;
revoke all on pipeline.layer2_enrichment_hourly_admin_cache_v1 from public,anon,authenticated;
grant select,insert,update,delete on pipeline.layer2_enrichment_hourly_admin_cache_v1 to service_role;

create unique index if not exists layer2_enrichment_hourly_admin_cache_v1_uq
  on pipeline.layer2_enrichment_hourly_admin_cache_v1(hour_utc,country_code,domain);
create index if not exists layer2_enrichment_hourly_admin_cache_v1_recent_idx
  on pipeline.layer2_enrichment_hourly_admin_cache_v1(hour_utc desc,country_code,domain);

create or replace function public.svc_cf245_refresh_hourly_admin_cache()
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','pipeline'
as $$
declare
  v_rows integer:=0;
begin
  if current_user not in('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;

  delete from pipeline.layer2_enrichment_hourly_admin_cache_v1
  where hour_utc < date_trunc('hour',now())-interval '8 days';

  delete from pipeline.layer2_enrichment_hourly_admin_cache_v1
  where hour_utc >= date_trunc('hour',now())-interval '168 hours';

  insert into pipeline.layer2_enrichment_hourly_admin_cache_v1
  select *
  from pipeline.layer2_enrichment_hourly_v1
  where hour_utc >= date_trunc('hour',now())-interval '168 hours';

  get diagnostics v_rows=row_count;
  return jsonb_build_object(
    'ok',true,
    'rows',v_rows,
    'observed_at',now(),
    'change_control_ref','CF-CHG-20260915-245'
  );
end $$;

revoke all on function public.svc_cf245_refresh_hourly_admin_cache() from public,anon,authenticated;
grant execute on function public.svc_cf245_refresh_hourly_admin_cache() to service_role;

-- Refresh independently from enrichment scheduling. The cache is observational.
do $$
begin
  if exists(select 1 from cron.job where jobname='coursefinder-cf245-enrichment-hourly-admin-cache') then
    perform cron.unschedule((select jobid from cron.job where jobname='coursefinder-cf245-enrichment-hourly-admin-cache' limit 1));
  end if;
  perform cron.schedule(
    'coursefinder-cf245-enrichment-hourly-admin-cache',
    '12 * * * *',
    'select public.svc_cf245_refresh_hourly_admin_cache();'
  );
end $$;

-- Seed the reporting cache before the browser path is switched.
select public.svc_cf245_refresh_hourly_admin_cache();

-- Preserve the accepted CF-245 admin-read response contract and all role checks;
-- only substitute the expensive hourly projection with the persisted observational
-- cache. The earlier migration deterministically defines this function before this
-- corrective migration, so the replacement is replay-safe in migration order.
do $$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('security.admin_enrichment_operations_read(jsonb)'::regprocedure)
    into v_def;
  if position('pipeline.layer2_enrichment_hourly_v1' in v_def)=0 then
    raise exception 'Expected CF-245 hourly projection reference not found; refusing semantic rewrite';
  end if;
  v_new:=replace(
    v_def,
    'pipeline.layer2_enrichment_hourly_v1',
    'pipeline.layer2_enrichment_hourly_admin_cache_v1'
  );
  execute v_new;
end $$;

revoke all on function security.admin_enrichment_operations_read(jsonb) from public,anon;
grant execute on function security.admin_enrichment_operations_read(jsonb) to authenticated,service_role;
