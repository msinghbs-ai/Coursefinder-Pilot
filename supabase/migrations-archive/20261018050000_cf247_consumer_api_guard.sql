-- CF-247 Decision 266 (18 Oct 2026): the consumer API is frozen. Platform Admin 18 Oct 2026 11:58: "From here on, make sure the consumer api are not
-- affected by any decision or design"; choice "Frozen-surface guard (Recommended)".
-- The consumer API is what the website and Zoho read: the database functions public.website_v2_*, public.website_edge_*, public.website_api_v2_*,
-- public.zoho_edge_*, public.svc_website_settings_v1 and every function in schema api, and the edge functions website-api-v2, wix-course-api,
-- website-course-api, zoho-api-v2 and zoho-course-api.
-- 1 pipeline.consumer_api_baseline keeps, as found live now: each of those functions' definition checksum, and the columns (name and type) of every
--   table or view their definitions name. Nothing is changed by taking the baseline.
-- 2 security.consumer_api_check_v1() compares live with the baseline: a function missing or changed, a relation missing, a column missing or with
--   another type is drift (a column added is not). Drift raises a hard flag (entity api, reason consumer_api_drift) and an event; a clean check
--   releases earlier flags. Job consumer-api-guard runs it daily.
-- 3 Re-baselining is only done by a migration that carries "-- Consumer API change approved:" (the S57 test enforces it, with the edge function
--   checksums in tests/uat/consumer-api-baseline.json).
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped or deleted.

create table if not exists pipeline.consumer_api_baseline (
  kind text not null check (kind in ('function', 'relation')),
  name text not null,
  md5 text,
  columns jsonb,
  captured_at timestamptz not null default now(),
  reason text not null,
  primary key (kind, name)
);
comment on table pipeline.consumer_api_baseline is 'CF-247 Decision 266: the consumer API as found live (function definition checksums; columns of the relations they read). security.consumer_api_check_v1 compares live with it daily; it is re-taken only by a migration approved for a consumer API change.';
alter table pipeline.consumer_api_baseline enable row level security;

create or replace function security.consumer_api_functions_v1()
returns table(oid oid, name text) language sql stable set search_path = '' as $function$
  select p.oid, p.oid::regprocedure::text
    from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where (n.nspname = 'public' and p.proname ~ '^(website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1$)')
      or n.nspname = 'api'
$function$;

-- relations (tables, views) the consumer functions name, with their columns
create or replace function security.consumer_api_relations_v1()
returns table(name text, columns jsonb) language sql stable set search_path = '' as $function$
  with words as (
    select distinct lower(m[1]) || '.' || lower(m[2]) qn
      from security.consumer_api_functions_v1() f,
           regexp_matches(pg_catalog.pg_get_functiondef(f.oid), '\m(catalogue|ref|ranking|scholarship|search|pipeline|security|api|public)\.([a-z_][a-z0-9_]*)\M', 'g') m),
  rels as (
    select w.qn, c.oid from words w
      join pg_catalog.pg_namespace n on n.nspname = split_part(w.qn, '.', 1)
      join pg_catalog.pg_class c on c.relnamespace = n.oid and c.relname = split_part(w.qn, '.', 2) and c.relkind in ('r', 'v', 'm', 'p', 'f'))
  select r.qn, (select coalesce(jsonb_object_agg(a.attname, pg_catalog.format_type(a.atttypid, a.atttypmod)), '{}'::jsonb)
                  from pg_catalog.pg_attribute a where a.attrelid = r.oid and a.attnum > 0 and not a.attisdropped)
    from rels r
$function$;

