#!/usr/bin/env bash
# Guards: REQ-68 publication guard and REQ-65/67 destination importer (Platform Admin 15 Nov 2026 23:04, combined build item 4) and G4 database-backed tests:
# migration 20261115230000 on top of 20261115190000 runs on an isolated PostgreSQL 16 (fixtures only, never a Supabase project). It proves: an import is
# idempotent and writes only changed rows; an import never approves terms; no edition is published without approved terms, by any route; published and
# superseded editions are fixed; one published edition per country and domain; row country and domain follow the edition; a city keeps a stable id.
# Needs a scratch PostgreSQL 16: PGHOST/PGPORT/PGUSER point at it. Drops its database at the end (DE_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${DE_DB:-g_destination_editions}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
F=tests/fixtures/destination-editions
S=supabase/migrations-archive/20261115190000_api_v3_additive_schema.sql; M=supabase/migrations-archive/20261115230000_cf247_destination_importer_guard.sql
trap '[ -n "${DE_KEEP:-}" ] || dropdb --if-exists '$DB' >/dev/null 2>&1' EXIT
dropdb --if-exists $DB >/dev/null 2>&1; createdb $DB
psql -X -q -d postgres -c "do \$\$ begin if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if; if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if; if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role; end if; end \$\$"
$P -f $F/stubs.sql
$P -1 -f $S >/dev/null
echo "loaded: stubs and $S"
$P -1 -f $M >/dev/null; $P -1 -f $M >/dev/null
echo "migration: applied twice without error (post-check included)"

$P <<'SQL'
create or replace function pg_temp.ok(c boolean, m text) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', m; end if; raise notice 'ok: %', m; end $$;
create or replace function pg_temp.err(q text) returns text language plpgsql as $$ begin execute q; return null; exception when others then return sqlerrm; end $$;
create or replace function pg_temp.payload(p_label text, p_fee numeric, p_terms text default null) returns jsonb language sql as $$
  select jsonb_build_object('edition', jsonb_build_object('country_code', 'au', 'domain', 'study_rules', 'edition_label', p_label, 'effective_from', case when p_label = '2027' then '2027-01-01' else '2026-07-01' end,
           'source_url', 'https://immi.homeaffairs.gov.au/visas/getting-a-visa/visa-listing/student-500', 'source_owner', 'Department of Home Affairs',
           'attribution_text', 'Source: Department of Home Affairs', 'terms_status', p_terms),
         'rows', jsonb_build_array(
           jsonb_build_object('visa_subclass', '500', 'visa_name', 'Student visa', 'application_fee_amount', p_fee, 'fee_currency', 'aud', 'work_hours_fortnight', 48),
           jsonb_build_object('visa_subclass', '485', 'visa_name', 'Temporary Graduate visa', 'application_fee_amount', 2300, 'fee_currency', 'AUD', 'post_study_work_years_min', 2, 'post_study_work_years_max', 4)))
