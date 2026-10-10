-- CF-CHG-20260825-036
-- Preserve operator-visible freshness after moving the expensive aggregate rebuild
-- from every 15 minutes to off-peak daily + explicit post-ingestion refresh.

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
  v_reason text;
begin
  if v_country is not null and v_country not in ('AU','NZ') then
    raise exception 'unsupported Data Quality country scope: %',v_country using errcode='22023';
  end if;
  v_scope:=coalesce(v_country,'AU+NZ');
  select * into v_row from security.data_quality_overview_snapshots where scope_code=v_scope;
  if not found then
    raise exception 'Data Quality overview snapshot unavailable for scope %',v_scope using errcode='55000';
  end if;

  v_reason:=coalesce(v_row.payload#>>'{policy,reason}','Domain readiness is reported by governed domain.')
    ||' Aggregate snapshot computed at '||v_row.computed_at::text
    ||'; refreshed off-peak daily and after explicit post-ingestion refresh; exception drill-down is live.';

  return jsonb_set(v_row.payload,'{policy,reason}',to_jsonb(v_reason),true)
    || jsonb_build_object(
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