create or replace function security.consumer_api_check_v1()
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_drift jsonb := '[]'::jsonb; b record; v_md5 text; v_cols jsonb; k text;
begin
  for b in select * from pipeline.consumer_api_baseline order by kind, name loop
    if b.kind = 'function' then
      select md5(pg_catalog.pg_get_functiondef(f.oid)) into v_md5 from security.consumer_api_functions_v1() f where f.name = b.name;
      if v_md5 is null then v_drift := v_drift || jsonb_build_object('name', b.name, 'what', 'function missing');
      elsif v_md5 <> b.md5 then v_drift := v_drift || jsonb_build_object('name', b.name, 'what', 'function changed'); end if;
    else
      select r.columns into v_cols from security.consumer_api_relations_v1() r where r.name = b.name;
      if v_cols is null then
        -- a relation the functions no longer name may still exist: look it up directly
        select (select coalesce(jsonb_object_agg(a.attname, pg_catalog.format_type(a.atttypid, a.atttypmod)), '{}'::jsonb)
                  from pg_catalog.pg_attribute a where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped)
          into v_cols
          from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace
         where n.nspname = split_part(b.name, '.', 1) and c.relname = split_part(b.name, '.', 2);
      end if;
      if v_cols is null then v_drift := v_drift || jsonb_build_object('name', b.name, 'what', 'relation missing');
      else
        for k in select jsonb_object_keys(b.columns) loop
          if not (v_cols ? k) then v_drift := v_drift || jsonb_build_object('name', b.name, 'what', 'column missing: ' || k);
          elsif v_cols->>k <> b.columns->>k then v_drift := v_drift || jsonb_build_object('name', b.name, 'what', format('column %s type %s, was %s', k, v_cols->>k, b.columns->>k)); end if;
        end loop;
      end if;
    end if;
  end loop;
  -- a consumer function that is new since the baseline is reported too (an addition is allowed, but a person should know)
  v_drift := v_drift || coalesce((select jsonb_agg(jsonb_build_object('name', f.name, 'what', 'function added (not in baseline)'))
                                    from security.consumer_api_functions_v1() f
                                   where not exists (select 1 from pipeline.consumer_api_baseline x where x.kind = 'function' and x.name = f.name)), '[]'::jsonb);
  if jsonb_array_length(v_drift) > 0 then
    insert into pipeline.enrichment_flags(entity, entity_key, field, reason_code, reason, source, kind, state, raised_by_kind)
    values ('api', 'consumer', '', 'consumer_api_drift',
            format('The consumer API differs from its baseline (%s): %s. Nothing the website reads may change without the Platform Admin''s approval (Decision 266).',
                   jsonb_array_length(v_drift), left(v_drift::text, 1500)), 'consumer-api-guard', 'hard', 'raised', 'auto')
    on conflict (entity, entity_key, field, reason_code) do update set reason = excluded.reason, flagged_at = now(), cleared_at = null, state = 'raised';
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('api', 'consumer_api_drift', 'consumer API', jsonb_build_object('drift', v_drift, 'decision', 266), null);
  else
    update pipeline.enrichment_flags set cleared_at = now(), state = 'released', released_at = now(), release_kind = 'auto', release_reason = 'Consumer API matches its baseline'
     where entity = 'api' and entity_key = 'consumer' and reason_code = 'consumer_api_drift' and state = 'raised';
  end if;
  return jsonb_build_object('checked_at', now(), 'functions', (select count(*) from pipeline.consumer_api_baseline where kind = 'function'),
                            'relations', (select count(*) from pipeline.consumer_api_baseline where kind = 'relation'), 'drift', v_drift);
end $function$;

-- only for a migration approved as a consumer API change
create or replace function security.consumer_api_rebaseline_v1(p_reason text)
returns integer language plpgsql security definer set search_path = '' as $function$
declare n int;
begin
  if current_user <> 'postgres' then raise exception 'consumer API baseline is re-taken only by a migration'; end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'give the approval reason'; end if;
  insert into pipeline.consumer_api_baseline(kind, name, md5, columns, captured_at, reason)
  select 'function', f.name, md5(pg_catalog.pg_get_functiondef(f.oid)), null, now(), p_reason from security.consumer_api_functions_v1() f
  on conflict (kind, name) do update set md5 = excluded.md5, captured_at = now(), reason = excluded.reason;
  insert into pipeline.consumer_api_baseline(kind, name, md5, columns, captured_at, reason)
  select 'relation', r.name, null, r.columns, now(), p_reason from security.consumer_api_relations_v1() r
  on conflict (kind, name) do update set columns = excluded.columns, captured_at = now(), reason = excluded.reason;
  select count(*) into n from pipeline.consumer_api_baseline;
  return n;
end $function$;

revoke execute on function security.consumer_api_functions_v1(), security.consumer_api_relations_v1(), security.consumer_api_check_v1(), security.consumer_api_rebaseline_v1(text) from public, anon, authenticated;

select security.consumer_api_rebaseline_v1('Decision 266, 18 Oct 2026: first baseline, taken from live as found');

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('consumer-api-guard', 'Search and API', 12, 'Consumer API guard', 'Daily: compares what the website and Zoho read (API functions, the tables and columns behind them) with the frozen baseline; any change raises a hard flag (Decision 266).', 4, false)
on conflict (jobname) do nothing;
select cron.schedule('consumer-api-guard', '23 18 * * *', $$select security.consumer_api_check_v1()$$);

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('table', 'pipeline.consumer_api_baseline', 'API', 'Frozen consumer API baseline (Decision 266)', 'active', '20261018050000'),
 ('job', 'consumer-api-guard', 'API', 'Daily consumer API drift check', 'active', '20261018050000'),
 ('function', 'security.consumer_api_check_v1', 'API', 'Compares the consumer API with its baseline', 'active', '20261018050000'),
 ('function', 'security.consumer_api_rebaseline_v1', 'API', 'Re-takes the baseline (approved consumer API changes only)', 'active', '20261018050000'),
 ('function', 'security.consumer_api_functions_v1', 'API', 'The consumer API functions', 'active', '20261018050000'),
 ('function', 'security.consumer_api_relations_v1', 'API', 'Relations the consumer API functions read', 'active', '20261018050000')
on conflict (kind, name) do nothing;

do $post$
declare r jsonb;
begin
  if (select count(*) from pipeline.consumer_api_baseline where kind = 'function') < 70 then raise exception 'Decision 266 post-check: functions'; end if;
  if (select count(*) from pipeline.consumer_api_baseline where kind = 'relation') < 10 then raise exception 'Decision 266 post-check: relations'; end if;
  r := security.consumer_api_check_v1();
  if jsonb_array_length(r->'drift') <> 0 then raise exception 'Decision 266 post-check: drift right after baseline %', r->'drift'; end if;
end $post$;
