#!/usr/bin/env bash
# Guards: API v3 course fields and city profiles edition rows (Platform Admin 18 Nov 2026 10:33 and 10:34, ref G7QN3W) and G4 database-backed tests:
# migration 20261118133707 on top of the destination schema (20261115190000, 20261115230000, 20261117040000, 20261117131500) and the v3 course item
# (20261113180000) runs on an isolated PostgreSQL 16 (fixtures only, never a Supabase project). It proves: the migration applies twice; every v3 course
# item carries study_load and empty_reason_code from the catalogue, each campus the approved locality its postcode maps to (never a draft one), and the
# provider's active, unexpired accreditations; the intake reading is unchanged; the provider action carries accreditations; a city profiles edition
# counts the localities its load wrote (by country and edition name) and their figures, publishes once one is approved, and is refused before;
# other domains keep their check.
# Needs a scratch PostgreSQL 16: PGHOST/PGPORT/PGUSER point at it. Drops its database at the end (V3CF_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${V3CF_DB:-g_api_v3_course_fields}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
F=tests/fixtures/api-v3-course-fields
M=supabase/migrations-archive/20261118133707_cf247_api_v3_course_study_load_edition_rows.sql
trap '[ -n "${V3CF_KEEP:-}" ] || dropdb --if-exists '$DB' >/dev/null 2>&1' EXIT
dropdb --if-exists $DB >/dev/null 2>&1; createdb $DB
psql -X -q -d postgres -c "do \$\$ begin if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if; if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if; if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role; end if; end \$\$"
$P -f tests/fixtures/destination-editions/stubs.sql -f tests/fixtures/destination-schema-pack/stubs.sql
$P -1 -f supabase/migrations-archive/20261115190000_api_v3_additive_schema.sql >/dev/null
$P -1 -f supabase/migrations-archive/20261115230000_cf247_destination_importer_guard.sql >/dev/null
$P -1 -f supabase/migrations-archive/20261117040000_cf247_rm_destination_schema_pack.sql >/dev/null
$P -f tests/fixtures/destination-admin-ui/stubs.sql
$P -1 -f supabase/migrations-archive/20261117131500_cf247_rm0f_destination_admin_ui.sql >/dev/null
$P -f $F/stubs.sql -f $F/r28.sql
$P -1 -f $M >/dev/null; $P -1 -f $M >/dev/null
echo "migration: applied twice without error (post-check included)"

# the header's before -> after body md5 lines are what the live database now holds
for sig in "public.website_v3_course_item_r28(jsonb)" "public.website_v3_provider_item(jsonb)" "security.destination_edition_publish_v1(uuid,uuid)" "public.admin_destination_overview()"; do
  want=$(grep -F -- "--   $sig " $M | awk '{print $NF}')
  got=$($P -A -t -c "select md5(prosrc) from pg_proc where oid = '$sig'::regprocedure")
  [ "$want" = "$got" ] || { echo "FAIL: $sig body md5 $got, header says $want" >&2; exit 1; }
done
echo "ok: the four edited bodies match the header"

