#!/usr/bin/env bash
# Guards: F-AER.03 (country and qualification variants) AER qualification-first storage (Platform Admin 11 Nov 2026 decisions, items 2 and 3) and G4 database-backed tests: migration 20261112060000 edits
# public.svc_entry_matrix_record and security.entry_matrix_review_apply_v1 only from their live bodies (Database function snapshot run 42977913332: 3e76d77b..., 6d7b47fe...),
# leaves the recorded after md5s, is refused on a changed body, is idempotent; a read's qualification rows are recorded beside the matrix on the same Layer 4 item and follow
# the person's decision (approve, approve except, reject); the lookup returns an IB requirement for an applicant from any country; the forward recovery restores both bodies.
# Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Drops its databases at the end (AQF_KEEP=1 keeps them).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${AQF_DB:-g_aer_qualification_first}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
F=tests/fixtures/aer-qualification-first
M=supabase/migrations/20261112060000_cf247_aer_qualification_first.sql
R=supabase/held/aer_qualification_first_forward_recovery.sql
RE='public.svc_entry_matrix_record(uuid,jsonb,numeric,text)'; AP='security.entry_matrix_review_apply_v1(uuid,text,jsonb,text,uuid)'
RE_B=3e76d77b83bc8c1f9514b40f7cb4ac3e; AP_B=6d7b47fe7d2cd40b9cfb8f3547bad158; RE_A=7eee2ef2229520266fd56c8aa8f1f1fb; AP_A=c46ef6d3f9820c3d4d822846909e35ce
q() { psql -X -d "$DB" -Atc "$1"; }
md5s() { echo "$(q "select md5(prosrc) from pg_proc where oid = '$RE'::regprocedure") $(q "select md5(prosrc) from pg_proc where oid = '$AP'::regprocedure")"; }
trap '[ -n "${AQF_KEEP:-}" ] || { dropdb --if-exists '$DB' >/dev/null 2>&1; dropdb --if-exists '${DB}_refuse' >/dev/null 2>&1; }' EXIT
dropdb --if-exists $DB >/dev/null 2>&1; createdb $DB
psql -X -q -d postgres -c "do \$\$ begin if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if; if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if; if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role; end if; end \$\$"
$P -f $F/stubs.sql
for f in public.svc_entry_matrix_record security.entry_matrix_review_apply_v1; do { echo "set check_function_bodies = off;"; cat $F/live/$f.sql; echo ";"; } | $P; done
[ "$(md5s)" = "$RE_B $AP_B" ] || { echo "the loaded bodies differ from live ($RE_B $AP_B)"; exit 1; }
echo "loaded: svc_entry_matrix_record and entry_matrix_review_apply_v1 as live ($RE_B, $AP_B)"

RF=${DB}_refuse; dropdb --if-exists $RF >/dev/null 2>&1; createdb -T $DB $RF
psql -X -q -d $RF -v ON_ERROR_STOP=1 -c "set check_function_bodies = off; do \$\$ begin execute replace(pg_get_functiondef('$AP'::regprocedure), 'v_gate jsonb;', 'v_gate jsonb; v_x int;'); end \$\$" >/dev/null
OUT=$(psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $M 2>&1) && { echo "applied over a changed body"; exit 1; }
grep -qF "differs from the definition this change edits" <<<"$OUT" || { echo "unexpected refusal: $OUT" | tail -3; exit 1; }
[ "$(psql -X -d $RF -Atc "select count(*) from pg_tables where tablename = 'aer_qualifications'")" = 0 ] || { echo "the refused migration left a table"; exit 1; }
echo "refused: a hand-changed live body is refused and nothing is applied"; dropdb --if-exists $RF >/dev/null 2>&1

OUT=$({ echo "set check_function_bodies = off;"; cat $M; } | $P -1 -At 2>&1) || { echo "$OUT" | tail -8; exit 1; }
[ "$(md5s)" = "$RE_A $AP_A" ] || { echo "after md5s differ: $(md5s)"; exit 1; }
for want in "$RE $RE_B -> $RE_A" "$AP $AP_B -> $AP_A"; do grep -qF -- "--   $want" $M || { echo "header does not record: $want"; exit 1; }; done
OUT=$({ echo "set check_function_bodies = off;"; cat $M; } | $P -1 -At 2>&1) || { echo "$OUT" | tail -8; exit 1; }
[ "$(md5s)" = "$RE_A $AP_A" ] || { echo "applied again: changed"; exit 1; }
[ "$(q "select value from pipeline.platform_toolset_settings where key = 'reading.entry_country_aliases_on'")" = 1 ] || { echo "aliases not switched on"; exit 1; }
echo "migration: both bodies go to the recorded after md5s; qualifications seeded; aliases on; applied again: no change"

