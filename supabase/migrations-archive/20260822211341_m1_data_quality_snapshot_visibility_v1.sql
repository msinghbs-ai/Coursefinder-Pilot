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
    ||'; refreshed every 15 minutes; exception drill-down is live.';
  return jsonb_set(v_row.payload,'{policy,reason}',to_jsonb(v_reason),true)
    || jsonb_build_object('snapshot',jsonb_build_object('scope_code',v_row.scope_code,'computed_at',v_row.computed_at,'compute_duration_ms',v_row.compute_duration_ms,'refresh_interval_minutes',15,'live_drilldown',true));
end
$$;
