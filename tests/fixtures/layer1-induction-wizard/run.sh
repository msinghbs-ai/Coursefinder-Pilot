#!/usr/bin/env bash
# Guards: Layer 1 induction wizard and Country & category completeness report (Platform Admin 17 Nov 2026 17:59; decisions 18:10) and G4 database-backed
# tests: migration 20261117193000 runs on an isolated PostgreSQL 16 (fixtures only, never a Supabase project). It proves: the migration applies twice;
# eight categories hold the 32 coverage fields; drafting is Pipeline Operator and above and validates what it stores; activation is the Platform
# Admin's with a reason, creates the source paused through admin_layer1_add_source and is logged; a dry run is recorded by the service role only and
# switches nothing on; per-source retention is recorded and no policy changes; the report gives fill by country and category, editions and Layer 4 ageing.
# Needs a scratch PostgreSQL 16: PGHOST/PGPORT/PGUSER point at it. Drops its database at the end (LIW_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${LIW_DB:-g_layer1_induction_wizard}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
M=supabase/migrations-archive/20261117193000_cf247_layer1_induction_wizard.sql
trap '[ -n "${LIW_KEEP:-}" ] || dropdb --if-exists '$DB' >/dev/null 2>&1' EXIT
dropdb --if-exists $DB >/dev/null 2>&1; createdb $DB
psql -X -q -d postgres -c "do \$\$ begin if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if; if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if; if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role; end if; end \$\$"
$P <<'SQL'
create schema pipeline; create schema security; create schema auth; create schema ref;
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('fixture.uid', true), '')::uuid $$;
create function auth.role() returns text language sql stable as $$ select nullif(current_setting('fixture.role', true), '') $$;
create function security.current_role_rank() returns int language sql stable as $$ select nullif(current_setting('fixture.rank', true), '')::int $$;
create table ref.countries (id uuid primary key default gen_random_uuid(), iso_alpha2 text unique, name text);
insert into ref.countries(iso_alpha2, name) values ('AU', 'Australia'), ('NZ', 'New Zealand'), ('IE', 'Ireland');
create table ref.registration_schemes (scheme text, kind text, country_code text, authority text, label text, primary key (scheme, kind, country_code));
insert into ref.registration_schemes values ('ie_qqi', 'course_registration', 'IE', 'QQI', 'QQI course register'), ('cricos', 'course_registration', 'AU', 'DoE', 'CRICOS');
create table pipeline.platform_toolset_settings (toolset_key text, key text, label text, help text, kind text, value jsonb, min_value numeric, max_value numeric, unit text, sort int, reason text, section text, used_by text, primary key (toolset_key, key));
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable as $$ select coalesce((select (value #>> '{}')::numeric from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = p_key), p_default) $$;
create table pipeline.admin_control_events (id bigserial primary key, area text not null, action text not null, target text, detail jsonb not null default '{}', actor uuid, created_at timestamptz not null default now());
create table pipeline.sources (id uuid primary key default gen_random_uuid(), source_type text, country_id uuid, url text, label text, trust_rank int, status text, metadata jsonb);
create table pipeline.layer1_source_operations (source_id uuid primary key, authority_name text, paused boolean, active boolean, ingestion_cadence_days int, expected_format text, last_verified_at timestamptz, verification_status text,
  previous_accepted_count bigint, last_expected_count bigint, variance_percent numeric, variance_decision text);
create table pipeline.layer1_dataset_editions (id uuid primary key default gen_random_uuid(), source_id uuid, edition_key text, status text, last_verified_at timestamptz);
create table pipeline.layer4_review_items (id uuid primary key default gen_random_uuid(), entity_type text, status text, created_at timestamptz not null default now());
create table pipeline.retention_class_policies (class_key text primary key, default_retention_days int, immutable boolean, purge_allowed boolean);
insert into pipeline.retention_class_policies values ('temporary_staging', 14, false, true), ('accepted_source_versions', null, true, false);
create table pipeline.field_coverage_daily (snapshot_date date, country_code text, field text, total bigint, filled bigint, primary key (snapshot_date, country_code, field));
-- the existing add-source function, reduced to what the wizard relies on: Platform Admin only, saved active and paused, logged
create function public.admin_layer1_add_source(p_args jsonb) returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v_id uuid; begin
  if auth.uid() is null or security.current_role_rank() < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if exists (select 1 from pipeline.sources s where lower(s.url) = lower(p_args->>'url')) then raise exception 'a source with this address already exists'; end if;
  insert into pipeline.sources(source_type, country_id, url, label, trust_rank, status, metadata) values ('web', (select id from ref.countries where iso_alpha2 = p_args->>'country_code'), p_args->>'url', p_args->>'label', 10, 'active', jsonb_build_object('needs_reader', true)) returning id into v_id;
  insert into pipeline.layer1_source_operations(source_id, authority_name, paused, active, ingestion_cadence_days, expected_format) values (v_id, p_args->>'authority_name', true, true, (p_args->>'ingestion_cadence_days')::int, p_args->>'expected_format');
  insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('layer1', 'add_source', v_id::text, jsonb_build_object('reason', p_args->>'reason'), auth.uid());
  return jsonb_build_object('ok', true, 'source_id', v_id, 'label', p_args->>'label');
end $f$;
SQL
$P -1 -f $M >/dev/null; $P -1 -f $M >/dev/null
echo "migration: applied twice without error (post-check included)"
$P <<'SQL'
create or replace function pg_temp.ok(c boolean, m text) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', m; end if; raise notice 'ok: %', m; end $$;
create or replace function pg_temp.err(q text) returns text language plpgsql as $$ begin execute q; return null; exception when others then return sqlerrm; end $$;
do $t$ declare r jsonb; v_id uuid; v_src uuid; v_pol text; begin
  perform pg_temp.ok((select count(*) from ref.enrichment_categories) = 8 and (select count(*) from ref.enrichment_category_fields) = 32
    and (select count(distinct category_key) from ref.enrichment_category_fields) = 8, 'eight categories hold the 32 coverage fields, one category each');
  perform pg_temp.ok((select count(*) from ref.enrichment_category_fields where boost_category in ('identity_registers', 'geo_localities', 'tuition_fees', 'admissions_entry', 'intakes_delivery', 'study_rules', 'careers_outcomes', 'scholarships_accred')) = 32
    and (select boost_category from ref.enrichment_category_fields where field = 'v3_study_load') = 'intakes_delivery', 'every field also carries its Boost category (the keys of setting country_category_boost)');
  perform pg_temp.ok(pg_temp.err($$select public.admin_layer1_induction_read()$$) = 'authentication required', 'no session: refused');
  perform set_config('fixture.uid', '44444444-4444-4444-4444-444444444444', true); perform set_config('fixture.rank', '3', true);
  perform pg_temp.ok(pg_temp.err($$select public.admin_layer1_induction_read()$$) like 'Pipeline Operator (rank 4)%' and pg_temp.err($$select public.admin_layer1_induction_save(null, '{"country_code":"IE"}')$$) like 'Pipeline Operator (rank 4)%', 'a Curator cannot open or draft (Layer 1 opens at Pipeline Operator)');
  perform set_config('fixture.rank', '4', true);
  r := public.admin_layer1_induction_read();
  perform pg_temp.ok(jsonb_array_length(r#>'{options,categories}') = 8 and r#>>'{options,retention_defaults,staging_retention_days}' = '14' and r#>'{options,retention_defaults,raw_retention_days}' = 'null'::jsonb
    and (r#>>'{options,dry_run_rows}')::int = 100 and (r#>>'{options,postcode_min_share}')::numeric = 0.9 and jsonb_array_length(r#>'{options,schemes}') = 2, 'options: categories, schemes, retention defaults from today''s policy (14 days, permanent), 100 dry-run rows');
  perform pg_temp.ok(pg_temp.err($$select public.admin_layer1_induction_save(null, '{"country_code":"ZZ"}')$$) like 'choose a country%'
    and pg_temp.err($$select public.admin_layer1_induction_save(null, '{"country_code":"IE","scheme":"cricos","scheme_kind":"course_registration"}')$$) like 'scheme cricos (course_registration) is not registered for IE%'
    and pg_temp.err($$select public.admin_layer1_induction_save(null, '{"country_code":"IE","source_url":"http://x.example"}')$$) like 'the source address must be an https address'
    and pg_temp.err($$select public.admin_layer1_induction_save(null, '{"country_code":"IE","cadence":"daily"}')$$) like 'the cadence is weekly, monthly or annual'
    and pg_temp.err($$select public.admin_layer1_induction_save(null, '{"country_code":"IE","staging_retention_days":0}')$$) like 'staging_retention_days is a whole number of days%'
    and pg_temp.err($$select public.admin_layer1_induction_save(null, '{"country_code":"IE"}', '[{"source_field":"Title","category_key":"nope"}]')$$) = 'unknown category nope'
    and pg_temp.err($$select public.admin_layer1_induction_save(null, '{"country_code":"IE"}', '[{"target_field":"level"}]')$$) = 'every mapping names its source field', 'a draft refuses an unknown country, a scheme of another country, a non-https address, an unknown cadence, bad retention and bad mappings');
  r := public.admin_layer1_induction_save(null, '{"country_code":"ie","scheme":"ie_qqi","scheme_kind":"course_registration"}');
  v_id := (r#>>'{item,id}')::uuid;
  perform pg_temp.ok(r#>>'{item,country_code}' = 'IE' and (r#>>'{item,steps,scheme}')::boolean and not (r#>>'{item,steps,source}')::boolean and r#>>'{item,steps,dry_run_state}' = 'waiting_for_reader', 'step 1 saved; the other steps are open and the dry run waits for a reader');
  r := public.admin_layer1_induction_save(v_id, jsonb_build_object('source_label', 'QQI course register', 'source_url', 'https://qsearch.qqi.ie/courses.csv', 'authority_name', 'Quality and Qualifications Ireland',
    'connector_type', 'csv_file', 'terms_status', 'pending', 'licence_name', 'QQI terms of use', 'attribution_text', 'Source: QQI',
    'sample', jsonb_build_object('columns', '["Title","NFQ Level","Provider"]'::jsonb, 'total_rows', 5000, 'rows', (select jsonb_agg(jsonb_build_array('Course ' || g, '8', 'Provider')) from generate_series(1, 60) g))),
    '[{"source_field":"Title","target_field":"description","category_key":"course_basics","by":"manual"},{"source_field":"NFQ Level","target_field":"level","category_key":"course_basics","by":"ai_adjusted"}]');
  perform pg_temp.ok((r#>>'{item,steps,source}')::boolean and (r#>>'{item,steps,mapping}')::boolean and jsonb_array_length(r#>'{item,payload,sample,rows}') = 20 and r#>>'{item,payload,scheme}' = 'ie_qqi'
    and r#>>'{item,payload,terms_status}' = 'pending', 'steps 2 and 3 saved: licence and terms (REQ-68) kept, the sample cut to 20 rows, earlier values kept');
  perform set_config('fixture.rank', '6', true);
  perform pg_temp.ok(pg_temp.err(format($$select public.admin_layer1_induction_activate(%L, 'go live')$$, v_id)) like 'step 4 is not finished%', 'activation refuses an unfinished step');
  perform set_config('fixture.rank', '4', true);
  r := public.admin_layer1_induction_save(v_id, '{"cadence":"monthly","edition_archiving":true,"staging_retention_days":90,"raw_retention_days":2555}');
  select string_agg(class_key || ':' || coalesce(default_retention_days::text, 'permanent'), ',' order by class_key) into v_pol from pipeline.retention_class_policies;
  perform pg_temp.ok((r#>>'{item,steps,cadence}')::boolean and r#>>'{item,payload,staging_retention_days}' = '90' and r#>>'{item,payload,raw_retention_days}' = '2555'
    and v_pol = 'accepted_source_versions:permanent,temporary_staging:14', 'step 4 saved: per-source retention is recorded and the platform policy is unchanged');
  perform pg_temp.ok(pg_temp.err(format($$select public.admin_layer1_induction_activate(%L, 'go live')$$, v_id)) like 'Platform Admin (rank 6) activates%', 'a Pipeline Operator cannot activate');
  perform pg_temp.ok(pg_temp.err(format($$select public.svc_layer1_induction_dry_run_record(%L, '{"status":"passed"}')$$, v_id)) = 'service role required', 'a signed-in user cannot record a dry run');
  perform set_config('fixture.role', 'service_role', true);
  perform pg_temp.ok(pg_temp.err(format($$select public.svc_layer1_induction_dry_run_record(%L, '{"status":"passed","rows_read":100}')$$, v_id)) = 'inserts is a count', 'a dry run needs every count');
  r := public.svc_layer1_induction_dry_run_record(v_id, '{"status":"failed","rows_read":100,"inserts":0,"updates":0,"departures":0,"postcode_escalations":0,"reader":"layer1-ie-qqi","message":"header row not found"}');
  perform pg_temp.ok(public.svc_layer1_induction_read(v_id)#>>'{dry_run,status}' = 'failed', 'the loaders read the induction and record a dry run');
  perform set_config('fixture.role', '', true); perform set_config('fixture.rank', '6', true);
  perform pg_temp.ok(pg_temp.err(format($$select public.admin_layer1_induction_activate(%L, 'go live')$$, v_id)) like 'the dry run failed%'
    and pg_temp.err(format($$select public.admin_layer1_induction_activate(%L, ' ')$$, v_id)) = 'a reason is required', 'activation refuses a failed dry run and needs a reason');
  perform set_config('fixture.role', 'service_role', true);
  perform public.svc_layer1_induction_dry_run_record(v_id, '{"status":"passed","rows_read":100,"inserts":92,"updates":6,"departures":2,"postcode_escalations":3,"reader":"layer1-ie-qqi"}');
  perform pg_temp.ok((select status from pipeline.layer1_source_inductions where id = v_id) = 'draft' and (select count(*) from pipeline.sources) = 0, 'a passing dry run switches nothing on: still a draft, no source');
  perform set_config('fixture.role', '', true);
  r := public.admin_layer1_induction_activate(v_id, 'QQI register approved for Ireland');
  v_src := (r->>'source_id')::uuid;
  perform pg_temp.ok((r->>'source_paused')::boolean and r#>>'{item,status}' = 'activated' and r->>'dry_run' = 'passed'
    and (select paused and ingestion_cadence_days = 30 from pipeline.layer1_source_operations where source_id = v_src)
    and (select count(*) from pipeline.admin_control_events where area = 'layer1' and action = 'induction_activate' and target = v_src::text and detail->>'reason' = 'QQI register approved for Ireland' and detail->>'terms_status' = 'pending' and (detail->>'source_paused')::boolean) = 1
    and (select count(*) from pipeline.admin_control_events where action = 'add_source') = 1, 'activation creates the source paused through admin_layer1_add_source, monthly, and is logged with its reason');
  perform pg_temp.ok(pg_temp.err(format($$select public.admin_layer1_induction_save(%L, '{"cadence":"weekly"}')$$, v_id)) like 'this induction is activated%'
    and pg_temp.err(format($$select public.admin_layer1_induction_activate(%L, 'again')$$, v_id)) like 'this induction is already activated', 'an activated induction is closed');
  -- a second draft activated with no reader: allowed, and says so
  r := public.admin_layer1_induction_save(null, '{"country_code":"AU","scheme":"cricos","scheme_kind":"course_registration","source_label":"Second register","source_url":"https://example.org/data.json","authority_name":"Authority","connector_type":"json_api","terms_status":"not_required","cadence":"annual"}', '[{"source_field":"name"}]');
  r := public.admin_layer1_induction_activate((r#>>'{item,id}')::uuid, 'no reader yet');
  perform pg_temp.ok(r->>'dry_run' = 'waiting_for_reader' and (r->>'source_paused')::boolean and (select ingestion_cadence_days from pipeline.layer1_source_operations where source_id = (r->>'source_id')::uuid) = 365, 'with no reader the source is still saved paused, marked waiting for a reader');
  r := public.admin_layer1_induction_save(null, '{"country_code":"NZ"}');
  perform set_config('fixture.rank', '4', true);
  perform pg_temp.ok(pg_temp.err(format($$select public.admin_layer1_induction_cancel(%L, '')$$, r#>>'{item,id}')) = 'a reason is required'
    and (public.admin_layer1_induction_cancel((r#>>'{item,id}')::uuid, 'not needed')#>>'{item,status}') = 'cancelled' and (select count(*) from pipeline.layer1_source_inductions) = 3, 'a draft is cancelled with a reason and kept');
  -- categories
  perform pg_temp.ok(pg_temp.err($$select public.admin_enrichment_category_field_set('deadline', 'fees', 'x')$$) like 'Platform Admin (rank 6)%', 'only the Platform Admin moves a field');
  perform set_config('fixture.rank', '6', true);
  perform pg_temp.ok(pg_temp.err($$select public.admin_enrichment_category_field_set('deadline', 'fees', '')$$) = 'a reason is required' and pg_temp.err($$select public.admin_enrichment_category_field_set('deadline', 'nope', 'x')$$) = 'unknown category'
    , 'a field move needs a reason and a known category');
  r := public.admin_enrichment_category_field_set('deadline', 'fees', 'fee deadline');
  perform pg_temp.ok(r->>'from' = 'intakes_deadlines' and (select category_key from ref.enrichment_category_fields where field = 'deadline') = 'fees'
    and (select count(*) from pipeline.admin_control_events where action = 'enrichment_category_field_set' and detail->>'to' = 'fees') = 1, 'a field moves category with a reason, logged');
  -- report
  insert into pipeline.field_coverage_daily values (current_date - 1, 'AU', 'level', 10, 1), (current_date, 'AU', 'level', 100, 90), (current_date, 'AU', 'duration', 100, 50), (current_date, 'AU', 'provider_tuition', 100, 25),
    (current_date, 'NZ', 'level', 40, 40), (current_date, 'NZ', 'brand_new_field', 40, 10);
  insert into pipeline.layer1_dataset_editions(source_id, edition_key, status, last_verified_at) values (v_src, '2025', 'superseded', now() - interval '400 days'), (v_src, '2026', 'current', now());
  insert into pipeline.layer4_review_items(entity_type, status, created_at) values ('course', 'pending', now()), ('course', 'pending', now() - interval '10 days'), ('course', 'pending', now() - interval '45 days'), ('provider', 'pending', now() - interval '2 days'), ('course', 'approved', now() - interval '90 days');
  perform set_config('fixture.rank', '2', true);
  perform pg_temp.ok(pg_temp.err($$select public.admin_completeness_report()$$) like 'Curator (rank 3)%', 'the report opens at Curator');
  perform set_config('fixture.rank', '3', true);
  r := public.admin_completeness_report();
  perform pg_temp.ok(r->>'snapshot_date' = current_date::text and r->'countries' = '["AU","NZ"]'::jsonb and jsonb_array_length(r->'categories') = 8
    and (select (c->>'pct')::numeric = 70.0 and jsonb_array_length(c->'fields') = 2 from jsonb_array_elements(r->'cells') c where c->>'country_code' = 'AU' and c->>'category_key' = 'course_basics')
    and (select (c->>'pct')::numeric = 25.0 from jsonb_array_elements(r->'cells') c where c->>'country_code' = 'AU' and c->>'category_key' = 'fees')
    and (select (c->>'pct')::numeric = 25.0 from jsonb_array_elements(r->'cells') c where c->>'country_code' = 'NZ' and c->>'category_key' = 'unmapped'), 'fill by country and category from the latest snapshot only; a field with no category shows as unmapped');
  perform pg_temp.ok((select (e->>'editions_kept')::int = 2 and e->>'current_edition' = '2026' and (e->>'paused')::boolean and (e#>>'{retention,per_source}')::boolean and e#>>'{retention,staging_retention_days}' = '90' and e#>>'{retention,raw_retention_days}' = '2555'
      from jsonb_array_elements(r->'editions') e where e->>'source_id' = v_src::text) and jsonb_array_length(r->'editions') = 2 and jsonb_array_length(r->'retention_policy') = 2, 'editions kept, the current edition and per-source retention for each Layer 1 source');
  perform pg_temp.ok((r#>>'{layer4,pending}')::int = 4 and (r#>>'{layer4,warn_days}')::int = 7 and (r#>>'{layer4,old_days}')::int = 30
    and (select (x->>'fresh')::int = 1 and (x->>'waiting')::int = 1 and (x->>'old')::int = 1 from jsonb_array_elements(r#>'{layer4,by_type}') x where x->>'entity_type' = 'course'), 'Layer 4 ageing: pending items by type, in fresh, waiting and old from the settings');
  perform pg_temp.ok(not has_function_privilege('anon', 'public.admin_layer1_induction_activate(uuid, text)', 'execute') and not has_function_privilege('anon', 'public.admin_completeness_report()', 'execute')
    and not has_function_privilege('authenticated', 'public.svc_layer1_induction_dry_run_record(uuid, jsonb)', 'execute') and not has_table_privilege('authenticated', 'pipeline.layer1_source_inductions', 'select')
    and not has_table_privilege('authenticated', 'ref.enrichment_category_fields', 'select') and has_table_privilege('service_role', 'ref.enrichment_category_fields', 'select'), 'anon reaches nothing; tables are closed to the browser; the loaders read the categories');
end $t$;
SQL
# Wave 2 addenda (Platform Admin 17 Nov 2026 19:09): parser line items and the target record type, on top of the wizard
N=supabase/migrations-archive/20261117203000_cf247_layer1_parser_line_items.sql
$P -1 -f $N >/dev/null; $P -1 -f $N >/dev/null
echo "parser migration: applied twice without error (definition guard and post-check included)"
$P <<'SQL'
create or replace function pg_temp.ok(c boolean, m text) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', m; end if; raise notice 'ok: %', m; end $$;
create or replace function pg_temp.err(q text) returns text language plpgsql as $$ begin execute q; return null; exception when others then return sqlerrm; end $$;
do $t$ declare r jsonb; v_id uuid; v_ai uuid; v_hard uuid; v_none uuid; begin
  perform set_config('fixture.uid', '44444444-4444-4444-4444-444444444444', true); perform set_config('fixture.rank', '4', true);
  r := public.admin_layer1_induction_read();
  perform pg_temp.ok(jsonb_array_length(r#>'{options,record_types}') = 7 and r#>'{options,record_types}' @> '[{"key":"course_register"},{"key":"career_outcomes"},{"key":"destination_metrics"}]'::jsonb, 'the wizard offers seven target record types');
  perform pg_temp.ok(pg_temp.err($$select public.admin_layer1_induction_save(null, '{"country_code":"IE","target_record_type":"anything"}')$$) = 'unknown target record type', 'an unknown record type is refused');
  r := public.admin_layer1_induction_save(null, '{"country_code":"IE","scheme":"ie_qqi","scheme_kind":"course_registration"}');
  v_id := (r#>>'{item,id}')::uuid;
  perform pg_temp.ok(not (r#>>'{item,steps,scheme}')::boolean and not (r#>>'{item,steps,parser_spec}')::boolean, 'step 1 is not finished without a target record type');
  perform pg_temp.ok(pg_temp.err(format($$select public.admin_layer1_induction_save(%L, '{"target_record_type":"tuition_fees","parser_spec":{"record_type":"course_register","fields":[]}}')$$, v_id)) like 'the parser spec is for another record type%', 'a parser spec for another record type is refused');
  r := public.admin_layer1_induction_save(v_id, '{"target_record_type":"tuition_fees","source_label":"QQI fees table","source_url":"https://qsearch.qqi.ie/fees.csv","authority_name":"QQI","connector_type":"csv_file","terms_status":"not_required","cadence":"annual",
    "parser_spec":{"record_type":"tuition_fees","target_table":"catalogue.course_fees","format":"csv","fields":[{"source":"Fee","target":"provider_tuition"}]}}', '[{"source_field":"Fee","target_field":"provider_tuition","category_key":"fees","by":"ai"}]');
  perform pg_temp.ok((r#>>'{item,steps,scheme}')::boolean and (r#>>'{item,steps,parser_spec}')::boolean and r#>>'{item,payload,parser_spec,target_table}' = 'catalogue.course_fees' and r#>>'{item,payload,parser_spec_by}' = 'ai', 'the record type and the mapper''s parser spec are saved with the draft');
  perform set_config('fixture.rank', '6', true);
  r := public.admin_layer1_induction_activate(v_id, 'QQI fees approved');
  v_ai := (r->>'source_id')::uuid;
  perform pg_temp.ok((select parser_kind = 'ai_built' and target_record_type = 'tuition_fees' and spec_version = 1 and induction_id = v_id and parser_spec->>'format' = 'csv' from pipeline.layer1_source_parsers where source_id = v_ai)
    and (select detail->>'parser' = 'ai_built' and detail->>'target_record_type' = 'tuition_fees' from pipeline.admin_control_events where action = 'induction_activate' and target = v_ai::text)
    and (select paused from pipeline.layer1_source_operations where source_id = v_ai), 'activation records the AI-built parser for the source, which stays paused');
  -- a register read by code, and one still waiting for a parser
  insert into pipeline.sources(source_type, url, label, status, metadata) values ('web', 'https://cricos.example/data', 'CRICOS courses', 'active', '{}') returning id into v_hard;
  insert into pipeline.layer1_source_operations(source_id, authority_name, paused, active) values (v_hard, 'DoE', false, true);
  select s.id into v_none from pipeline.sources s where s.label = 'Second register';
  perform set_config('fixture.rank', '3', true);
  perform pg_temp.ok(pg_temp.err($$select public.admin_layer1_parser_status()$$) like 'Pipeline Operator (rank 4)%', 'the parser status opens with Layer 1');
  perform set_config('fixture.rank', '4', true);
  r := public.admin_layer1_parser_status()->'sources';
  perform pg_temp.ok(r#>>array[v_ai::text, 'parser'] = 'ai_built' and r#>>array[v_hard::text, 'parser'] = 'hardcoded' and r#>>array[v_none::text, 'parser'] = 'none' and r#>>array[v_ai::text, 'target_record_type'] = 'tuition_fees'
    and (select count(*) from pipeline.layer1_source_parsers) = 1, 'badges: AI-built from its spec, hardcoded when read by code, none while it waits for a parser');
  perform pg_temp.ok(pg_temp.err(format($$select public.admin_layer1_parser_reinfer_request(%L, 'layout moved')$$, v_ai)) = 'no layout drift is flagged for this source'
    and pg_temp.err(format($$select public.svc_layer1_parser_drift_record(%L, true, 'x')$$, v_ai)) = 'service role required', 're-infer needs flagged drift; only a reader flags drift');
  perform set_config('fixture.role', 'service_role', true);
  perform public.svc_layer1_parser_drift_record(v_ai, true, 'column Fee is now Annual fee');
  perform public.svc_layer1_parser_drift_record(v_hard, true, 'header row moved');
  perform pg_temp.ok(pg_temp.err($$select public.svc_layer1_parser_drift_record('99999999-9999-9999-9999-999999999999', true, 'x')$$) = 'not a Layer 1 source'
    and (select parser_kind = 'hardcoded' and drift_flagged_at is not null from pipeline.layer1_source_parsers where source_id = v_hard), 'a reader flags drift; a source read by code gets its row as hardcoded');
  perform set_config('fixture.role', '', true);
  perform pg_temp.ok(pg_temp.err(format($$select public.admin_layer1_parser_reinfer_request(%L, ' ')$$, v_ai)) = 'a reason is required', 're-infer needs a reason');
  r := public.admin_layer1_parser_reinfer_request(v_ai, 'fee column renamed');
  perform pg_temp.ok((r->>'ok')::boolean and (select count(*) from pipeline.admin_control_events where area = 'layer1' and action = 'parser_reinfer_request' and target = v_ai::text and detail->>'reason' = 'fee column renamed') = 1
    and pg_temp.err(format($$select public.admin_layer1_parser_reinfer_request(%L, 'again')$$, v_ai)) = 'a re-infer is already requested for this source'
    and public.admin_layer1_parser_status()#>>array['sources', v_ai::text, 'reinfer_reason'] = 'fee column renamed'
    and (select paused from pipeline.layer1_source_operations where source_id = v_ai), 'the request is recorded once and logged; nothing is run and the source stays paused');
  perform set_config('fixture.role', 'service_role', true);
  perform pg_temp.ok(pg_temp.err(format($$select public.svc_layer1_parser_record(%L, '{"parser_kind":"ai_built"}')$$, v_ai)) = 'an AI-built parser needs its spec', 'an AI-built parser needs its spec');
  r := public.svc_layer1_parser_record(v_ai, '{"parser_kind":"ai_built","target_record_type":"tuition_fees","parser_spec":{"record_type":"tuition_fees","format":"csv","fields":[{"source":"Annual fee","target":"provider_tuition"}]}}');
  perform pg_temp.ok((r->>'spec_version')::int = 2 and (select drift_flagged_at is null and reinfer_requested_at is null and parser_spec#>>'{fields,0,source}' = 'Annual fee' from pipeline.layer1_source_parsers where source_id = v_ai)
    and public.svc_layer1_parser_drift_record(v_hard, false)->>'drift_flagged' = 'false', 'a new spec is version 2 and clears the drift and the request; a reader can clear drift');
  perform pg_temp.ok(not has_function_privilege('anon', 'public.admin_layer1_parser_reinfer_request(uuid, text)', 'execute') and not has_function_privilege('authenticated', 'public.svc_layer1_parser_record(uuid, jsonb)', 'execute')
    and not has_table_privilege('authenticated', 'pipeline.layer1_source_parsers', 'select'), 'anon reaches nothing; the parser table and service functions are closed to the browser');
end $t$;
SQL
# Wave 2 decisions (Platform Admin 17 Nov 2026 19:58 and 20:45): one category list, retention in S1-Build's table, Curators in Layer 1
$P <<'SQL'
-- S1-Build's per-source retention (migration 20261117200000), reduced to what the wizard relies on
create table pipeline.source_retention_policies (source_id uuid primary key references pipeline.sources(id), staging_keep_days int not null check (staging_keep_days between 30 and 3650), reason text not null, updated_by uuid, updated_at timestamptz not null default now());
create function public.admin_source_retention_set(p_source_id uuid, p_keep_days int, p_reason text) returns jsonb language plpgsql security definer set search_path to '' as $f$
begin
  if coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin (rank 6) is needed to change a retention period' using errcode = '42501'; end if;
  insert into pipeline.source_retention_policies(source_id, staging_keep_days, reason, updated_by) values (p_source_id, p_keep_days, p_reason, auth.uid())
  on conflict (source_id) do update set staging_keep_days = excluded.staging_keep_days, reason = excluded.reason;
  insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('retention', 'source_retention_set', p_source_id::text, jsonb_build_object('staging_keep_days', p_keep_days, 'reason', p_reason), auth.uid());
  return jsonb_build_object('source_id', p_source_id, 'staging_keep_days', p_keep_days);
end $f$;
insert into pipeline.platform_toolset_settings(toolset_key, key, value) values ('pipeline', 'retention.staging_keep_days', to_jsonb(90)), ('pipeline', 'retention.raw_hash_keep_years', to_jsonb(7)), ('pipeline', 'retention.staging_prune_on', to_jsonb(0));
-- the Layer 1 list read of another lane is not in this fixture: the migration leaves an absent function alone
SQL
U=supabase/migrations-archive/20261117213000_cf247_wave2_unify_categories_retention_roles.sql
$P -1 -f $U >/dev/null; $P -1 -f $U >/dev/null
echo "decisions migration: applied twice without error (definition guards, exact-text swaps and post-check included)"
$P <<'SQL'
create or replace function pg_temp.ok(c boolean, m text) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', m; end if; raise notice 'ok: %', m; end $$;
create or replace function pg_temp.err(q text) returns text language plpgsql as $$ begin execute q; return null; exception when others then return sqlerrm; end $$;
do $t$ declare r jsonb; v_id uuid; v_src uuid; v_cur uuid; begin
  perform set_config('fixture.uid', '55555555-5555-5555-5555-555555555555', true); perform set_config('fixture.rank', '2', true);
  perform pg_temp.ok(pg_temp.err($$select public.admin_layer1_induction_read()$$) like 'Curator (rank 3)%' and pg_temp.err($$select public.admin_layer1_parser_status()$$) like 'Curator (rank 3)%', 'a Counsellor still cannot open Layer 1');
  perform set_config('fixture.rank', '3', true);
  r := public.admin_layer1_induction_read();
  perform pg_temp.ok((r->>'rank')::int = 3 and (r#>>'{options,retention_defaults,staging_keep_days}')::int = 90 and (r#>>'{options,retention_defaults,raw_hash_keep_years}')::int = 7
    and r#>>'{options,retention_defaults,staging_prune_on}' = 'false' and not r#>'{options,retention_defaults}' ? 'raw_retention_days' and public.admin_layer1_parser_status() ? 'sources',
    'a Curator opens the wizard and the parser badges; retention defaults come from the retention settings');
  perform pg_temp.ok(pg_temp.err($$select public.admin_layer1_induction_save(null, '{"country_code":"IE","staging_keep_days":14}')$$) like 'staging is kept for a whole number of days from 30 to 3,650%', 'the keep period follows the range of the retention table');
  r := public.admin_layer1_induction_save(null, '{"country_code":"IE","scheme":"ie_qqi","scheme_kind":"course_registration","target_record_type":"provider_register","source_label":"QQI providers","source_url":"https://qsearch.qqi.ie/providers.csv","authority_name":"QQI","connector_type":"csv_file","terms_status":"not_required","cadence":"monthly","staging_keep_days":180,"raw_retention_days":2555}', '[{"source_field":"Name","target_field":"p_type","category_key":"provider_profile"}]');
  v_id := (r#>>'{item,id}')::uuid;
  perform pg_temp.ok(r#>>'{item,payload,staging_keep_days}' = '180' and not r#>'{item,payload}' ? 'raw_retention_days' and not r#>'{item,payload}' ? 'staging_retention_days' and (r#>>'{item,steps,cadence}')::boolean,
    'a Curator creates and edits a draft; it carries one staging keep period and no retention values of its own');
  r := public.admin_layer1_induction_save(null, '{"country_code":"NZ"}'); v_cur := (r#>>'{item,id}')::uuid;
  perform pg_temp.ok(public.admin_layer1_induction_cancel(v_cur, 'not needed')#>>'{item,status}' = 'cancelled', 'a Curator cancels a draft with a reason');
  perform pg_temp.ok(pg_temp.err(format($$select public.admin_layer1_induction_activate(%L, 'go')$$, v_id)) like 'Platform Admin (rank 6) activates%', 'a Curator cannot activate');
  perform set_config('fixture.rank', '5', true);
  perform pg_temp.ok(pg_temp.err(format($$select public.admin_layer1_induction_activate(%L, 'go live')$$, v_id)) like 'Platform Admin (rank 6) activates%', 'a PIM Operator cannot activate');
  perform set_config('fixture.rank', '6', true);
  r := public.admin_layer1_induction_activate(v_id, 'QQI providers approved'); v_src := (r->>'source_id')::uuid;
  perform pg_temp.ok((select staging_keep_days = 180 and reason = 'Induction wizard: QQI providers approved' from pipeline.source_retention_policies where source_id = v_src)
    and (select count(*) from pipeline.admin_control_events where area = 'retention' and action = 'source_retention_set' and target = v_src::text) = 1
    and (select (detail->>'staging_keep_days')::int = 180 from pipeline.admin_control_events where action = 'induction_activate' and target = v_src::text)
    and (select paused from pipeline.layer1_source_operations where source_id = v_src), 'activation sets the keep period through admin_source_retention_set (the table housekeeping reads); the source stays paused');
  -- re-infer: Pipeline Operator and above, never a Curator
  perform set_config('fixture.role', 'service_role', true);
  perform public.svc_layer1_parser_drift_record(v_src, true, 'column renamed');
  perform pg_temp.ok(jsonb_array_length(public.svc_enrichment_categories()->'categories') = 8 and (public.svc_enrichment_categories()->>'version')::int = 1
    and (select sum(jsonb_array_length(c->'fields')) from jsonb_array_elements(public.svc_enrichment_categories()->'categories') c) = 32
    and public.svc_enrichment_categories()#>>'{categories,0,key}' = 'course_basics' and public.svc_enrichment_categories()::text not like '%identity_registers%',
    'the loaders read one list: eight keys, 32 fields, in order, and no Boost key among them');
  perform set_config('fixture.role', '', true); perform set_config('fixture.rank', '3', true);
  perform pg_temp.ok(pg_temp.err($$select public.svc_enrichment_categories()$$) = 'service role required'
    and pg_temp.err(format($$select public.admin_layer1_parser_reinfer_request(%L, 'layout moved')$$, v_src)) like 'Pipeline Operator (rank 4)%', 'a Curator cannot request a re-infer');
  perform set_config('fixture.rank', '4', true);
  perform pg_temp.ok((public.admin_layer1_parser_reinfer_request(v_src, 'layout moved')->>'ok')::boolean, 'a Pipeline Operator requests a re-infer with a reason');
  -- the report reads the retention table and settings
  perform set_config('fixture.rank', '3', true);
  r := public.admin_completeness_report();
  perform pg_temp.ok((select (e#>>'{retention,per_source}')::boolean and (e#>>'{retention,staging_keep_days}')::int = 180 and (e#>>'{retention,raw_hash_keep_years}')::int = 7 from jsonb_array_elements(r->'editions') e where e->>'source_id' = v_src::text)
    and (select count(*) from jsonb_array_elements(r->'editions') e where not (e#>>'{retention,per_source}')::boolean and (e#>>'{retention,staging_keep_days}')::int = 90) >= 1
    and (r#>>'{retention_settings,staging_keep_days}')::int = 90 and r#>>'{retention_settings,staging_prune_on}' = 'false', 'the report shows each source''s keep period from the retention table, or the platform period');
  perform pg_temp.ok(col_description('ref.enrichment_category_fields'::regclass, (select attnum from pg_attribute where attrelid = 'ref.enrichment_category_fields'::regclass and attname = 'boost_category')) like 'Crosswalk only%', 'the Boost key on a field is marked as a crosswalk, not a list');
end $t$;
SQL
# Wave 2 register drafts (Platform Admin 17 Nov 2026 23:02): nine drafts are pre-staged; a draft is not a source and writes no retention policy
W=supabase/migrations-archive/20261118004000_cf247_wave2_register_drafts.sql
if $P -1 -f $W >/dev/null 2>/tmp/liw_w.err; then echo "FAIL: the drafts migration applied without GB, US and CA or their schemes" >&2; exit 1; fi
grep -q "prerequisite missing" /tmp/liw_w.err
$P <<'SQL'
insert into ref.countries(iso_alpha2, name) values ('GB', 'United Kingdom'), ('US', 'United States'), ('CA', 'Canada') on conflict do nothing;
insert into ref.registration_schemes values ('uk_ofs', 'provider_registration', 'GB', 'Office for Students', 'OfS register (UKPRN)'), ('ie_qqi', 'provider_registration', 'IE', 'QQI', 'QQI provider'),
  ('us_ipeds', 'provider_registration', 'US', 'NCES', 'IPEDS unit ID'), ('us_opeid', 'provider_registration', 'US', 'US Department of Education', 'OPE ID'), ('pgwp', 'work_eligibility', 'CA', 'IRCC', 'PGWP'),
  ('hecos', 'field_of_study', 'GB', 'HESA', 'HECoS'), ('cip', 'field_of_study', 'US', 'NCES', 'CIP'), ('cip', 'field_of_study', 'CA', 'Statistics Canada', 'CIP Canada') on conflict do nothing;
create table public.fixture_before_w as select (select count(*) from pipeline.sources) sources, (select count(*) from pipeline.source_retention_policies) policies,
  (select count(*) from pipeline.layer1_source_inductions) inductions, (select count(*) from pipeline.admin_control_events) events;
SQL
$P -1 -f $W >/dev/null; $P -1 -f $W >/dev/null
echo "drafts migration: refused without its prerequisites, then applied twice without error (post-check included)"
$P <<'SQL'
create or replace function pg_temp.ok(c boolean, m text) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', m; end if; raise notice 'ok: %', m; end $$;
create or replace function pg_temp.err(q text) returns text language plpgsql as $$ begin execute q; return null; exception when others then return sqlerrm; end $$;
do $t$ declare r jsonb; v_id uuid; b record; begin
  select * into b from public.fixture_before_w;
  perform pg_temp.ok((select count(*) from pipeline.layer1_source_inductions) = b.inductions + 9
    and (select count(*) from pipeline.layer1_source_inductions i where i.payload->>'notes' like 'Wave 2 draft, pre-staged%' and i.status = 'draft' and i.source_id is null and i.created_by is null) = 9,
    'nine Wave 2 drafts, once only after two applies, all in draft with no source');
  perform pg_temp.ok((select jsonb_object_agg(country_code, n) from (select country_code, count(*) n from pipeline.layer1_source_inductions where payload->>'notes' like 'Wave 2 draft%' group by 1) x)
    = '{"GB": 3, "IE": 3, "US": 2, "CA": 1}'::jsonb, 'three for the United Kingdom, three for Ireland, two for the United States, one for Canada');
  perform pg_temp.ok((select count(*) from pipeline.sources) = b.sources and (select count(*) from pipeline.source_retention_policies) = b.policies and (select count(*) from pipeline.admin_control_events) = b.events,
    'no source is added, no retention policy is written and nothing is logged as a control change');
  perform pg_temp.ok(not exists (select 1 from pipeline.layer1_source_inductions i where i.payload->>'notes' like 'Wave 2 draft%' and i.payload->>'source_label' ilike '%Designated Learning%'),
    'the IRCC Designated Learning Institutions list is not drafted (it is already a live source)');
  perform pg_temp.ok((select bool_and((i.payload->>'staging_keep_days')::int = 90 and (i.payload->>'edition_archiving')::boolean and i.payload->>'terms_status' = 'pending' and i.payload->>'source_url' ~ '^https://'
      and i.payload->>'target_record_type' in ('provider_register', 'course_register', 'study_rules')) from pipeline.layer1_source_inductions i where i.payload->>'notes' like 'Wave 2 draft%'),
    'each draft keeps staging 90 days, has an https address, a target record type and licence terms pending');
  perform pg_temp.ok((select count(*) from pipeline.layer1_source_inductions i where i.payload->>'notes' like 'Wave 2 draft%' and (security.layer1_induction_steps_v1(i)->>'scheme')::boolean) = 5
    and (select count(*) from pipeline.layer1_source_inductions i where i.payload->>'notes' like 'Wave 2 draft%' and (security.layer1_induction_steps_v1(i)->>'mapping')::boolean) = 5
    and (select bool_and((security.layer1_induction_steps_v1(i)->>'cadence')::boolean and security.layer1_induction_steps_v1(i)->>'dry_run_state' = 'waiting_for_reader') from pipeline.layer1_source_inductions i where i.payload->>'notes' like 'Wave 2 draft%'),
    'five drafts have a registered scheme and five have mappings; all have a cadence and wait for a reader');
  -- a Curator opens a seeded draft and saves it through the wizard's own function; activation stays the Platform Admin's and is refused while a step is unfinished
  perform set_config('fixture.uid', '44444444-4444-4444-4444-444444444444', true); perform set_config('fixture.rank', '3', true);
  select i.id into v_id from pipeline.layer1_source_inductions i where i.payload->>'source_label' = 'IPEDS institution directory (HD)';
  r := public.admin_layer1_induction_read(v_id);
  perform pg_temp.ok(r#>>'{item,payload,target_record_type}' = 'provider_register' and jsonb_array_length(r#>'{item,mappings}') = 10 and (select count(*) from jsonb_array_elements(r->'drafts') d where d->>'status' = 'draft') >= 9,
    'a Curator sees the seeded drafts and opens one');
  r := public.admin_layer1_induction_save(v_id, '{"notes":"checked by the fixture"}'::jsonb, null);
  perform pg_temp.ok(r#>>'{item,payload,scheme}' = 'us_ipeds' and (r#>>'{item,payload,staging_keep_days}')::int = 90 and jsonb_array_length(r#>'{item,mappings}') = 10, 'the wizard''s save accepts a seeded draft and keeps its scheme, keep period and mappings');
  perform pg_temp.ok(pg_temp.err(format($$select public.admin_layer1_induction_activate(%L, 'fixture activation')$$, v_id)) like 'Platform Admin (rank 6)%', 'a Curator cannot activate a seeded draft');
  perform set_config('fixture.rank', '6', true);
  select i.id into v_id from pipeline.layer1_source_inductions i where i.payload->>'source_label' = 'Interim List of Eligible Programmes (ILEP)';
  perform pg_temp.ok(pg_temp.err(format($$select public.admin_layer1_induction_activate(%L, 'fixture activation')$$, v_id)) like 'step 1 is not finished%', 'a draft with no registered scheme cannot be activated');
end $t$;
SQL
echo "layer1 induction wizard: all checks passed"
