-- CF-CHG-20260825-036 / inherited M1 performance hardening
-- The full Data Quality overview recomputes AU+NZ, AU and NZ serially across the
-- governed catalogue. At AU+NZ scale this can consume tens of seconds and was
-- observed contending with interactive admin_read calls when scheduled every 15m.
-- Keep the overview explicitly cached and move the full rebuild to an off-peak
-- daily cadence. The service-role refresh function remains available for an
-- explicit post-ingestion refresh when fresher summary state is required.

select cron.unschedule('coursefinder-data-quality-overview-refresh')
where exists (
  select 1 from cron.job where jobname='coursefinder-data-quality-overview-refresh'
);

select cron.schedule(
  'coursefinder-data-quality-overview-refresh',
  '17 16 * * *',
  'select security.refresh_data_quality_overview_snapshots();'
);

create or replace function security.data_quality_overview_cached(p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, security
as $$
declare
  v_country text:=nullif(upper(btrim(coalesce(p_args->>'country_code',''))),'');
  v_scope text;
  v_row security.data_quality_overview_snapshots%rowtype;
begin
  if v_country is not null and v_country not in ('AU','NZ') then
    raise exception 'unsupported Data Quality country scope: %',v_country using errcode='22023';
  end if;
  v_scope:=coalesce(v_country,'AU+NZ');
  select * into v_row from security.data_quality_overview_snapshots where scope_code=v_scope;
  if not found then
    raise exception 'Data Quality overview snapshot unavailable for scope %',v_scope using errcode='55000';
  end if;
  return v_row.payload||jsonb_build_object(
    'snapshot',jsonb_build_object(
      'scope_code',v_row.scope_code,
      'computed_at',v_row.computed_at,
      'compute_duration_ms',v_row.compute_duration_ms,
      'refresh_interval_minutes',1440,
      'refresh_mode','off_peak_daily_plus_explicit_post_ingestion',
      'live_drilldown',true
    )
  );
end
$$;

revoke all on function security.data_quality_overview_cached(jsonb) from public,anon,authenticated,service_role;
