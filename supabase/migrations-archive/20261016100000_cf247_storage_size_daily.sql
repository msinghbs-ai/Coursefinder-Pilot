-- CF-247 (16 Oct 2026): database and file storage sizes, recorded daily. Platform Admin 16 Oct 2026 23:18: "Prepare and record all db and
-- tables data and sizes also prepare total bucket usage. Keep the stat's simple and recoed on daily basis".
-- One row a day for the database, each schema, each table (rows, table, index and TOAST bytes) and each storage bucket (files, bytes).
-- Recorded daily at about 00:25 Melbourne by job storage-size-daily, and on demand from Settings > Storage & retention (Measure now).
-- Table rows are kept for storage.size_keep_days (365); database, schema and bucket rows are kept always (a few rows a day).
-- Replaces: nothing (the daily capacity observation keeps its policy checks; its top-10 largest tables are now part of this full list)
-- Retires: nothing
-- Nothing dropped or deleted.

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'storage.size_keep_days', 'Daily table sizes: days kept', 'Each table''s daily size row is kept this many days; the daily database, schema and bucket totals are kept always.', 'number', to_jsonb(365), 30, 1825, 'days', 900, 'Platform Admin 16 Oct 2026: record sizes daily', 'Storage', 'security.storage_size_snapshot_v1')
on conflict (toolset_key, key) do nothing;

create table if not exists pipeline.storage_size_daily (
  day date not null,
  kind text not null check (kind in ('database', 'schema', 'table', 'bucket')),
  name text not null,
  bytes bigint not null,
  table_bytes bigint,
  index_bytes bigint,
  toast_bytes bigint,
  rows_estimate bigint,
  files bigint,
  measured_at timestamptz not null default now(),
  primary key (day, kind, name));
comment on table pipeline.storage_size_daily is 'CF-247 16 Oct 2026 (Platform Admin: "record all db and tables data and sizes also prepare total bucket usage ... on daily basis"): one row a day for the database, each schema, each table (estimated rows; table, index and TOAST bytes) and each storage bucket (files, bytes). Written by security.storage_size_snapshot_v1 (job storage-size-daily, or Measure now). Table rows kept storage.size_keep_days; the rest kept always.';
create index if not exists storage_size_daily_kind_day on pipeline.storage_size_daily (kind, day);
alter table pipeline.storage_size_daily enable row level security;
revoke all on pipeline.storage_size_daily from anon, authenticated;

create or replace function security.storage_size_snapshot_v1()
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_day date := (now() at time zone 'Australia/Melbourne')::date; v_tables int; v_removed int;
begin
  -- tables (and materialised views): bytes from the catalogue, rows from the planner's estimate (no table is scanned)
  insert into pipeline.storage_size_daily(day, kind, name, bytes, table_bytes, index_bytes, toast_bytes, rows_estimate)
  select v_day, 'table', n.nspname || '.' || c.relname, pg_total_relation_size(c.oid), pg_relation_size(c.oid), pg_indexes_size(c.oid),
         coalesce(pg_total_relation_size(nullif(c.reltoastrelid, 0)), 0), greatest(c.reltuples, 0)::bigint
    from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace
   where c.relkind in ('r', 'm', 'p') and n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg_toast%'
  on conflict (day, kind, name) do update set bytes = excluded.bytes, table_bytes = excluded.table_bytes, index_bytes = excluded.index_bytes,
     toast_bytes = excluded.toast_bytes, rows_estimate = excluded.rows_estimate, measured_at = now();
  get diagnostics v_tables = row_count;
  insert into pipeline.storage_size_daily(day, kind, name, bytes, table_bytes, index_bytes, toast_bytes, rows_estimate)
  select v_day, 'schema', split_part(t.name, '.', 1), sum(t.bytes), sum(t.table_bytes), sum(t.index_bytes), sum(t.toast_bytes), sum(t.rows_estimate)
    from pipeline.storage_size_daily t where t.day = v_day and t.kind = 'table' group by 3
  on conflict (day, kind, name) do update set bytes = excluded.bytes, table_bytes = excluded.table_bytes, index_bytes = excluded.index_bytes,
     toast_bytes = excluded.toast_bytes, rows_estimate = excluded.rows_estimate, measured_at = now();
  insert into pipeline.storage_size_daily(day, kind, name, bytes)
  values (v_day, 'database', 'database', pg_database_size(current_database()))
  on conflict (day, kind, name) do update set bytes = excluded.bytes, measured_at = now();
  -- buckets: the file sizes Supabase Storage records for each file
  insert into pipeline.storage_size_daily(day, kind, name, bytes, files)
  select v_day, 'bucket', o.bucket_id, coalesce(sum((o.metadata ->> 'size')::bigint), 0), count(*)
    from storage.objects o group by o.bucket_id
  on conflict (day, kind, name) do update set bytes = excluded.bytes, files = excluded.files, measured_at = now();
  delete from pipeline.storage_size_daily
   where kind = 'table' and day < v_day - security.pipeline_num_v1('storage.size_keep_days', 365)::int;
  get diagnostics v_removed = row_count;
  return jsonb_build_object('day', v_day, 'tables', v_tables, 'old_rows_removed', v_removed);