$$;
do $t$ declare r jsonb; v_ed uuid; v_ed2 uuid; v_city jsonb; v_c1 uuid; v_c2 uuid; m text; begin
  r := security.destination_import_v1(pg_temp.payload('2026', 2000));
  perform pg_temp.ok(r->>'edition' = 'created' and r->>'status' = 'draft' and r->>'terms_status' = 'pending' and (r->>'inserted')::int = 2, 'a new edition is a draft with pending terms; both rows inserted');
  v_ed := (r->>'edition_id')::uuid;
  perform pg_temp.ok((select fee_currency from destination.study_rules where visa_subclass = '500') = 'AUD', 'currency is upper-cased');
  r := security.destination_import_v1(pg_temp.payload('2026', 2000));
  perform pg_temp.ok(r->>'edition' = 'unchanged' and (r->>'unchanged')::int = 2 and (r->>'inserted')::int = 0 and (r->>'updated')::int = 0, 'the same import again changes nothing');
  r := security.destination_import_v1(pg_temp.payload('2026', 2000.5));
  perform pg_temp.ok((r->>'updated')::int = 1 and (r->>'unchanged')::int = 1, 'a changed value updates only its row');
  perform pg_temp.ok((select count(*) from destination.editions) = 1, 'one edition per country, domain and label');
  m := pg_temp.err($$select security.destination_import_v1(pg_temp.payload('2026', 1, 'approved'))$$);
  perform pg_temp.ok(m like 'INVALID_INPUT: an import sets terms_status pending or restricted%', 'an import cannot approve terms');
  m := pg_temp.err(format($$update destination.editions set status = 'published' where id = %L$$, v_ed));
  perform pg_temp.ok(m like 'DESTINATION_TERMS_NOT_APPROVED%', 'REQ-68: a direct write cannot publish with pending terms');
  m := pg_temp.err(format($$insert into destination.editions(country_id, domain, edition_label, effective_from, status, source_url, source_owner, attribution_text, terms_status)
                            select id, 'city_profiles', 'x', current_date, 'published', 'u', 'o', 'a', 'restricted' from ref.countries where iso_alpha2 = 'NZ'$$));
  perform pg_temp.ok(m like 'DESTINATION_TERMS_NOT_APPROVED%', 'REQ-68: an insert cannot create a published edition without approved terms');
  m := pg_temp.err(format($$select security.destination_edition_publish_v1(%L)$$, v_ed));
  perform pg_temp.ok(m like 'DESTINATION_TERMS_NOT_APPROVED%', 'REQ-68: the publish function refuses pending terms');
  perform security.destination_edition_set_terms_v1(v_ed, 'approved', null);
  r := security.destination_edition_publish_v1(v_ed, null);
  perform pg_temp.ok(r->>'status' = 'published' and (r->>'rows')::int = 2 and r->'superseded' = 'null'::jsonb, 'approved terms and rows: published');
  m := pg_temp.err($$update destination.study_rules set visa_name = 'changed' where visa_subclass = '500'$$);
  perform pg_temp.ok(m like 'DESTINATION_EDITION_FIXED%', 'rows of a published edition are fixed');
  m := pg_temp.err($$delete from destination.study_rules where visa_subclass = '485'$$);
  perform pg_temp.ok(m like 'DESTINATION_EDITION_FIXED%', 'rows of a published edition cannot be deleted');
  m := pg_temp.err($$select security.destination_import_v1(pg_temp.payload('2026', 9))$$);
  perform pg_temp.ok(m like 'INVALID_INPUT: edition 2026 is published and fixed%', 'a published edition cannot be re-imported');
  r := security.destination_import_v1(pg_temp.payload('2027', 2100));
  v_ed2 := (r->>'edition_id')::uuid;
  perform security.destination_edition_set_terms_v1(v_ed2, 'approved', null);
  r := security.destination_edition_publish_v1(v_ed2, null);
  perform pg_temp.ok((r->>'superseded')::uuid = v_ed, 'publishing the next edition supersedes the previous one');
  perform pg_temp.ok((select status from destination.editions where id = v_ed) = 'superseded' and (select effective_to from destination.editions where id = v_ed) = '2026-12-31', 'the previous edition ends the day before');
  perform pg_temp.ok((select count(*) from destination.editions where status = 'published') = 1, 'one published edition per country and domain');
  m := pg_temp.err($$update destination.study_rules set visa_name = 'changed' where visa_subclass = '500' and edition_id in (select id from destination.editions where status = 'superseded')$$);
  perform pg_temp.ok(m like 'DESTINATION_EDITION_FIXED%', 'rows of a superseded edition are fixed');
  r := security.destination_edition_set_terms_v1(v_ed2, 'restricted', null);
  perform pg_temp.ok(r->>'status' = 'in_review' and r->>'terms_status' = 'restricted', 'restricting the terms of a published edition takes it off at once');
  m := pg_temp.err(format($$insert into destination.city_profiles(edition_id, city_id, country_id, city_name, cost_currency, source_url) select %L, gen_random_uuid(), id, 'X', 'AUD', 'u' from ref.countries where iso_alpha2 = 'AU'$$, v_ed2));
  perform pg_temp.ok(m like 'DESTINATION_DOMAIN_MISMATCH%', 'a city row cannot go into a study rules edition');
  m := pg_temp.err(format($$insert into destination.study_rules(edition_id, country_id, visa_subclass, visa_name, fee_currency, source_url) select %L, id, '600', 'v', 'NZD', 'u' from ref.countries where iso_alpha2 = 'NZ'$$, v_ed2));
  perform pg_temp.ok(m like 'DESTINATION_COUNTRY_MISMATCH%', 'a row''s country is its edition''s country');
  v_city := jsonb_build_object('edition', jsonb_build_object('country_code', 'NZ', 'domain', 'city_profiles', 'edition_label', '2026', 'effective_from', '2026-01-01', 'source_url', 'https://www.stats.govt.nz',
              'source_owner', 'Stats NZ', 'attribution_text', 'Source: Stats NZ'), 'rows', jsonb_build_array(jsonb_build_object('city_name', 'Auckland ', 'population', 1700000, 'cost_currency', 'nzd')));
  r := security.destination_import_v1(v_city);
  select city_id into v_c1 from destination.city_profiles where city_name = 'Auckland';
  r := security.destination_import_v1(jsonb_set(v_city, '{rows,0,city_name}', '"auckland"'));
  select city_id into v_c2 from destination.city_profiles where lower(city_name) = 'auckland';
  perform pg_temp.ok(v_c1 = v_c2 and (select count(*) from destination.city_profiles) = 1 and (r->>'updated')::int = 1, 'a city without city_id keeps one stable id by country and name');
  m := pg_temp.err(format($$select security.destination_edition_publish_v1(%L)$$, (select id from destination.editions where domain = 'city_profiles')));
  perform pg_temp.ok(m like 'DESTINATION_TERMS_NOT_APPROVED%', 'pending city edition cannot be published');
  r := security.destination_import_v1(jsonb_set(jsonb_set(v_city, '{edition,edition_label}', '"empty"'), '{rows}', '[]'));
  perform security.destination_edition_set_terms_v1((r->>'edition_id')::uuid, 'approved', null);
  m := pg_temp.err(format($$select security.destination_edition_publish_v1(%L)$$, r->>'edition_id'));
  perform pg_temp.ok(m like 'INVALID_INPUT: an edition with no rows%', 'an edition with no rows cannot be published');
  m := pg_temp.err($$select security.destination_import_v1('{"edition":{"country_code":"ZZ","domain":"study_rules","edition_label":"x","effective_from":"2026-01-01","source_url":"u","source_owner":"o","attribution_text":"a"}}')$$);
  perform pg_temp.ok(m like 'INVALID_INPUT: unknown country_code ZZ%', 'an unknown country is refused');
  m := pg_temp.err($$select security.destination_import_v1('{"edition":{"country_code":"AU","domain":"study_rules","edition_label":"bad","effective_from":"2026-01-01","source_url":"u","source_owner":"o","attribution_text":"a"},"rows":[{"visa_subclass":"500","visa_name":"v","fee_currency":"AUD","application_fee_amount":"lots"}]}')$$);
  perform pg_temp.ok(m like 'INVALID_INPUT: row 1:%', 'a bad value names its row');
  perform pg_temp.ok(not has_function_privilege('anon', 'security.destination_import_v1(jsonb)', 'execute') and not has_function_privilege('authenticated', 'security.destination_edition_publish_v1(uuid, uuid)', 'execute'), 'only the service role can import or publish');
end $t$;
SQL
echo "behaviour: all destination importer and guard checks passed"
