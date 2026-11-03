#!/usr/bin/env bash
# CF-247 Layer 4 rule executor bounded (migration 20261104310000) on isolated fixtures. Needs a scratch PostgreSQL (never a Supabase project):
# PGHOST/PGPORT/PGUSER point at it. Builds the Layer 4 course-link fixture database as it reached production (../l4-course-link/run.sh, kept),
# applies 20261104280000 (the executor's own run tables, v2.15.448), checks the two edited definitions against the live md5s read 4 Nov 2026
# 00:29 AEDT, applies this migration twice (the second run changes nothing), then seed.sql and fixtures.sql. Drops the database at the end.
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=l4_rule_sfu_perf_fixtures
P="psql -v ON_ERROR_STOP=1 -q -X"
MIG=supabase/migrations/20261104310000_cf247_l4_rule_sfu_perf.sql
FX=tests/fixtures/l4-rule-sfu-perf
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
q() { $P -d $DB -Atc "$1"; }
md5of() { q "select md5(pg_get_functiondef('$1'::regprocedure))"; }
trap '$P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT
L4CL_KEEP=1 L4CL_DB=$DB bash tests/fixtures/l4-course-link/run.sh >/dev/null || { echo "the Layer 4 course-link fixture failed"; exit 1; }
# stub gaps (live has them): the register's retirement columns, the level reading's inputs
$P -d $DB -c "alter table pipeline.component_register add column if not exists updated_at timestamptz, add column if not exists replaced_by text, add column if not exists retire_after date" >/dev/null
PGOPTIONS='-c check_function_bodies=off' $P -d $DB -1 -o /dev/null -f supabase/migrations/20261104280000_cf247_l4_rule_runs_table.sql
$P -d $DB -c "create schema if not exists ref; create table if not exists ref.study_levels(id uuid primary key, code text);
  alter table catalogue.courses add column if not exists study_level_id uuid; alter table pipeline.coverage_course_pages add column if not exists candidates jsonb not null default '{}'::jsonb" >/dev/null
declare -A LIVE=(
  ["security.layer4_course_link_rule_validate_v1(text,uuid)"]=31bd052cb7161008ef9452bd24eb0e75
  ["security.layer4_course_link_rule_execute_v1(text,integer,boolean)"]=86e1089a5e93e1e2cce9a0ffd29aa22b
)
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "before (loaded = live): ${#LIVE[@]} definitions"
OUT=$(PGOPTIONS='-c check_function_bodies=off' $P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(grep -c ': applied' <<<"$OUT")" = 2 ] || { echo "the migration did not apply both guarded edits"; echo "$OUT"; exit 1; }
for s in "${!LIVE[@]}"; do echo "after: $s ${LIVE[$s]} -> $(md5of "$s")"; done
echo "new: security.layer4_rule_level_v1(uuid,text) $(md5of 'security.layer4_rule_level_v1(uuid,text)')"
OUT=$(PGOPTIONS='-c check_function_bodies=off' $P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(grep -c 'already applied' <<<"$OUT")" = 2 ] || { echo "a second run changed a guarded function"; exit 1; }
echo "applied twice: the second run changed nothing"
$P -d $DB -f $FX/seed.sql
$P -d $DB -f $FX/fixtures.sql 2>&1 | show
echo "all rule executor bounded fixtures passed"
