#!/usr/bin/env bash
# Guards: Admin destination data design v1.6 (roadmap schema pack, Platform Admin 17 Nov 2026 07:39; RM0C, RM0D, RM0E, RM0F) and G4 database-backed tests:
# migration 20261117040000 on top of 20261115190000 and 20261115230000 runs on an isolated PostgreSQL 16 (fixtures only, never a Supabase project). It proves:
# the pack applies twice; the #1155 importer still works; the destination read is empty lists before any load and returns only approved or published rows of
# a published edition inside their effective dates; one primary locality per postcode; a rule is a visa row or a categorised rule; approval is the Platform
# Admin's; the access history accepts password_reset_sent and still refuses an unknown action.
# Needs a scratch PostgreSQL 16: PGHOST/PGPORT/PGUSER point at it. Drops its database at the end (DSP_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${DSP_DB:-g_destination_schema_pack}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
F=tests/fixtures/destination-schema-pack
S=supabase/migrations-archive/20261115190000_api_v3_additive_schema.sql; G=supabase/migrations-archive/20261115230000_cf247_destination_importer_guard.sql
M=supabase/migrations-archive/20261117040000_cf247_rm_destination_schema_pack.sql
trap '[ -n "${DSP_KEEP:-}" ] || dropdb --if-exists '$DB' >/dev/null 2>&1' EXIT
dropdb --if-exists $DB >/dev/null 2>&1; createdb $DB
psql -X -q -d postgres -c "do \$\$ begin if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if; if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if; if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role; end if; end \$\$"
$P -f tests/fixtures/destination-editions/stubs.sql -f $F/stubs.sql
$P -1 -f $S >/dev/null; $P -1 -f $G >/dev/null
$P -1 -f $M >/dev/null; $P -1 -f $M >/dev/null
echo "migration: applied twice without error (post-check included)"

