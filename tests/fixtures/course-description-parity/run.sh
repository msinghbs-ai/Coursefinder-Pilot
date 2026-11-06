#!/usr/bin/env bash
# Guards: Platform Admin direction 6 Nov 2026 08:12 (course descriptions: safe parallel planning and independent validation); decision 19:14 §8
# (production-representative validation). Builds the course-description path from the production-parity manifest (captured read-only
# 6 Nov 2026 08:29 AEDT with scripts/prod-parity-capture.mjs: catalogue.courses, pipeline.field_enrich_items, pipeline.layer4_review_items,
# pipeline.platform_toolset_settings with their constraints, triggers, grants and RLS, and the live course_description_check_v1 and related
# functions, each md5-checked), proves the fixture equals the manifest, seeds the live settings, and runs the validator baseline
# (synthetic shapes, then real held readings from production with the rule production recorded).
# Needs a scratch PostgreSQL (never a Supabase project): PGHOST/PGPORT/PGUSER. Databases use the prefix g_.
set -euo pipefail
cd "$(dirname "$0")"
ROOT=../../..
DB=${CDESC_DB:-g_cdesc_baseline}
P="psql -v ON_ERROR_STOP=1 -q -X"
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
[ -n "${CDESC_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null' EXIT
# Supabase keeps gen_random_uuid in schema "extensions" (a column default of pipeline.evidence_artifacts calls it); PostgreSQL 16 has it in core
EXT="create schema if not exists extensions; create or replace function extensions.gen_random_uuid() returns uuid language sql as 'select pg_catalog.gen_random_uuid()'"
$P -d $DB -c "$EXT" >/dev/null
node $ROOT/scripts/prod-parity-capture.mjs fixture manifest-register.json | $P -d $DB >/dev/null 2>&1
node $ROOT/scripts/prod-parity-capture.mjs fixture manifest.json | $P -d $DB 2>&1 | grep -v -e 'does not exist, skipping' -e '^$' || true
# Parity: only the PostgreSQL 17 MAINTAIN privilege may differ on a PostgreSQL 16 server (tests/fixtures/prod-parity/README.md, Limits).
DIFF=$(node $ROOT/scripts/prod-parity-capture.mjs check-sql manifest.json | $P -d $DB -At | grep -v '^grant|.*MAINTAIN' || true)
[ -z "$DIFF" ] || { echo "fixture differs from the production manifest:"; echo "$DIFF"; exit 1; }
# The live definitions the plan guards on (6 Nov 2026 08:25-08:29 AEDT)
declare -A LIVE=(
  ["security.course_description_check_v1(uuid,jsonb)"]=ff3d6dd7b0f88c85b1fdff6c8a8cd86b
  ["security.enrich_course_text_record_v1(bigint,jsonb)"]=b47c00b19bc6eaa36828dbe4d2371501
  ["security.course_description_trusted_v1(uuid)"]=3f056fa4495963ec1d3bca61bfe0642d
  ["security.layer4_course_description_apply_v1(uuid,uuid,jsonb,text)"]=ba97236f3010e248bac44a0a7c09611a
  ["security.course_description_release_held_v1(uuid)"]=dd4b178afcd26b696d70710038e34f1c
  ["security.course_description_review_trg_v1()"]=d143eba24f5896f36a3a93e8e5c075aa
)
for s in "${!LIVE[@]}"; do
  got=$($P -d $DB -Atc "select md5(pg_get_functiondef('$s'::regprocedure))")
  [ "$got" = "${LIVE[$s]}" ] || { echo "loaded $s is $got, not live ${LIVE[$s]}"; exit 1; }
done
echo "parity: fixture equals the production manifest; ${#LIVE[@]} live md5s confirmed"
$P -d $DB -f settings.sql
for f in baseline.sql held-real.sql; do
  [ -f "$f" ] || { echo "missing $f"; exit 1; }
  $P -d $DB -1 -f "$f" 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'
done
echo "course-description baseline (before the migration): all passed"
# After the migration: a second database gets the same live settings, then migration 20261106500000 (twice: it must be re-run safe), then the SAME
# baseline cases and real held readings must give identical outcomes, then the queue/reconciliation/sample tests.
DB2=${CDESC_DB2:-g_cdesc_after}
$P -d postgres -c "drop database if exists $DB2" -c "create database $DB2" >/dev/null
[ -n "${CDESC_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" -c "drop database if exists $DB2" >/dev/null' EXIT
$P -d $DB2 -c "$EXT" >/dev/null
node $ROOT/scripts/prod-parity-capture.mjs fixture manifest-register.json | $P -d $DB2 >/dev/null 2>&1
node $ROOT/scripts/prod-parity-capture.mjs fixture manifest.json | $P -d $DB2 >/dev/null 2>&1 || true
$P -d $DB2 -f settings.sql
MIG=$ROOT/supabase/migrations/20261106500000_cf247_course_descriptions_complete.sql
$P -d $DB2 -1 -f $MIG 2>&1 | sed -n 's/^.*\(WARNING\|ERROR\):  /\1 /p'
$P -d $DB2 -1 -f $MIG 2>&1 | sed -n 's/^.*\(WARNING\|ERROR\):  /\1 /p'
echo "migration 20261106500000 applied twice without error"
for f in baseline.sql held-real.sql; do
  $P -d $DB2 -1 -v after=1 -f "$f" 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'
done
echo "course-description baseline (after the migration): identical outcomes"
$P -d $DB2 -f queue.sql 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\|WARNING\):  /\1 /p'
echo "course-description queue, reconciliation and sample tests: all passed"
