#!/usr/bin/env bash
# IQ-00116 tuition publication on isolated fixtures (CF-247, Platform Admin mandate 4 Nov 2026 05:08 §7). Needs a scratch PostgreSQL (never a
# Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database:
#   1 the E16 fixture database (its stubs, its rebuilt definitions and the E16 migration), so the search projection builder
#     (search.refresh_course_enrichment_core_v1 / _core_scoped_v1) is the live definition; md5s checked against live;
#   2 this fixture's stubs, then the live definitions read on 4 Nov 2026 (live-before/, and security.layer4_admission_check_v1 from its
#     migration), md5s checked against live;
#   3 fixtures-before.sql: the live mismatch reproduced through the live (unfixed) apply path;
#   4 the migration unchanged (its md5 guards run), then again (nothing changes);
#   5 fixtures.sql: the cases.
# Drops the throwaway database at the end.
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${TP_DB:-tuition_publication_fixtures}
P="psql -v ON_ERROR_STOP=1 -q -X"
FX=tests/fixtures/tuition-publication
E16=tests/fixtures/e16-binding-validation
E16MIG=supabase/migrations/20261102030000_cf247_e16_binding_validation.sql
L4MIG=supabase/migrations/20261104120000_cf247_ops_layer4_throughput.sql
MIG=supabase/migrations/20261104380000_cf247_tuition_publication.sql
TMP=$(mktemp -d)
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
if [ -n "${TP_KEEP:-}" ]; then trap 'rm -rf "$TMP"' EXIT; else trap 'rm -rf "$TMP"; $P -d postgres -c "drop database if exists $DB" >/dev/null' EXIT; fi
md5of() { $P -d $DB -Atc "select string_agg(md5(pg_get_functiondef(f::regprocedure)), ' ' order by o) from unnest($1) with ordinality t(f, o)"; }
# 1 the E16 fixture database: the live projection builder
node $E16/before.mjs > "$TMP/e16.sql"
$P -d $DB -c "create schema security; create schema search; create schema pipeline; create schema catalogue"
PGOPTIONS='-c check_function_bodies=off' $P -d $DB -o /dev/null -f "$TMP/e16.sql"
$P -d $DB -f $E16/stubs.sql
$P -d $DB -1 -o /dev/null -f $E16MIG
PROJ="array['search.refresh_course_enrichment_core_v1(boolean)', 'search.refresh_course_enrichment_core_scoped_v1(uuid[],boolean)']"
[ "$(md5of "$PROJ")" = "04fa25d82c373de08767d5573d4caabc 5b45bbf1e39d9098d5f23de729418b2d" ] || { echo "projection differs from live: $(md5of "$PROJ")"; exit 1; }
echo "projection builder (rebuilt = live): $(md5of "$PROJ")"
# 2 stubs and the live definitions this change edits or calls
$P -d $DB -c "drop function search.refresh_course_enrichment_scoped_v1(uuid[], boolean)"
$P -d $DB -f $FX/stubs.sql
for f in $FX/live-before/*.sql; do PGOPTIONS='-c check_function_bodies=off' $P -d $DB -o /dev/null -f "$f"; done
awk '/^create or replace function security.layer4_admission_check_v1\(/{p=1} p{print} p&&/^end \$function\$;/{exit}' $L4MIG > "$TMP/check.sql"
PGOPTIONS='-c check_function_bodies=off' $P -d $DB -o /dev/null -f "$TMP/check.sql"
SIGS="array['security.layer4_tuition_apply_impl(uuid,uuid,jsonb,text)', 'search.refresh_course_enrichment_scoped_v1(uuid[],boolean)', 'security.course_fee_used_v1(uuid)', 'security.layer4_admission_record_v1(uuid)', 'security.layer4_admission_check_v1(uuid)']"
BEFORE=$(md5of "$SIGS")
[ "$BEFORE" = "ef89bdd9ad75a12ecd42ff83e5abc9cb fb55e935a8d1c6c7b8cd1c476362cc60 e3cd801549ebf1883bb988fa24a3c909 b47d337ce40e075fe47d751ba564df64 a03e1c3d26237f33b3e38dd81377b744" ] || { echo "rebuilt definitions differ from live: $BEFORE"; exit 1; }
echo "before (rebuilt = live): $BEFORE"
# 3 the live mismatch, through the live apply path
$P -d $DB -f $FX/fixtures-before.sql 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'
# 4 the migration, twice
$P -d $DB -1 -o /dev/null -f $MIG
AFTER=$(md5of "$SIGS"); echo "after: $AFTER"
$P -d $DB -1 -At -f $MIG | grep -c 'already applied' | grep -qx 1 || { echo "a second run changed something"; exit 1; }
[ "$(md5of "$SIGS")" = "$AFTER" ] || { echo "a second run changed a definition"; exit 1; }
[ "$($P -d $DB -Atc "select count(*) from pipeline.platform_toolset_settings where key = 'layer4.tuition_publication_batch'")" = 1 ] || { echo "the setting was added twice"; exit 1; }
echo "second run: already applied, unchanged"
# 5 the cases
$P -d $DB -f $FX/fixtures.sql 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'