$P <<'SQL'
create or replace function pg_temp.ok(c boolean, m text) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', m; end if; raise notice 'ok: %', m; end $$;
create or replace function pg_temp.err(q text) returns text language plpgsql as $$ begin execute q; return null; exception when others then return sqlerrm; end $$;
do $t$ declare r jsonb; v_ed uuid; v_ed2 uuid; v_au uuid; v_loc uuid; v_loc2 uuid; v_rule uuid; v_m uuid; v_car uuid; m text; f record; begin
  select id into v_au from ref.countries where iso_alpha2 = 'AU';
  r := security.destination_read_v1();
  perform pg_temp.ok(r->'localities' = '[]'::jsonb and r->'study_rules' = '[]'::jsonb and r->'career_outcomes' = '[]'::jsonb and (r->'totals'->>'localities')::int = 0, 'before any load the destination read is three empty lists');
  perform pg_temp.ok(public.website_v3_destination('{"country_code":"au"}'::jsonb) -> 'filters' ->> 'country_code' = 'AU' and public.zoho_v3_destination() ? 'career_outcomes', 'both v3 wrappers answer');
  perform pg_temp.ok(security.destination_read_v1('{"country_code":"AUS"}'::jsonb)->'error'->>'code' = 'INVALID_INPUT' and security.destination_read_v1('{"section":"x"}'::jsonb)->'error'->>'code' = 'INVALID_INPUT'
    and security.destination_read_v1('{"locality_id":"x"}'::jsonb)->'error'->>'code' = 'INVALID_INPUT', 'bad filters are INVALID_INPUT');

  -- localities, postcodes, metrics
  insert into destination.localities(country_code, name, geography_type, geography_code, boundary_vintage, dataset_edition, attribution_text)
    values ('AU', 'Ballarat', 'SUA', '2003', 'ASGS_2021_ED3', 'ERP 2025-06-30', 'Source: Australian Bureau of Statistics') returning id into v_loc;
  insert into destination.localities(country_code, name, geography_type, geography_code, boundary_vintage, dataset_edition, attribution_text)
    values ('AU', 'Melbourne', 'SUA', '2011', 'ASGS_2021_ED3', 'ERP 2025-06-30', 'Source: Australian Bureau of Statistics') returning id into v_loc2;
  m := pg_temp.err($$insert into destination.localities(country_code, name, geography_type, geography_code, boundary_vintage, dataset_edition, attribution_text) values ('AU', 'Ballarat again', 'SUA', '2003', 'ASGS_2021_ED3', 'x', 'y')$$);
  perform pg_temp.ok(m like '%duplicate key%', 'one locality per country, geography type, vintage and code');
  select * into f from security.destination_postcode_flags_v1(0.93);
  perform pg_temp.ok(f.is_primary_match and not f.needs_layer4_review, 'A-3: a 93% share is a primary match');
  select * into f from security.destination_postcode_flags_v1(0.6);
  perform pg_temp.ok(not f.is_primary_match and f.needs_layer4_review, 'A-3: a 60% share goes to Layer 4');
  update pipeline.platform_toolset_settings set value = to_jsonb(0.5) where key = 'destination.postcode_primary_min_share';
  select * into f from security.destination_postcode_flags_v1(0.6);
  perform pg_temp.ok(f.is_primary_match, 'G2: the share is the setting, not a number in code');
  update pipeline.platform_toolset_settings set value = to_jsonb(0.9) where key = 'destination.postcode_primary_min_share';
  insert into destination.locality_postcodes(locality_id, country_code, postcode, containment_share, is_primary_match, boundary_vintage) values (v_loc, 'AU', '3350', 0.97, true, 'ASGS_2021_ED3');
  m := pg_temp.err(format($$insert into destination.locality_postcodes(locality_id, country_code, postcode, containment_share, is_primary_match, boundary_vintage) values (%L, 'AU', '3350', 0.03, true, 'ASGS_2021_ED3')$$, v_loc2));
  perform pg_temp.ok(m like '%duplicate key%', 'one primary locality per postcode and vintage');
  m := pg_temp.err(format($$insert into destination.locality_postcodes(locality_id, country_code, postcode, containment_share, is_primary_match, needs_layer4_review, boundary_vintage) values (%L, 'AU', '3351', 1.2, false, true, 'ASGS_2021_ED3')$$, v_loc2));
  perform pg_temp.ok(m like '%check constraint%', 'a share is between 0 and 1');
  insert into destination.locality_metrics(locality_id, metric_category, metric_key, numeric_value, unit, reference_period, dataset_edition, source_url, attribution_text)
    values (v_loc, 'population', 'erp_persons', 119096, 'persons', '2025-06-30', 'Regional population 2024-25', 'https://www.abs.gov.au/statistics/people/population/regional-population/2024-25', 'Source: Australian Bureau of Statistics') returning id into v_m;
  perform pg_temp.ok((security.destination_read_v1()->'totals'->>'localities')::int = 0, 'a draft locality is not returned');

  -- approval is the Platform Admin's
  m := pg_temp.err(format($$select public.admin_destination_set_status('locality', %L, 'approved', 'ABS approval A-1')$$, v_loc));
  perform pg_temp.ok(m = 'authentication required', 'no session: refused');
  perform set_config('fixture.uid', '11111111-1111-1111-1111-111111111111', true); perform set_config('fixture.rank', '3', true);
  m := pg_temp.err(format($$select public.admin_destination_set_status('locality', %L, 'approved', 'ABS approval A-1')$$, v_loc));
  perform pg_temp.ok(m like 'Platform Admin (rank 6)%', 'a Curator cannot approve');
  perform pg_temp.ok((public.admin_destination_overview()->'localities'->>'draft')::int = 2 and jsonb_array_length(public.admin_destination_review('locality', 'draft')->'rows') = 2, 'a Curator reads the overview and the review list');
  perform set_config('fixture.rank', '6', true);
  m := pg_temp.err(format($$select public.admin_destination_set_status('locality', %L, 'approved', ' ')$$, v_loc));
  perform pg_temp.ok(m = 'a reason is required', 'approval needs a reason');
  r := public.admin_destination_set_status('locality', v_loc, 'approved', 'ABS approval A-1');
  perform pg_temp.ok(r->>'from' = 'draft' and r->>'to' = 'approved' and (r->>'changed')::boolean, 'the Platform Admin approves a locality');
  r := security.destination_read_v1('{"country_code":"AU","section":"localities"}'::jsonb);
  perform pg_temp.ok((r->'totals'->>'localities')::int = 1 and r->'localities'->0->>'name' = 'Ballarat' and r->'localities'->0->'metrics' = '[]'::jsonb, 'the approved locality is returned; its draft metric is not');
  perform public.admin_destination_set_status('locality_metric', v_m, 'published', 'ABS approval A-1');
  r := security.destination_read_v1('{"postcode":"3350"}'::jsonb);
  perform pg_temp.ok(r->'localities'->0->'metrics'->0->>'key' = 'erp_persons' and r->'localities'->0->'metrics'->0->>'attribution' like 'Source: Australian Bureau%' and r->'localities'->0->>'attribution' is not null,
    'a postcode finds its primary locality; the published figure carries its attribution');
  perform pg_temp.ok((security.destination_read_v1('{"postcode":"9999"}'::jsonb)->'totals'->>'localities')::int = 0 and (security.destination_read_v1('{"country_code":"NZ"}'::jsonb)->'totals'->>'localities')::int = 0, 'other postcodes and countries are empty');

  -- study rules: the #1155 importer still works; general rules sit beside visa rows
  r := security.destination_import_v1(jsonb_build_object('edition', jsonb_build_object('country_code', 'AU', 'domain', 'study_rules', 'edition_label', '2026', 'effective_from', '2026-07-01',
         'source_url', 'https://immi.homeaffairs.gov.au', 'source_owner', 'Department of Home Affairs', 'attribution_text', 'Source: Department of Home Affairs'),
       'rows', jsonb_build_array(jsonb_build_object('visa_subclass', '500', 'visa_name', 'Student visa', 'application_fee_amount', 2000, 'fee_currency', 'AUD'))));
  v_ed := (r->>'edition_id')::uuid;
  perform pg_temp.ok((r->>'inserted')::int = 1 and (select approval_status from destination.study_rules where visa_subclass = '500') = 'draft', 'the existing importer still loads a visa row; it starts as a draft');
  m := pg_temp.err(format($$insert into destination.study_rules(edition_id, country_id, source_url) values (%L, %L, 'u')$$, v_ed, v_au));
  perform pg_temp.ok(m like '%study_rules_kind_check%', 'a rule is a visa row or a categorised, titled rule');
  m := pg_temp.err(format($$insert into destination.study_rules(edition_id, country_id, source_url, rule_category, title) values (%L, %L, 'u', 'tuition', 't')$$, v_ed, v_au));
  perform pg_temp.ok(m like '%study_rules_rule_category_check%', 'an unknown rule category is refused');
  insert into destination.study_rules(edition_id, country_id, source_url, rule_category, applicant_scope, title, summary, effective_from, quote_on_page, evidence_date)
    values (v_ed, v_au, 'https://www.studyaustralia.gov.au', 'application_route', 'international', 'Apply direct to the institution', 'International applicants apply to the provider.', '2026-01-01', 'apply directly', '2026-11-17')
    returning id into v_rule;
  insert into destination.study_rules(edition_id, country_id, source_url, rule_category, title, effective_from)
    values (v_ed, v_au, 'https://www.studyaustralia.gov.au', 'work_rights', 'A rule that starts later', current_date + 30);
  insert into destination.rule_applicability(rule_id, entity_type, entity_id, applicability_status, evidence_url) values (v_rule, 'country', v_au, 'proven', 'https://www.studyaustralia.gov.au');
  insert into destination.rule_applicability(rule_id, entity_type, entity_code, applicability_status, evidence_url) values (v_rule, 'state', 'VIC', 'excluded', 'https://www.vtac.edu.au');
  m := pg_temp.err(format($$insert into destination.rule_applicability(rule_id, entity_type, entity_code, applicability_status, evidence_url) values (%L, 'state', 'VIC', 'proven', 'u')$$, v_rule));
  perform pg_temp.ok(m like '%duplicate key%', 'one applicability row per rule and entity');
  perform public.admin_destination_set_status('study_rule', v_rule, 'approved', 'page read 17 Nov');
  update destination.study_rules set approval_status = 'approved' where title = 'A rule that starts later';
  perform pg_temp.ok((select approved_by from destination.study_rules where id = v_rule) = '11111111-1111-1111-1111-111111111111', 'the approver is recorded on the rule');
  perform pg_temp.ok((security.destination_read_v1()->'totals'->>'study_rules')::int = 0, 'an approved rule of an unpublished edition is not returned');
  perform security.destination_edition_set_terms_v1(v_ed, 'approved', null); perform security.destination_edition_publish_v1(v_ed, null);
  r := security.destination_read_v1('{"country_code":"AU","section":"study_rules"}'::jsonb);
  perform pg_temp.ok((r->'totals'->>'study_rules')::int = 1 and r->'study_rules'->0->>'rule_category' = 'application_route' and jsonb_array_length(r->'study_rules'->0->'applicability') = 2
    and r->'study_rules'->0->>'attribution' = 'Source: Department of Home Affairs' and r->'localities' = '[]'::jsonb,
    'published edition: only the approved rule inside its dates is returned (not the draft visa row, not the future rule), with applicability and attribution');
  m := pg_temp.err(format($$select public.admin_destination_set_status('study_rule', %L, 'withdrawn', 'x')$$, v_rule));
  perform pg_temp.ok(m like 'DESTINATION_EDITION_FIXED%', 'rows of a published edition stay fixed: a change is a new edition');

  -- career outcomes
  r := security.destination_import_v1(jsonb_build_object('edition', jsonb_build_object('country_code', 'AU', 'domain', 'career_outcomes', 'edition_label', '2026', 'effective_from', '2026-07-01',
         'source_url', 'https://www.jobsandskills.gov.au', 'source_owner', 'Jobs and Skills Australia', 'attribution_text', 'Source: Jobs and Skills Australia'),
       'rows', jsonb_build_array(jsonb_build_object('occupation_code', '2613', 'occupation_title', 'Software and Applications Programmers', 'median_salary', 110000, 'salary_currency', 'AUD', 'job_outlook_rating', 'strong'),
                                 jsonb_build_object('occupation_code', '2544', 'occupation_title', 'Registered Nurses', 'salary_currency', 'AUD'))));
  v_ed2 := (r->>'edition_id')::uuid;
  update destination.career_outcomes set occupation_scheme = 'ANZSCO', reference_period = '2025' where edition_id = v_ed2;
  m := pg_temp.err($$update destination.career_outcomes set occupation_scheme = 'ISCO'$$);
  perform pg_temp.ok(m like '%career_outcomes_occupation_scheme_check%', 'occupation scheme is ANZSCO, NOC or SOC');
  select id into v_car from destination.career_outcomes where occupation_code = '2613';
  perform public.admin_destination_set_status('career_outcome', v_car, 'approved', 'JSA edition read');
  perform security.destination_edition_set_terms_v1(v_ed2, 'approved', null); perform security.destination_edition_publish_v1(v_ed2, null);
  r := security.destination_read_v1('{"section":"career_outcomes"}'::jsonb);
  perform pg_temp.ok((r->'totals'->>'career_outcomes')::int = 1 and r->'career_outcomes'->0->>'occupation_scheme' = 'ANZSCO' and (r->'career_outcomes'->0->>'median_annual_earnings')::numeric = 110000
    and r->'career_outcomes'->0->>'currency_code' = 'AUD' and r->'career_outcomes'->0->>'demand_rating' = 'strong' and r->'career_outcomes'->0->>'attribution' = 'Source: Jobs and Skills Australia',
    'only the approved outcome of the published edition is returned, with earnings, currency, demand and attribution');
  r := security.destination_read_v1('{}'::jsonb, 1, 100000);
  perform pg_temp.ok((r->>'page_size')::int = 100, 'G2: the page size is capped by the setting');

  -- schemes and access history
  perform pg_temp.ok((select count(*) from ref.registration_schemes) = 18 and (select never_mixed_with @> '{pgwp}' from ref.registration_schemes where scheme = 'ircc_dli')
    and (select count(*) from ref.registration_schemes where kind = 'field_of_study') = 5, 'the scheme register lists every scheme once per kind and country; DLI is never mixed with PGWP');
  insert into security.user_access_events(action) values ('password_reset_sent'), ('user_invited');
  m := pg_temp.err($$insert into security.user_access_events(action) values ('user_deleted')$$);
  perform pg_temp.ok(m like '%user_access_events_action_check%', 'the access history accepts password_reset_sent and still refuses an unknown action');
  perform pg_temp.ok(not has_function_privilege('anon', 'public.website_v3_destination(jsonb, int, int)', 'execute') and not has_function_privilege('authenticated', 'public.zoho_v3_destination(jsonb, int, int)', 'execute')
    and not has_function_privilege('anon', 'public.admin_destination_overview()', 'execute') and has_function_privilege('service_role', 'public.website_v3_destination(jsonb, int, int)', 'execute'),
    'the v3 wrappers are the service role''s; anon reaches nothing');
  perform pg_temp.ok((select bool_and(relrowsecurity) from pg_class where oid in ('destination.localities'::regclass, 'destination.locality_postcodes'::regclass, 'destination.locality_metrics'::regclass,
    'destination.rule_applicability'::regclass, 'ref.registration_schemes'::regclass)), 'row level security is on for every new table');
end $t$;
SQL
echo "destination schema pack: all checks passed"
