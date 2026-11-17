#!/usr/bin/env bash
# Guards: Admin destination data UI and ingestion specification v1.2 (RM0F; decisions G-2, G-3, G-5, Platform Admin 17 Nov 2026 11:52 and 13:12) and G4
# database-backed tests: migration 20261117131500 on top of 20261115190000, 20261115230000 and 20261117040000 runs on an isolated PostgreSQL 16
# (fixtures only, never a Supabase project). It proves: the migration applies twice; edition terms and publish are the Platform Admin's with a reason;
# a postcode below the share is a Layer 4 "Campus locality" item per campus and one decision settles the postcode; campuses[].locality appears on the
# Zoho v3 provider answer only for an approved locality; the review lists carry applicability and stored evidence; the Course and Provider reads keep
# DLI apart from PGWP.
# Needs a scratch PostgreSQL 16: PGHOST/PGPORT/PGUSER point at it. Drops its database at the end (DAU_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${DAU_DB:-g_destination_admin_ui}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
F=tests/fixtures/destination-admin-ui
M=supabase/migrations/20261117131500_cf247_rm0f_destination_admin_ui.sql
trap '[ -n "${DAU_KEEP:-}" ] || dropdb --if-exists '$DB' >/dev/null 2>&1' EXIT
dropdb --if-exists $DB >/dev/null 2>&1; createdb $DB
psql -X -q -d postgres -c "do \$\$ begin if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if; if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if; if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role; end if; end \$\$"
$P -f tests/fixtures/destination-editions/stubs.sql -f tests/fixtures/destination-schema-pack/stubs.sql
$P -1 -f supabase/migrations/20261115190000_api_v3_additive_schema.sql >/dev/null
$P -1 -f supabase/migrations/20261115230000_cf247_destination_importer_guard.sql >/dev/null
$P -1 -f supabase/migrations/20261117040000_cf247_rm_destination_schema_pack.sql >/dev/null
$P -f $F/stubs.sql
$P -1 -f $M >/dev/null; $P -1 -f $M >/dev/null
echo "migration: applied twice without error (post-check included)"

