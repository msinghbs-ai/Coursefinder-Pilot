-- CF-247 s1174 (S1-RM-Design; SS-Programme-Control P0, 26 Nov 2026 14:25 AEDT: Data Delivery performance).
-- Measured live 14:30 AEDT: the screen read security.data_delivery_v1 ran four live-count helpers on every call: data_delivery_cdesc_stages_v1 8.6 s, data_delivery_aer_v1 1.8 s,
-- data_delivery_intake_v1 1.4 s, data_delivery_pdesc_v1 0.6 s.
--   1. pipeline.data_delivery_helper_snapshots (one row per helper): the last good result, when it was counted, how long it took, and the last error and its time.
--   2. The existing background count security.data_delivery_refresh_v1 (job data-delivery) counts each helper again after data_delivery.refresh_minutes; a failed count keeps the
--      last good result and records the error, as for the other Data Delivery counts.
--   3. security.data_delivery_v1 reads the snapshots; each helper's response is the same object as before (contract unchanged). If a snapshot is missing it counts live once.
--      New top-level key snapshots: per helper as_at, took_ms, error, failed_at (freshness and error reporting).
--   Read-only closing checks; the first fill below only writes the snapshot rows.
-- G1: no new job or scheduler (the existing data-delivery job). G2: the existing setting. G3: no consumer API object touched (checked). No lock removed; cron ceiling checked.
-- Replaces: the live helper calls inside security.data_delivery_v1; security.data_delivery_refresh_v1 (one block added). Both md5 guarded.
-- Retires: none.
set local lock_timeout = '5s';  -- fixed: lock wait for the function replaces
set local statement_timeout = '120s';  -- fixed: the first fill (about 13 s) and the checks

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'guard: consumer API not at baseline: %', v; end if;
  if md5(pg_get_functiondef('security.data_delivery_v1()'::regprocedure)) <> '3dac30bc7f5239a2536c0b1f1b15d1d4' then raise exception 'guard: data_delivery_v1 changed'; end if;
  if md5(pg_get_functiondef('security.data_delivery_refresh_v1(boolean)'::regprocedure)) <> '4ef07c81650790ec305116240a94249a' then raise exception 'guard: data_delivery_refresh_v1 changed'; end if;
end $g$;
create temp table s1174_locks on commit drop as select count(*) n from pipeline.manual_locks;

create table if not exists pipeline.data_delivery_helper_snapshots (
  helper text primary key check (helper in ('cdesc_stages', 'intake', 'aer', 'pdesc')),
  rows jsonb,
  measured_at timestamptz,
  took_ms integer,
  error text,
  failed_at timestamptz);
comment on table pipeline.data_delivery_helper_snapshots is 'Data Delivery (s1174): last good result of each heavy helper, counted in the background by security.data_delivery_refresh_v1 and read by security.data_delivery_v1.';
alter table pipeline.data_delivery_helper_snapshots enable row level security;
revoke all on table pipeline.data_delivery_helper_snapshots from public, anon, authenticated;
grant select on table pipeline.data_delivery_helper_snapshots to service_role;

do $r$
declare d text := pg_get_functiondef('security.data_delivery_refresh_v1(boolean)'::regprocedure);
        a constant text := E'  -- PIM progress (s1167)';
        b constant text := E'  -- Data Delivery helpers (s1174): counted here in the background; the screen read takes the snapshot\n'
          || E'  declare v_h text; v_h0 timestamptz; v_hr jsonb;\n'
          || E'  begin\n'
          || E'    foreach v_h in array array[''cdesc_stages'', ''intake'', ''aer'', ''pdesc''] loop\n'
          || E'      continue when not p_force and exists (select 1 from pipeline.data_delivery_helper_snapshots x where x.helper = v_h and coalesce(x.failed_at, x.measured_at) >= now() - make_interval(mins => v_every));\n'
          || E'      v_h0 := clock_timestamp();\n'
          || E'      begin\n'
          || E'        execute format(''select security.data_delivery_%s_v1()'', v_h) into v_hr;\n'
          || E'        insert into pipeline.data_delivery_helper_snapshots as x(helper, rows, measured_at, took_ms, error, failed_at) values (v_h, v_hr, clock_timestamp(), (extract(epoch from clock_timestamp() - v_h0) * 1000)::int, null, null)\n'
          || E'          on conflict (helper) do update set rows = excluded.rows, measured_at = excluded.measured_at, took_ms = excluded.took_ms, error = null, failed_at = null;\n'
          || E'      exception when others then\n'
          || E'        insert into pipeline.data_delivery_helper_snapshots as x(helper, took_ms, error, failed_at) values (v_h, (extract(epoch from clock_timestamp() - v_h0) * 1000)::int, left(sqlerrm, 300), clock_timestamp())\n'
          || E'          on conflict (helper) do update set took_ms = excluded.took_ms, error = excluded.error, failed_at = excluded.failed_at;\n'
          || E'      end;\n'
          || E'    end loop;\n'
          || E'  end;\n' || a;