end $function$;

-- Screen: Settings > Storage & retention (Platform Admin page; read for rank 4 and up, Measure now for Platform Admin)
create or replace function public.admin_storage_sizes(p_days integer default 30)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare v_days int := least(greatest(coalesce(p_days, 30), 1), 365); v_last date;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if security.current_role_rank() < 4 then raise exception 'pipeline_operator role required' using errcode = '42501'; end if;
  select max(day) into v_last from pipeline.storage_size_daily;
  return jsonb_build_object(
    'day', v_last,
    'measured_at', (select max(measured_at) from pipeline.storage_size_daily where day = v_last),
    'database_bytes', (select bytes from pipeline.storage_size_daily where day = v_last and kind = 'database'),
    'buckets', (select coalesce(jsonb_agg(jsonb_build_object('name', b.name, 'bytes', b.bytes, 'files', b.files,
                   'bytes_7d_ago', (select p.bytes from pipeline.storage_size_daily p where p.kind = 'bucket' and p.name = b.name and p.day = v_last - 7)) order by b.bytes desc), '[]'::jsonb)
                from pipeline.storage_size_daily b where b.day = v_last and b.kind = 'bucket'),
    'schemas', (select coalesce(jsonb_agg(jsonb_build_object('name', s.name, 'bytes', s.bytes, 'index_bytes', s.index_bytes, 'rows', s.rows_estimate) order by s.bytes desc), '[]'::jsonb)
                from pipeline.storage_size_daily s where s.day = v_last and s.kind = 'schema'),
    'tables', (select coalesce(jsonb_agg(jsonb_build_object('name', t.name, 'bytes', t.bytes, 'table_bytes', t.table_bytes, 'index_bytes', t.index_bytes, 'toast_bytes', t.toast_bytes,
                  'rows', t.rows_estimate,
                  'bytes_1d_ago', (select p.bytes from pipeline.storage_size_daily p where p.kind = 'table' and p.name = t.name and p.day = v_last - 1),
                  'bytes_7d_ago', (select p.bytes from pipeline.storage_size_daily p where p.kind = 'table' and p.name = t.name and p.day = v_last - 7)) order by t.bytes desc), '[]'::jsonb)
               from pipeline.storage_size_daily t where t.day = v_last and t.kind = 'table'),
    'daily', (select coalesce(jsonb_agg(jsonb_build_object('day', d.day, 'database_bytes', d.bytes,
                  'bucket_bytes', (select sum(b.bytes) from pipeline.storage_size_daily b where b.day = d.day and b.kind = 'bucket'),
                  'bucket_files', (select sum(b.files) from pipeline.storage_size_daily b where b.day = d.day and b.kind = 'bucket')) order by d.day desc), '[]'::jsonb)
              from pipeline.storage_size_daily d where d.kind = 'database' and d.day > v_last - v_days),
    'can_measure', security.current_role_rank() >= 6,
    'days', v_days);
end $function$;

create or replace function public.admin_storage_sizes_measure()
returns jsonb language plpgsql security definer set search_path = '' as $function$
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if security.current_role_rank() < 6 then raise exception 'platform_admin role required' using errcode = '42501'; end if;
  return security.storage_size_snapshot_v1();
end $function$;

revoke execute on function security.storage_size_snapshot_v1() from public, anon, authenticated;
revoke execute on function public.admin_storage_sizes(integer), public.admin_storage_sizes_measure() from public, anon;
grant execute on function public.admin_storage_sizes(integer), public.admin_storage_sizes_measure() to authenticated;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('storage-size-daily', 'Platform', 61, 'Storage sizes: daily record', 'Daily (about 00:25 Melbourne): records the size of the database, each schema, each table (rows, table, index and TOAST bytes) and each storage bucket (files, bytes). Shown on Settings > Storage & retention.', 6, false)
on conflict (jobname) do nothing;
select cron.schedule('storage-size-daily', '25 13 * * *', 'select security.storage_size_snapshot_v1()');

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('table', 'pipeline.storage_size_daily', 'Platform', 'Daily database, schema, table and bucket sizes', 'active', '20261016100000'),
 ('job', 'storage-size-daily', 'Platform', 'Daily storage size record', 'active', '20261016100000')
on conflict (kind, name) do nothing;

-- first record today
select security.storage_size_snapshot_v1();

do $post$
begin
  if (select count(*) from pipeline.storage_size_daily where kind = 'bucket') < 1 or (select count(*) from pipeline.storage_size_daily where kind = 'table') < 100 then
    raise exception 'storage sizes post-check: first record missing';
  end if;
end $post$;
