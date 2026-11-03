#!/usr/bin/env bash
# CF-247 IQ-00189 rule target as a full https:// address (migration 20261104350000) on isolated fixtures. Needs a scratch PostgreSQL (never a
# Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds the Layer 4 course-link fixture database (../l4-course-link/run.sh, kept), applies
# 20261104280000 and 20261104330000 (v2.15.448 and v2.15.451) with their stub gaps and seed, checks the two edited definitions against the live
# md5s read 4 Nov 2026 01:48 AEDT, applies this migration twice (the second run changes nothing), then seed.sql and fixtures.sql.
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=l4_rule_target_scheme_fixtures
P="psql -v ON_ERROR_STOP=1 -q -X"
MIG=supabase/migrations/20261104350000_cf247_l4_rule_target_scheme.sql
FX=tests/fixtures/l4-rule-target-scheme
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
q() { $P -d $DB -Atc "$1"; }
md5of() { q "select md5(pg_get_functiondef('$1'::regprocedure))"; }
trap '$P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT
L4CL_KEEP=1 L4CL_DB=$DB bash tests/fixtures/l4-course-link/run.sh >/dev/null || { echo "the Layer 4 course-link fixture failed"; exit 1; }
# stub gaps (live has them), as ../l4-rule-sfu-perf/run.sh
$P -d $DB -c "alter table pipeline.component_register add column if not exists updated_at timestamptz, add column if not exists replaced_by text, add column if not exists retire_after date" >/dev/null
PGOPTIONS='-c check_function_bodies=off' $P -d $DB -1 -o /dev/null -f supabase/migrations/20261104280000_cf247_l4_rule_runs_table.sql
$P -d $DB -c "create schema if not exists ref; create table if not exists ref.study_levels(id uuid primary key, code text);
  alter table catalogue.courses add column if not exists study_level_id uuid; alter table pipeline.coverage_course_pages add column if not exists candidates jsonb not null default '{}'::jsonb" >/dev/null 2>&1
PGOPTIONS='-c check_function_bodies=off' $P -d $DB -1 -o /dev/null -f supabase/migrations/20261104330000_cf247_l4_rule_sfu_perf.sql
$P -d $DB -f tests/fixtures/l4-rule-sfu-perf/seed.sql
declare -A LIVE=(
  ["security.layer4_course_link_rule_validate_v1(text,uuid)"]=3a5d088e4aaf3ad1e1a5460524a2e70a
  ["security.layer4_course_link_rule_execute_v1(text,integer,boolean)"]=85c991e7b626e07f9777f7a65249fd81
  ["security.layer4_course_link_apply_impl(uuid,uuid,jsonb,text)"]=75a53dbbcd5e20e1018a05b61f6763aa
  ["security.layer4_review_decide_impl(uuid,text,text,jsonb)"]=55353f1903c97b268255c8c1e4f5ca6f
)
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "before (loaded = live): ${#LIVE[@]} definitions"
OUT=$(PGOPTIONS='-c check_function_bodies=off' $P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(grep -c ': applied' <<<"$OUT")" = 2 ] || { echo "the migration did not apply both guarded edits"; echo "$OUT"; exit 1; }
for s in "security.layer4_course_link_rule_validate_v1(text,uuid)" "security.layer4_course_link_rule_execute_v1(text,integer,boolean)"; do echo "after: $s ${LIVE[$s]} -> $(md5of "$s")"; done
for s in "security.layer4_course_link_apply_impl(uuid,uuid,jsonb,text)" "security.layer4_review_decide_impl(uuid,text,text,jsonb)"; do
  [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "$s changed"; exit 1; }; done
OUT=$(PGOPTIONS='-c check_function_bodies=off' $P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(grep -c 'already applied' <<<"$OUT")" = 2 ] || { echo "a second run changed a guarded function"; exit 1; }
echo "applied twice: the second run changed nothing"
$P -d $DB -f $FX/seed.sql
$P -d $DB -f $FX/fixtures.sql 2>&1 | show
echo "all rule target scheme fixtures passed"
