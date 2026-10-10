create table if not exists private.zoho_integration_rate_windows (
  identity text not null,
  resource text not null,
  window_started_at timestamptz not null,
  request_count integer not null default 0 check (request_count >= 0),
  updated_at timestamptz not null default now(),
  primary key (identity, resource, window_started_at)
);

revoke all on table private.zoho_integration_rate_windows from public, anon, authenticated;

create or replace function api.zoho_integration_rate_check_v1(
  p_identity text,
  p_resource text,
  p_limit integer default 120,
  p_window_seconds integer default 60
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, private
as $$
declare
  v_identity text := nullif(trim(coalesce(p_identity,'')), '');
  v_resource text := nullif(trim(coalesce(p_resource,'')), '');
  v_limit integer := least(greatest(coalesce(p_limit,120),1),1000);
  v_window integer := least(greatest(coalesce(p_window_seconds,60),10),3600);
  v_now timestamptz := clock_timestamp();
  v_epoch bigint;
  v_start timestamptz;
  v_count integer;
  v_retry integer;
begin
  if v_identity is null or v_resource is null then
    raise exception using errcode='22023', message='identity_and_resource_required';
  end if;

  v_epoch := floor(extract(epoch from v_now) / v_window)::bigint * v_window;
  v_start := to_timestamp(v_epoch);

  insert into private.zoho_integration_rate_windows(identity, resource, window_started_at, request_count, updated_at)
  values (v_identity, v_resource, v_start, 1, v_now)
  on conflict (identity, resource, window_started_at)
  do update set request_count = private.zoho_integration_rate_windows.request_count + 1,
                updated_at = excluded.updated_at
  returning request_count into v_count;

  v_retry := greatest(1, ceil(extract(epoch from (v_start + make_interval(secs => v_window) - v_now)))::integer);

  delete from private.zoho_integration_rate_windows
   where window_started_at < v_now - interval '1 day';

  return jsonb_build_object(
    'allowed', v_count <= v_limit,
    'count', v_count,
    'limit', v_limit,
    'window_seconds', v_window,
    'retry_after_seconds', case when v_count <= v_limit then 0 else v_retry end
  );
end;
$$;

revoke all on function api.zoho_integration_rate_check_v1(text,text,integer,integer) from public;
revoke all on function api.zoho_integration_rate_check_v1(text,text,integer,integer) from anon;
revoke all on function api.zoho_integration_rate_check_v1(text,text,integer,integer) from authenticated;
grant execute on function api.zoho_integration_rate_check_v1(text,text,integer,integer) to service_role;
