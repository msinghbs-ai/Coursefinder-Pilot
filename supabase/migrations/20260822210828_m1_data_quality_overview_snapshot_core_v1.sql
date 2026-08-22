create table if not exists security.data_quality_overview_snapshots (
  scope_code text primary key check (scope_code in ('AU+NZ','AU','NZ')),
  country_code text null check (country_code is null or country_code in ('AU','NZ')),
  payload jsonb not null,
  computed_at timestamptz not null,
  compute_duration_ms numeric(12,2) not null,
  refreshed_by text not null default 'scheduled'
);
alter table security.data_quality_overview_snapshots enable row level security;
revoke all on security.data_quality_overview_snapshots from public, anon, authenticated;
grant select, insert, update on security.data_quality_overview_snapshots to service_role;

create or replace function security.refresh_data_quality_overview_snapshots()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, security
set statement_timeout = '120s'
set work_mem = '128MB'
as $$
declare
  r record;
  v_started timestamptz;
  v_finished timestamptz;
  v_payload jsonb;
  v_result jsonb := '[]'::jsonb;
begin
  for r in select * from (values
    ('AU+NZ'::text,null::text,'{}'::jsonb),
    ('AU'::text,'AU'::text,'{"country_code":"AU"}'::jsonb),
    ('NZ'::text,'NZ'::text,'{"country_code":"NZ"}'::jsonb)
  ) v(scope_code,country_code,args)
  loop
    v_started:=clock_timestamp();
    v_payload:=security.data_quality_overview_impl(r.args);
    v_finished:=clock_timestamp();
    insert into security.data_quality_overview_snapshots(scope_code,country_code,payload,computed_at,compute_duration_ms,refreshed_by)
    values(r.scope_code,r.country_code,v_payload,v_finished,round((extract(epoch from (v_finished-v_started))*1000.0)::numeric,2),current_user)
    on conflict(scope_code) do update set country_code=excluded.country_code,payload=excluded.payload,computed_at=excluded.computed_at,compute_duration_ms=excluded.compute_duration_ms,refreshed_by=excluded.refreshed_by;
    v_result:=v_result||jsonb_build_array(jsonb_build_object('scope_code',r.scope_code,'computed_at',v_finished,'compute_duration_ms',round((extract(epoch from (v_finished-v_started))*1000.0)::numeric,2)));
  end loop;
  return jsonb_build_object('snapshots',v_result,'completed_at',clock_timestamp());
end
$$;
revoke all on function security.refresh_data_quality_overview_snapshots() from public, anon, authenticated;
grant execute on function security.refresh_data_quality_overview_snapshots() to service_role;

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
  if v_country is not null and v_country not in ('AU','NZ') then raise exception 'unsupported Data Quality country scope: %',v_country using errcode='22023'; end if;
  v_scope:=coalesce(v_country,'AU+NZ');
  select * into v_row from security.data_quality_overview_snapshots where scope_code=v_scope;
  if not found then raise exception 'Data Quality overview snapshot unavailable for scope %',v_scope using errcode='55000'; end if;
  return v_row.payload||jsonb_build_object('snapshot',jsonb_build_object('scope_code',v_row.scope_code,'computed_at',v_row.computed_at,'compute_duration_ms',v_row.compute_duration_ms,'refresh_interval_minutes',15,'live_drilldown',true));
end
$$;
revoke all on function security.data_quality_overview_cached(jsonb) from public, anon, authenticated, service_role;

select security.refresh_data_quality_overview_snapshots();

create or replace function security.admin_data_quality_read(p_operation text,p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, security, auth
as $$
declare v_rank int:=0;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
  if p_operation='data_quality_overview' then return security.data_quality_overview_cached(p_args); end if;
  if p_operation='data_quality_exceptions' then return security.data_quality_exceptions_impl(p_args); end if;
  raise exception 'unsupported data quality operation: %',p_operation using errcode='22023';
end
$$;
