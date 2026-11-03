#!/usr/bin/env bash
# CF-247 v2.15.447 defect (rule executor writes into a live-only table of another shape), on isolated fixtures. Needs a scratch PostgreSQL.
# Builds the Layer 4 course link fixture database (its live definitions are checked against live md5s there), then reshapes
# pipeline.layer4_rule_runs to the live-only table found in production (id, rule, at, raised; one earlier row), as it was before 20261104260000.
# R1 the executor fails as it did live; R2 the migration applies (after-md5 checked by the migration) and a second run changes nothing;
# R3 a counting run succeeds and writes only to the executor's own tables; R4 the old table keeps its rows and shape.
set -euo pipefail
cd "$(dirname "$0")"
DB=l4_rule_runs_table_fixtures
MIG=../../../supabase/migrations/20261104280000_cf247_l4_rule_runs_table.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
q() { $P -d $DB -Atc "$1"; }
L4CL_KEEP=1 L4CL_DB=$DB bash ../l4-course-link/run.sh >/dev/null
trap '$P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT
# the live-only table as found in production (the 20261104260000 "create table if not exists" kept it)
q "drop table pipeline.layer4_rule_run_items; drop table pipeline.layer4_rule_runs cascade"
q "create table pipeline.layer4_rule_runs (id bigserial primary key, rule text, at timestamptz default now(), raised jsonb)"
q "create table pipeline.layer4_rule_run_items (run_id bigint not null references pipeline.layer4_rule_runs(id), item_id uuid not null, course_id uuid, outcome text not null, reasons text[] not null default '{}', decision_id uuid, action text, at timestamptz not null default now(), primary key (run_id, item_id))"
q "alter table pipeline.component_register add column if not exists updated_at timestamptz, add column if not exists replaced_by text, add column if not exists retire_after date"  # live columns (the shared stub cuts them)
q "insert into pipeline.layer4_rule_runs(rule, raised) values ('rule6', '{\"n\": 3}')"
ADMIN="select set_config('fx.uid', '90000000-0000-0000-0000-0000000000aa', false), set_config('fx.rank', '6', false);"
if $P -d $DB -Atc "$ADMIN select security.layer4_course_link_rule_execute_v1('canberra_no_year', 50, false)" >/dev/null 2>&1; then echo "R1: the executor did not fail"; exit 1; fi
echo "R1 ok: the executor fails on the live-only table, as in production"
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -3; exit 1; }
echo "$OUT" | grep -q ': applied$' || { echo "$OUT" | tail -3; exit 1; }
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -3; exit 1; }
echo "$OUT" | grep -q ': already applied$' || { echo "second run: $OUT" | tail -3; exit 1; }
echo "R2 ok: the migration applies; a second run changes nothing"
D0=$(q "select count(*) from pipeline.layer4_decisions")
R=$($P -d $DB -Atc "$ADMIN select security.layer4_course_link_rule_execute_v1('canberra_no_year', 50, false)" | tail -1)
[ "$(q "select count(*) from pipeline.layer4_course_link_rule_runs")" = 1 ] || { echo "R3: no run recorded ($R)"; exit 1; }
[ "$(q "select count(*) from pipeline.layer4_course_link_rule_run_items")" -gt 0 ] || { echo "R3: no items recorded ($R)"; exit 1; }
[ "$(q "select count(*) from pipeline.layer4_decisions")" = "$D0" ] || { echo "R3: a count decided"; exit 1; }
echo "R3 ok: a counting run succeeds and records in the executor's own tables ($R)"
[ "$(q "select count(*) from pipeline.layer4_rule_runs")" = 1 ] || { echo "R4: old table rows changed"; exit 1; }
[ "$(q "select string_agg(column_name, ',' order by ordinal_position) from information_schema.columns where table_schema = 'pipeline' and table_name = 'layer4_rule_runs'")" = "id,rule,at,raised" ] || { echo "R4: old table shape changed"; exit 1; }
[ "$(q "select status from pipeline.component_register where kind = 'table' and name = 'pipeline.layer4_rule_run_items'")" = retiring ] || { echo "R4: run_items not retiring"; exit 1; }
echo "R4 ok: the old table keeps its rows and shape; the empty run_items table is marked retiring"
echo "all rule runs table fixtures passed"