$P <<'SQL'
create or replace function pg_temp.ok(c boolean, m text) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', m; end if; raise notice 'ok: %', m; end $$;
insert into catalogue.providers(id, canonical_name) values ('a0000000-0000-0000-0000-00000000000a', 'Uni A');
insert into pipeline.entry_matrix_sources(id, provider_id, url, status) values ('5a000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-00000000000a', 'https://a.edu.au/entry', 'read');
insert into pipeline.entry_matrix_runs(id, source_id, provider_id) values ('7a000000-0000-0000-0000-000000000001', '5a000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-00000000000a');
do $$ declare r jsonb; item uuid; d jsonb; begin
  r := public.svc_entry_matrix_record('7a000000-0000-0000-0000-000000000001', jsonb_build_object('worker', 'coverage-sweep-worker-v0.70.0', 'dropped', '[]'::jsonb,
         'rows', jsonb_build_array(jsonb_build_object('country_code', 'IN', 'country_name', 'India', 'qualification_name', 'CBSE Year 12', 'min_value', 75, 'grade_scale', 'percentage', 'confidence', 0.95, 'quote', 'India | CBSE Year 12 | 75%')),
         'qualification_rows', jsonb_build_array(
           jsonb_build_object('qualification_code', 'IB_DP', 'qualification_name', 'International Baccalaureate (IB) Diploma', 'country_token', 'ALL', 'applicability', 'global', 'applicability_basis', 'country heading ALL',
                              'min_value', 28, 'grade_scale', 'points', 'confidence', 0.95, 'quote', 'All countries | International Baccalaureate (IB) Diploma | 28 points'),
           jsonb_build_object('qualification_code', 'GAC', 'qualification_name', 'Global Assessment Certificate', 'applicability', 'unresolved', 'min_value', 65, 'grade_scale', 'percentage', 'confidence', 0.9, 'quote', 'GAC 65%'),
           jsonb_build_object('qualification_code', 'MADE_UP', 'qualification_name', 'Something', 'confidence', 0.99, 'quote', 'Something 1'),
           jsonb_build_object('qualification_code', 'EB', 'qualification_name', 'European Baccalaureate', 'confidence', 0.5, 'quote', 'EB 70'))), 0.01, null);
  perform pg_temp.ok((r->>'qualification_rows')::int = 2 and (r->>'rows')::int = 1 and r->>'status' = 'layer4', 'a read with one country row and two recognised qualification rows goes to Layer 4');
  perform pg_temp.ok((select count(*) from catalogue.provider_qualification_requirements where status = 'proposed') = 2, 'the two recognised qualification rows are proposed beside the matrix');
  d := (select result->'dropped' from pipeline.entry_matrix_runs where id = '7a000000-0000-0000-0000-000000000001');
  perform pg_temp.ok(d @> '[{"reason":"unknown_qualification"}]' and d @> '[{"reason":"low_confidence","qualification":"EB"}]', 'an unknown code is dropped unknown_qualification; a low-confidence one low_confidence');
  item := (r->>'review_item_id')::uuid;
  perform pg_temp.ok((select (proposed_value->>'qualification_rows')::int from pipeline.layer4_review_items where id = item) = 2
    and (select jsonb_array_length(proposed_value->'qualification_sample') from pipeline.layer4_review_items where id = item) = 2, 'the Layer 4 item shows the qualification rows with a sample');
  perform pg_temp.ok((select applicability from catalogue.provider_qualification_requirements where qualification_code = 'IB_DP') = 'global'
    and (select applicability from catalogue.provider_qualification_requirements where qualification_code = 'GAC') = 'unresolved', 'applicability recorded as the reader proved it');
  -- approve except GAC
  perform security.entry_matrix_review_apply_v1(item, 'approve', jsonb_build_object('exclude_row_ids', jsonb_build_array((select id from catalogue.provider_qualification_requirements where qualification_code = 'GAC')::text), 'reviewer', 'fixture'), 'fixture approve except', null);
  perform pg_temp.ok((select status from catalogue.provider_qualification_requirements where qualification_code = 'IB_DP') = 'active'
    and (select status from catalogue.provider_qualification_requirements where qualification_code = 'GAC') = 'inactive'
    and (select status from catalogue.provider_entry_matrix where country_code = 'IN') = 'active', 'approve except: IB active, the excluded GAC inactive, the country row active');
  -- the lookup: a student educated in Nepal with IB sees the global IB requirement
  perform pg_temp.ok((select (public.admin_aer_qualification_lookup('{"qualification":"ib diploma","country":"NP"}')->'requirements'->0->>'applies_to_country')::boolean), 'an IB holder educated in Nepal retrieves the global IB requirement (no Nepal row needed)');
  perform pg_temp.ok((select jsonb_array_length(public.admin_aer_qualification_lookup('{}')->'qualifications')) >= 30, 'the qualification list is returned');