begin
  if (length(d) - length(replace(d, a, ''))) / length(a) <> 1 then raise exception 'guard: refresh anchor not found exactly once'; end if;
  execute replace(d, a, b);
end $r$;

do $s$
declare d text := pg_get_functiondef('security.data_delivery_v1()'::regprocedure); h text;
        ap constant text := E'''pim'', (select coalesce(j.pim';
begin
  foreach h in array array['cdesc_stages', 'pdesc', 'intake', 'aer'] loop
    if (length(d) - length(replace(d, format('security.data_delivery_%s_v1()', h), ''))) / length(format('security.data_delivery_%s_v1()', h)) <> 1 then raise exception 'guard: % call not found exactly once', h; end if;
    d := replace(d, format('security.data_delivery_%s_v1()', h),
                 format('coalesce((select x.rows from pipeline.data_delivery_helper_snapshots x where x.helper = %L), security.data_delivery_%s_v1())', h, h));
  end loop;
  if (length(d) - length(replace(d, ap, ''))) / length(ap) <> 1 then raise exception 'guard: pim anchor not found exactly once'; end if;
  d := replace(d, ap, E'''snapshots'', (select jsonb_object_agg(x.helper, jsonb_build_object(''as_at'', x.measured_at, ''took_ms'', x.took_ms, ''error'', x.error, ''failed_at'', x.failed_at)) from pipeline.data_delivery_helper_snapshots x), ' || ap);
  execute d;
end $s$;

-- first fill (snapshot rows only)
do $f$
declare v_h text; v_h0 timestamptz; v_hr jsonb;
begin
  foreach v_h in array array['cdesc_stages', 'intake', 'aer', 'pdesc'] loop
    v_h0 := clock_timestamp();
    execute format('select security.data_delivery_%s_v1()', v_h) into v_hr;
    insert into pipeline.data_delivery_helper_snapshots(helper, rows, measured_at, took_ms) values (v_h, v_hr, clock_timestamp(), (extract(epoch from clock_timestamp() - v_h0) * 1000)::int)
      on conflict (helper) do update set rows = excluded.rows, measured_at = excluded.measured_at, took_ms = excluded.took_ms, error = null, failed_at = null;
  end loop;
end $f$;

do $c$
declare v jsonb := security.consumer_api_check_v1(); t0 timestamptz; v_ms int; r jsonb;
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'guard: consumer API moved: %', v; end if;
  if (select count(*) from pipeline.manual_locks) < (select n from s1174_locks) then raise exception 'guard: a manual lock was removed'; end if;
  if (select count(*) from cron.job where active) > 140 then raise exception 'guard: active cron above 140'; end if;  -- fixed: protected ceiling
  if (select count(*) from pipeline.data_delivery_helper_snapshots where rows is not null) <> 4 then raise exception 'guard: helper snapshots missing'; end if;
  t0 := clock_timestamp(); r := security.data_delivery_v1(); v_ms := (extract(epoch from clock_timestamp() - t0) * 1000)::int;
  if r->'snapshots' is null then raise exception 'guard: no snapshots key'; end if;
  raise notice 'data delivery read % ms after the change', v_ms;  -- fixed: milliseconds
end $c$;