$P <<'SQL'
create or replace function pg_temp.ok(c boolean, m text) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', m; end if; raise notice 'ok: %', m; end $$;
create or replace function pg_temp.err(q text) returns text language plpgsql as $$ begin execute q; return null; exception when others then return sqlerrm; end $$;
do $t$ declare r jsonb; m text; v_au uuid; v_prov uuid; v_c1 uuid; v_c2 uuid; v_c3 uuid; v_course uuid; v_geel uuid; v_ball uuid; v_ed uuid; v_rule uuid; v_ev uuid; begin
  select id into v_au from ref.countries where iso_alpha2 = 'AU';
  insert into catalogue.providers(stable_key, canonical_name, display_name, country_id) values ('prov-deakin', 'Deakin University', 'Deakin University', v_au) returning id into v_prov;
  insert into catalogue.campuses(provider_id, name, city, postcode, is_primary, primary_basis) values (v_prov, 'Waurn Ponds', 'Geelong', '3216', true, 'cricos_head_office') returning id into v_c1;
  insert into catalogue.campuses(provider_id, name, city, postcode) values (v_prov, 'Waterfront', 'Geelong', '3220') returning id into v_c2;
  insert into catalogue.campuses(provider_id, name, city, postcode) values (v_prov, 'Second building', 'Geelong', '3216') returning id into v_c3;
  insert into catalogue.courses(provider_id) values (v_prov) returning id into v_course;
  insert into destination.localities(country_code, name, geography_type, geography_code, boundary_vintage, dataset_edition, attribution_text) values
    ('AU', 'Geelong', 'SUA', '2008', 'ASGS_2021_ED3', 'ERP 2025-06-30', 'Source: Australian Bureau of Statistics') returning id into v_geel;
  insert into destination.localities(country_code, name, geography_type, geography_code, boundary_vintage, dataset_edition, attribution_text) values
    ('AU', 'Ballarat', 'SUA', '2003', 'ASGS_2021_ED3', 'ERP 2025-06-30', 'Source: Australian Bureau of Statistics') returning id into v_ball;
  insert into destination.locality_postcodes(locality_id, country_code, postcode, containment_share, is_primary_match, needs_layer4_review, boundary_vintage) values
    (v_geel, 'AU', '3220', 0.99, true, false, 'ASGS_2021_ED3'), (v_geel, 'AU', '3216', 0.62, false, true, 'ASGS_2021_ED3'), (v_ball, 'AU', '3216', 0.05, false, true, 'ASGS_2021_ED3');

  -- sign-in and ranks
  m := pg_temp.err($$select public.admin_destination_overview()$$);
  perform pg_temp.ok(m = 'authentication required', 'no session: refused');
  perform set_config('fixture.uid', '22222222-2222-2222-2222-222222222222', true); perform set_config('fixture.rank', '3', true);
  r := public.admin_destination_overview();
  perform pg_temp.ok((r->>'campuses_waiting_locality')::int = 2 and (r->'locality_postcodes'->>'postcodes_needing_review')::int = 1 and r->'loads' = '[]'::jsonb and jsonb_typeof(r->'editions_list') = 'array'
    and (r->>'postcode_primary_min_share')::numeric = 0.9, 'overview: two campuses wait on one postcode; no load job is catalogued yet; the share is the setting');
  insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank) values ('destination-abs-load', 'Destination data', 10, 'ABS population and postcodes', 'Loads localities', 5);
  perform pg_temp.ok(public.admin_destination_overview()->'loads'->0->>'jobname' = 'destination-abs-load', 'a catalogued destination- job appears as a load');

  -- Layer 4 kind hook (G-3)
  r := security.layer4_campus_locality_inbox_counts_v1();
  perform pg_temp.ok((r->>'n')::int = 2 and r->>'kind' = 'campus_locality' and (r->'by_provider'->0->>'n')::int = 2 and r->'by_provider'->0->>'provider_id' = v_prov::text, 'Layer 4 counts: one item per campus, by provider');
  r := security.layer4_campus_locality_inbox_page_v1(jsonb_build_object('provider_id', v_prov, 'limit', 1));
  perform pg_temp.ok(jsonb_array_length(r->'items') = 1 and r->'items'->0->>'why' like 'Largest share is Geelong at 62%, below the 90%%' and r->'items'->0->>'suggestion' = 'Accept Geelong (62%)'
    and r->'items'->0->>'provider' = 'Deakin University' and r->'items'->0 ? 'ref' and r->'items'->0 ? 'created_at', 'Layer 4 page: the contract''s item fields, with why and a suggestion');
  r := security.layer4_campus_locality_inbox_page_v1(jsonb_build_object('limit', 50, 'after_at', r->'items'->0->>'created_at', 'after_ref', r->'items'->0->>'ref'));
  perform pg_temp.ok(jsonb_array_length(r->'items') = 1 and (r->>'before')::int = 1, 'Layer 4 page: the next page starts strictly after the cursor and reports what came before');
  r := security.layer4_campus_locality_inbox_detail_v1(v_c1::text);
  perform pg_temp.ok(r->'sections'->0->'body' ? 'Geelong (code 2008, SUA)' and jsonb_array_length(r->'actions') = 3, 'Layer 4 detail: candidates and the three actions');
  r := security.layer4_campus_locality_inbox_decide_v1(v_c1::text, 'choose_locality', 'Bendigo', null);
  perform pg_temp.ok(not (r->>'ok')::boolean and r->>'request' like 'Enter the code or name of one of the candidate localities%', 'a locality that is not a candidate is asked again, not accepted');
  r := security.layer4_campus_locality_inbox_decide_v1(v_c1::text, 'accept_largest', null, 'main campus is in Geelong');
  perform pg_temp.ok((r->>'ok')::boolean and r->>'returns' = 'Postcode 3216 now maps to Geelong.' and (security.layer4_campus_locality_inbox_counts_v1()->>'n')::int = 0
    and (select count(*) from pipeline.admin_control_events where area = 'layer4' and action = 'inbox_decide' and target = 'campus_locality:' || v_c1) = 1
    and (select count(*) from pipeline.admin_control_events where area = 'destination' and action = 'postcode_resolve') = 1
    and (select resolve_reason from destination.locality_postcodes where postcode = '3216' and is_primary_match) = 'main campus is in Geelong',
    'one decision settles the postcode for both campuses, with its reason and both audit rows');
  r := security.layer4_campus_locality_inbox_decide_v1(v_c3::text, 'no_locality', null, null);
  perform pg_temp.ok(not (r->>'ok')::boolean, 'a settled postcode cannot be decided twice');

  -- postcode resolve from the screen
  m := pg_temp.err($$select public.admin_destination_postcode_resolve('AU', '3216', null, ' ')$$);
  perform pg_temp.ok(m = 'a reason is required', 'resolve needs a reason');
  m := pg_temp.err($$select public.admin_destination_postcode_resolve('AU', '9999', null, 'x')$$);
  perform pg_temp.ok(m like 'no candidate locality is held for postcode 9999%', 'an unknown postcode is refused');
  r := public.admin_destination_postcode_resolve('AU', '3216', null, 'boundary straddles two areas');
  perform pg_temp.ok((select count(*) from destination.locality_postcodes where postcode = '3216' and (is_primary_match or needs_layer4_review)) = 0, 'a Curator can record a postcode as outside every locality');
  perform public.admin_destination_postcode_resolve('AU', '3216', v_geel, 'back to Geelong');

  -- G-5: locality only once the locality is approved
  perform pg_temp.ok(security.destination_locality_for_postcode_v1('au', '3220') is null, 'a draft locality gives no locality on the API');
  update destination.localities set status = 'approved' where id = v_geel;
  r := public.zoho_v3_provider('prov-deakin');
  perform pg_temp.ok((select count(*) from jsonb_array_elements(r->'item'->'campuses') e where e->'locality'->>'name' = 'Geelong' and e->'locality'->>'geography_type' = 'SUA') = 3
    and r->'item'->'campuses'->0->'locality' ? 'match_share' and r->>'api_version' = 'zoho-v2', 'Zoho v3 provider: every campus carries its approved locality; the rest of the v2 answer is unchanged');
  perform pg_temp.ok(public.zoho_v3_provider('nobody')->'item'->'campuses' = '[]'::jsonb, 'a provider without campuses is unchanged');

  -- editions: terms and publish are the Platform Admin's, with a reason
  r := security.destination_import_v1(jsonb_build_object('edition', jsonb_build_object('country_code', 'AU', 'domain', 'study_rules', 'edition_label', '2026', 'effective_from', '2026-07-01',
         'source_url', 'https://immi.homeaffairs.gov.au', 'source_owner', 'Department of Home Affairs', 'attribution_text', 'Source: Department of Home Affairs'),
       'rows', jsonb_build_array(jsonb_build_object('visa_subclass', '500', 'visa_name', 'Student visa', 'fee_currency', 'AUD'))));
  v_ed := (r->>'edition_id')::uuid;
  m := pg_temp.err(format($$select public.admin_destination_edition_publish(%L, 'ready')$$, v_ed));
  perform pg_temp.ok(m like 'Platform Admin (rank 6)%', 'a Curator cannot publish an edition');
  perform set_config('fixture.rank', '6', true);
  m := pg_temp.err(format($$select public.admin_destination_edition_set_terms(%L, 'approved', '')$$, v_ed));
  perform pg_temp.ok(m = 'a reason is required', 'terms need a reason');
  insert into pipeline.evidence_artifacts(source_url, storage_path) values ('https://www.studyaustralia.gov.au/apply', 'evidence/x.html') returning id into v_ev;
  insert into destination.study_rules(edition_id, country_id, source_url, rule_category, title, quote_on_page, evidence_id, effective_from)
    values (v_ed, v_au, 'https://www.studyaustralia.gov.au/apply', 'application_route', 'Apply direct to the institution', 'apply directly', v_ev, '2026-01-01') returning id into v_rule;
  insert into destination.rule_applicability(rule_id, entity_type, entity_id, applicability_status, evidence_url) values (v_rule, 'country', v_au, 'proven', 'https://www.studyaustralia.gov.au');
  insert into destination.rule_applicability(rule_id, entity_type, entity_code, applicability_status, evidence_url) values (v_rule, 'state', 'VIC', 'excluded', 'https://www.vtac.edu.au');
  r := public.admin_destination_review('study_rule', 'draft');
  perform pg_temp.ok((select count(*) from jsonb_array_elements(r->'rows') x where x->>'title' = 'Apply direct to the institution' and jsonb_array_length(x->'applicability') = 2
    and x->'evidence'->>'stored' = 'true' and x->>'country_code' = 'AU' and x->'applicability'->0->>'entity_name' = 'Australia') = 1,
    'rule review: applicability rows with names, and the stored page the quote is checked against');
  perform public.admin_destination_set_status('study_rule', v_rule, 'approved', 'quote found on the stored page');
  r := public.admin_destination_edition_set_terms(v_ed, 'approved', 'Home Affairs material is open licence');
  perform pg_temp.ok(r->>'to' = 'approved' and r->>'from' is distinct from 'approved', 'the Platform Admin records the terms');
  r := public.admin_destination_edition_publish(v_ed, 'rows approved 17 Nov');
  perform pg_temp.ok(r->>'to' = 'published' and (select count(*) from pipeline.admin_control_events where area = 'destination' and action in ('edition_terms', 'edition_publish') and detail->>'reason' is not null) = 2,
    'the Platform Admin publishes; both steps are in the control log with their reasons');
  r := public.admin_destination_overview();
  perform pg_temp.ok((select count(*) from jsonb_array_elements(r->'editions_list') e where e->>'status' = 'published' and (e->>'attribution_present')::boolean and (e->>'rows')::int = 2 and (e->>'rows_approved')::int = 1) = 1,
    'overview: the edition with its terms, attribution check and approved rows');
  r := public.admin_destination_review('postcode');
  perform pg_temp.ok(r->'rows' = '[]'::jsonb and (public.admin_destination_review('locality')->'rows'->0 ? 'postcodes_primary'), 'review: no postcode waits; localities carry their postcode counts');

  -- adapted screens
  perform set_config('fixture.rank', '1', true);
  insert into catalogue.course_registrations(course_id, scheme, registration_code, status) values (v_course, 'cricos', '0100123', 'active'), (v_course, 'pgwp', 'eligible', 'active');
  insert into catalogue.provider_registrations(provider_id, registration_scheme, registration_code, status) values (v_prov, 'cricos', '00113B', 'active'), (v_prov, 'ircc_dli', 'O000', 'active');
  r := public.admin_course_destination_read(v_course);
  perform pg_temp.ok((select count(*) from jsonb_array_elements(r->'registrations') x where x->>'scheme' = 'cricos' and x->>'label' = 'CRICOS course code' and (x->>'registered_scheme')::boolean) = 1
    and r->'study_rules'->0->>'title' = 'Apply direct to the institution' and r->'study_rules'->0->>'applies_through' = 'country' and r->'field_schemes'->0->>'scheme' = 'asced',
    'course read: registrations by scheme with their authority, the field scheme of the country, and the proven rules');
  r := public.admin_provider_destination_read(v_prov);
  perform pg_temp.ok(r->'campuses'->0->>'name' = 'Waurn Ponds' and (r->'campuses'->0->>'is_primary')::boolean and r->'campuses'->0->'locality'->>'name' = 'Geelong'
    and (select count(*) from jsonb_array_elements(r->'registrations') x where x->>'scheme' = 'pgwp') = 0
    and (select count(*) from jsonb_array_elements(r->'registrations') x where x->>'scheme' = 'ircc_dli') = 1 and (r->'work_eligibility'->>'courses')::int = 1 and r->'work_eligibility'->>'scheme' = 'pgwp',
    'provider read: primary campus first with its locality; DLI is a provider registration and PGWP is counted apart, per course');
  perform pg_temp.ok(not has_function_privilege('anon', 'public.admin_destination_edition_publish(uuid, text)', 'execute') and not has_function_privilege('authenticated', 'security.destination_postcode_resolve_v1(text, text, uuid, uuid, text)', 'execute')
    and not has_function_privilege('authenticated', 'security.layer4_campus_locality_inbox_decide_v1(text, text, text, text)', 'execute'), 'anon reaches nothing; the internal functions are not callable from the browser');
end $t$;
SQL
echo "destination admin UI: all checks passed"
