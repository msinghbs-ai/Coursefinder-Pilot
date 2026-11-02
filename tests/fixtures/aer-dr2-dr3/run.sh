#!/usr/bin/env bash
# D-R2 / D-R3 / E13 extension on isolated fixtures (CF-247, Platform Admin direction 2 Nov 2026 23:24). Needs a scratch PostgreSQL (never a
# Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database, rebuilds the live definitions this change edits from this
# repository's migrations (the E13 builder and E13 migration, then the matrix approval chain), checks every md5 against live (read 2 Nov 2026
# 23:46 AEDT), applies 20261103070000 unchanged (its own md5 guards run), applies it again (no change), then runs fixtures.sql.
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${DR_DB:-aer_dr2_dr3_fixtures}
MIG=supabase/migrations/20261103070000_cf247_aer_dr2_dr3_supersede_and_matrix_gate.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
trap '$P -d postgres -c "drop database if exists $DB" >/dev/null' EXIT
$P -d $DB -f tests/fixtures/e13-completeness-gate/stubs.sql
$P -d $DB -f tests/fixtures/aer-dr2-dr3/stubs.sql
node tests/fixtures/e13-completeness-gate/before.mjs | $P -d $DB -o /dev/null
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261102010000_cf247_e13_entry_completeness_gate.sql
node tests/fixtures/aer-dr2-dr3/before.mjs | $P -d $DB -o /dev/null
SIGS="'security.course_entry_gate_v1(uuid,uuid[])', 'security.entry_matrix_review_apply_v1(uuid,text,jsonb,text,uuid)', 'security.aer_review_read_v1(uuid)', 'security.enrich_entry_record_v1(bigint,jsonb)', 'security.course_entry_review_apply_v1(uuid,text,jsonb,text)', 'security.course_entry_review_trg_v1()'"
md5s() { $P -d $DB -Atc "select string_agg(md5(pg_get_functiondef(f::regprocedure)), ' ' order by o) from unnest(array[$SIGS]) with ordinality t(f, o)"; }
LIVE="c1e99d43c6081f9a98c0eb698d943f32 db3fde7584baf7e2960625d728603b99 50c31fc4df16b7bbbb39dab03aa9f9b2 9757abeeb3700c5cd2e02385def05869 4be9267d8419dee7d9f80cb96ff4098b 527980ffd84edffd9e8841a5c4202f72"
BEFORE=$(md5s); [ "$BEFORE" = "$LIVE" ] || { echo "rebuilt definitions differ from live: $BEFORE"; exit 1; }
echo "before (rebuilt = live): $BEFORE"
$P -d $DB -1 -o /dev/null -f $MIG
AFTER=$(md5s); echo "after: $AFTER"
$P -d $DB -1 -At -f $MIG | grep -c 'already applied' | grep -qx 4 || { echo "a second run changed something"; exit 1; }
[ "$(md5s)" = "$AFTER" ] || { echo "a second run changed a definition"; exit 1; }
echo "second run: already applied, unchanged"
$P -d $DB -f tests/fixtures/aer-dr2-dr3/fixtures.sql 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'