end $$;
-- a second read of the same source replaces the active IB row on approval; a third read is rejected and its qualification row quarantined
insert into pipeline.entry_matrix_runs(id, source_id, provider_id) values ('7a000000-0000-0000-0000-000000000002', '5a000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-00000000000a'),
                                                                     ('7a000000-0000-0000-0000-000000000003', '5a000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-00000000000a');
do $$ declare r jsonb; begin
  r := public.svc_entry_matrix_record('7a000000-0000-0000-0000-000000000002', jsonb_build_object('dropped', '[]'::jsonb, 'rows', '[]'::jsonb,
         'qualification_rows', jsonb_build_array(jsonb_build_object('qualification_code', 'IB_DP', 'qualification_name', 'IB Diploma', 'applicability', 'global', 'min_value', 30, 'grade_scale', 'points', 'confidence', 0.95, 'quote', 'All countries | IB Diploma | 30 points'))), 0.01, null);
  perform pg_temp.ok(r->>'status' = 'layer4' and (r->>'rows')::int = 0, 'a read with only qualification rows still goes to Layer 4');
  perform security.entry_matrix_review_apply_v1((r->>'review_item_id')::uuid, 'approve', '{}'::jsonb, 'fixture', null);
  perform pg_temp.ok((select count(*) from catalogue.provider_qualification_requirements where qualification_code = 'IB_DP' and status = 'active') = 1
    and (select min_value from catalogue.provider_qualification_requirements where qualification_code = 'IB_DP' and status = 'active') = 30
    and (select count(*) from catalogue.provider_qualification_requirements where qualification_code = 'IB_DP' and status = 'superseded') = 1, 'approval replaces the earlier active IB row of the same source');
  r := public.svc_entry_matrix_record('7a000000-0000-0000-0000-000000000003', jsonb_build_object('dropped', '[]'::jsonb, 'rows', '[]'::jsonb,
         'qualification_rows', jsonb_build_array(jsonb_build_object('qualification_code', 'GCE_A', 'qualification_name', 'A Levels', 'applicability', 'unresolved', 'min_grade', 'BBB', 'confidence', 0.95, 'quote', 'A Levels BBB'))), 0.01, null);
  perform security.entry_matrix_review_apply_v1((r->>'review_item_id')::uuid, 'reject', '{}'::jsonb, 'fixture reject', null);
  perform pg_temp.ok((select status from catalogue.provider_qualification_requirements where qualification_code = 'GCE_A') = 'inactive', 'reject quarantines the qualification row');
  -- switch off: rows are no longer recorded
  update pipeline.platform_toolset_settings set value = '0' where key = 'reading.entry_qualification_first_on';
  insert into pipeline.entry_matrix_runs(id, source_id, provider_id) values ('7a000000-0000-0000-0000-000000000004', '5a000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-00000000000a');
  r := public.svc_entry_matrix_record('7a000000-0000-0000-0000-000000000004', jsonb_build_object('dropped', '[]'::jsonb, 'rows', '[]'::jsonb,
         'qualification_rows', jsonb_build_array(jsonb_build_object('qualification_code', 'IB_DP', 'qualification_name', 'IB', 'min_value', 31, 'grade_scale', 'points', 'confidence', 0.95, 'quote', 'IB 31'))), 0.01, null);
  perform pg_temp.ok(r->>'status' = 'no_rows' and (select count(*) from catalogue.provider_qualification_requirements where run_id = '7a000000-0000-0000-0000-000000000004') = 0, 'with the switch off nothing is recorded (as before)');
end $$;
SQL
echo "behaviour: recorded beside the matrix on the same item, approve / approve except / replace / reject, lookup for any education country, switch off"

OUT=$({ echo "set check_function_bodies = off;"; cat $R; } | $P -1 -At 2>&1) || { echo "$OUT" | tail -8; exit 1; }
[ "$(md5s)" = "$RE_B $AP_B" ] || { echo "recovery did not restore the live md5s"; exit 1; }
echo "recovery: bodies back to $RE_B and $AP_B, qualification-first off, nothing dropped"
echo "PASS aer-qualification-first"