$P <<'SQL'
create or replace function pg_temp.ok(c boolean, m text) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', m; end if; raise notice 'ok: %', m; end $$;
create or replace function pg_temp.err(q text) returns text language plpgsql as $$ begin execute q; return null; exception when others then return sqlerrm; end $$;
do $t$ declare v_au uuid := (select id from ref.countries where iso_alpha2 = 'AU'); v_p uuid; v_c uuid; v_melb uuid; v_geel uuid; v_ed uuid; v_sr uuid; it jsonb; r jsonb; m text; begin
  -- a provider, a course with a study load and an empty reason, two localities (one approved, one draft) and three accreditations
  insert into catalogue.providers(stable_key, canonical_name, country_id) values ('provider:x', 'Provider X', v_au) returning id into v_p;
  insert into catalogue.courses(provider_id, study_load, empty_reason_code) values (v_p, 'both', 'online_only_no_campus') returning id into v_c;
  insert into search.course_documents(course_id, provider_id, course_stable_key) values (v_c, v_p, 'course:x');
  insert into catalogue.course_intakes(course_id, status, intake_label, intake_year) values (v_c, 'active', 'February', 2027);
  insert into destination.localities(country_code, name, geography_type, geography_code, boundary_vintage, dataset_edition, attribution_text, status)
  values ('AU', 'Melbourne', 'SUA', '2079', 'ASGS_2021_ED3', 'Edition A', 'Source: ABS', 'approved') returning id into v_melb;
  insert into destination.localities(country_code, name, geography_type, geography_code, boundary_vintage, dataset_edition, attribution_text, status)
  values ('AU', 'Geelong', 'SUA', '2003', 'ASGS_2021_ED3', 'Edition A', 'Source: ABS', 'draft') returning id into v_geel;
  insert into destination.locality_postcodes(locality_id, country_code, postcode, containment_share, is_primary_match, needs_layer4_review, boundary_vintage) values
    (v_melb, 'AU', '3000', 0.99, true, false, 'ASGS_2021_ED3'), (v_geel, 'AU', '3220', 0.98, true, false, 'ASGS_2021_ED3');
  insert into catalogue.provider_accreditations(provider_id, body_code, accredited_unit_name, status, expires_at, source_url) values
    (v_p, 'AACSB', 'Business School', 'active', null, 'https://www.aacsb.edu/'), (v_p, 'EQUIS', 'Business School', 'active', current_date - 1, 'https://www.efmdglobal.org/'),
    (v_p, 'AMBA', null, 'revoked', null, 'https://www.associationofmbas.com/');

  it := public.website_v3_course_item_r28('{"course_id":"COURSE:X","country_code":"AU","title":"T","intakes":[{"label":"February","year":2027}],
          "campuses":[{"city":"Melbourne","postcode":"3000"},{"city":"Geelong","postcode":"3220"},{"city":"Online"}],"provider":{"provider_id":"provider:x","name":"Provider X"}}'::jsonb);
  perform pg_temp.ok(it->>'study_load' = 'both' and it->>'empty_reason_code' = 'online_only_no_campus', 'study_load and empty_reason_code come from the catalogue');
  perform pg_temp.ok(it #>> '{campuses,0,locality,name}' = 'Melbourne' and (it #>> '{campuses,0,locality,match_share}')::numeric = 0.99, 'a campus postcode with an approved primary locality carries it');
  perform pg_temp.ok((it->'campuses'->1) ? 'locality' and jsonb_typeof(it #> '{campuses,1,locality}') = 'null', 'a draft locality is never returned (null)');
  perform pg_temp.ok((it->'campuses'->2) ? 'locality' and jsonb_typeof(it #> '{campuses,2,locality}') = 'null', 'a campus without a postcode has locality null');
  perform pg_temp.ok(jsonb_array_length(it #> '{provider,accreditations}') = 1 and it #>> '{provider,accreditations,0,body_code}' = 'AACSB'
                     and it #>> '{provider,name}' = 'Provider X', 'the provider carries only active, unexpired accreditations, and keeps its fields');
  perform pg_temp.ok(it #>> '{intakes,0,start_date_status}' = 'month_only' and it->>'title' = 'T', 'the intake reading (R28) and every other field are unchanged');
  it := public.website_v3_course_item_r28('{"course_id":"course:x","country_code":"AU"}'::jsonb);
  perform pg_temp.ok(it->>'study_load' = 'both' and not (it ? 'intakes') and not (it ? 'campuses'), 'an item without intakes still carries the fields, and gains no lists');
  it := public.website_v3_course_item_r28('{"course_id":"course:none","country_code":"AU","provider":{"provider_id":"p"}}'::jsonb);
  perform pg_temp.ok(it ? 'study_load' and jsonb_typeof(it->'study_load') = 'null' and jsonb_typeof(it->'empty_reason_code') = 'null'
                     and it #> '{provider,accreditations}' = '[]'::jsonb, 'an unknown course has null fields and no accreditations');
  perform pg_temp.ok(public.website_v3_course_item_r28(null) is null and public.website_v3_course_item_r28('[1]'::jsonb) = '[1]'::jsonb, 'a null or non-object item is returned as it came');
  it := public.website_v3_provider_item('{"provider_id":"provider:x","campuses":[]}'::jsonb);
  perform pg_temp.ok(jsonb_array_length(it->'accreditations') = 1 and it ? 'scholarships_page_url', 'the provider action carries accreditations beside its other fields');

  -- a city profiles edition: the localities its load wrote count as its rows (country and edition name), with the figures beside
  insert into destination.editions(country_id, domain, edition_label, effective_from, status, source_url, source_owner, attribution_text, terms_status)
  values (v_au, 'city_profiles', 'Edition B', current_date, 'draft', 'https://www.abs.gov.au/', 'ABS', 'Source: ABS', 'approved') returning id into v_ed;
  insert into destination.localities(country_code, name, geography_type, geography_code, boundary_vintage, dataset_edition, attribution_text, status)
  select 'AU', 'B' || i, 'SUA', 'B' || i, 'ASGS_2021_ED3', 'Edition B', 'Source: ABS', 'draft' from generate_series(1, 3) i;
  insert into destination.localities(country_code, name, geography_type, geography_code, boundary_vintage, dataset_edition, attribution_text, status)
  values ('NZ', 'Elsewhere', 'SUA', 'N1', 'ASGS_2021_ED3', 'Edition B', 'Source: Stats NZ', 'approved');
  insert into destination.locality_metrics(locality_id, metric_category, metric_key, numeric_value, unit, reference_period, dataset_edition, source_url, attribution_text, status)
  select l.id, 'population', 'erp_persons', 100, 'persons', '2025-06-30', 'Edition B', 'https://www.abs.gov.au/', 'Source: ABS', 'draft' from destination.localities l where l.dataset_edition = 'Edition B';
  r := security.destination_edition_rows_v1(v_ed);
  perform pg_temp.ok((r->>'rows')::int = 3 and (r->>'rows_approved')::int = 0 and (r #>> '{figures,held}')::int = 3, 'the edition counts its 3 AU localities and their figures; another country''s locality of the same name is not counted');
  m := pg_temp.err(format('select security.destination_edition_publish_v1(%L, null)', v_ed));
  perform pg_temp.ok(m like 'INVALID_INPUT: an edition with no approved rows cannot be published%', 'Publish edition is refused while no locality is approved: ' || coalesce(m, 'no error'));
  update destination.localities set status = 'approved' where dataset_edition = 'Edition B' and name in ('B1', 'B2');
  update destination.locality_metrics set status = 'approved' where dataset_edition = 'Edition B';
  r := security.destination_edition_rows_v1(v_ed);
  perform pg_temp.ok((r->>'rows_approved')::int = 2 and (r #>> '{figures,approved}')::int = 2, 'a figure counts as approved only when its locality is approved too (2 of 3)');
  perform set_config('fixture.uid', '66666666-6666-6666-6666-666666666666', true); perform set_config('fixture.rank', '3', true);
  r := (select x from jsonb_array_elements(public.admin_destination_overview()->'editions_list') x where x->>'edition_id' = v_ed::text);
  perform pg_temp.ok((r->>'rows')::int = 3 and (r->>'rows_approved')::int = 2 and (r #>> '{figures,approved}')::int = 2, 'Overview & editions shows the same rows, rows approved and figures');
  r := security.destination_edition_publish_v1(v_ed, null);
  perform pg_temp.ok(r->>'status' = 'published' and (r->>'rows')::int = 2 and (select status from destination.editions where id = v_ed) = 'published', 'with approved localities the edition publishes');
  -- a figures-only edition (climate averages on localities another edition wrote) counts and publishes on its figures
  declare v_cl uuid; begin
    insert into destination.editions(country_id, domain, edition_label, effective_from, status, source_url, source_owner, attribution_text, terms_status)
    values (v_au, 'city_profiles', 'Climate 1', current_date, 'draft', 'https://www.bom.gov.au/', 'BOM', 'Source: BOM', 'approved') returning id into v_cl;
    insert into destination.locality_metrics(locality_id, metric_category, metric_key, numeric_value, unit, reference_period, dataset_edition, source_url, attribution_text, status)
    select l.id, 'climate', 'climate_annual_rainfall_mm', 600, 'mm', '1991-2020', 'Climate 1', 'https://www.bom.gov.au/', 'Source: BOM', 'draft' from destination.localities l where l.dataset_edition = 'Edition B';
    r := security.destination_edition_rows_v1(v_cl);
    perform pg_temp.ok((r->>'rows')::int = 3 and (r->>'rows_approved')::int = 0, 'a figures-only edition counts its 3 figures as rows, none approved yet');
    update destination.locality_metrics set status = 'approved' where dataset_edition = 'Climate 1';
    r := security.destination_edition_rows_v1(v_cl);
    perform pg_temp.ok((r->>'rows_approved')::int = 2, 'an approved figure counts only on an approved locality (2 of 3)');
    perform pg_temp.ok(security.destination_edition_publish_v1(v_cl, null)->>'status' = 'published', 'the figures-only edition publishes');
  end;
  -- other domains keep their check
  insert into destination.editions(country_id, domain, edition_label, effective_from, status, source_url, source_owner, attribution_text, terms_status)
  values (v_au, 'study_rules', 'Rules 1', current_date, 'draft', 'https://immi.homeaffairs.gov.au/', 'Home Affairs', 'Source: Home Affairs', 'approved') returning id into v_sr;
  m := pg_temp.err(format('select security.destination_edition_publish_v1(%L, null)', v_sr));
  perform pg_temp.ok(m = 'INVALID_INPUT: an edition with no rows cannot be published', 'an empty study rules edition is refused as before');
end $t$;
SQL
echo "api-v3-course-fields: all checks passed"
