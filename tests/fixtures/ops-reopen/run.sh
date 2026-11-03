#!/usr/bin/env bash
# CF-247 P0 workstream A follow-ups (Integration Controller 3 Nov 2026 18:20; migration 20261104100000) on isolated fixtures. Scratch PostgreSQL
# only (PGHOST/PGPORT/PGUSER). Builds a throwaway database: the integration queue (../integration-queue stubs and migration 20261102120000), the
# controller (../ops-controller/stubs-extra.sql and migration 20261104010000 as released), the AI guard functions from repository migration
# 20261102070000 (ai-guards.sql) and stubs-extra.sql. Checks the six definitions this change edits and the three it calls against their live md5s
# (read 3 Nov 2026 18:17 AEDT), reproduces the IQ-00067 false reopening on the live definitions (fixtures-before.sql), applies the migration
# (six guarded edits, after-md5s checked), applies it again (already applied, nothing changed), and runs fixtures.sql. OPS_A2_KEEP=1 keeps it.
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${OPS_A2_DB:-ops_reopen_fixtures}
FX=tests/fixtures/ops-reopen
MIG=supabase/migrations/20261104100000_cf247_ops_reopen_rule_ai_contract.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
q() { $P -d $DB -Atc "$1"; }
md5of() { q "select md5(pg_get_functiondef('$1'::regprocedure))"; }
declare -A LIVE=(
  ["security.integration_issue_upsert_v1(jsonb,text)"]=f292f65689a35e213a3d12a539c11b1d
  ["security.integration_validate_v1()"]=5d88b7c14f4db3b26e7b2650364602db
  ["security.ops_issue_signals_v1(bigint,jsonb)"]=a966f2b39a734f05c045c53e274d0863
  ["security.ops_controller_tick_v1()"]=24793664aa99d3d97da1dcb2e63fb28c
  ["public.svc_ops_diagnosis_next(integer)"]=ade1ae9613bbdfd6f45bd6408e20d880
  ["public.svc_ops_diagnosis_record(bigint,jsonb,numeric)"]=1ac0cc3359af6bca9c0e28e74ed49bcd
  ["security.integration_issue_close_v1(bigint,text,jsonb)"]=4cae8eaee7444e0aa942b2702eb10bc6
  ["security.ai_spend_capture_v1()"]=5b78fa074a9480d4f127ecc4fe93dcf3
  ["security.ai_use_refusal_v1(text)"]=60c782e5aec7eb218c1149a3ad85dde2
)
EDITED="security.integration_issue_upsert_v1(jsonb,text) security.integration_validate_v1() security.ops_issue_signals_v1(bigint,jsonb) security.ops_controller_tick_v1() public.svc_ops_diagnosis_next(integer) public.svc_ops_diagnosis_record(bigint,jsonb,numeric)"
after() { sed -n "s/^--   ${1//[()]/.} *[0-9a-f]* -> \([0-9a-f]*\)$/\1/p" $MIG; }
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null 2>&1
[ -n "${OPS_A2_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT
$P -d $DB -f tests/fixtures/integration-queue/stubs.sql
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261102120000_cf247_integration_queue.sql 2>/dev/null
$P -d $DB -f tests/fixtures/ops-controller/stubs-extra.sql
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261104010000_cf247_ops_controller.sql 2>/dev/null
$P -d $DB -c "set check_function_bodies = off" -f $FX/ai-guards.sql
$P -d $DB -f $FX/stubs-extra.sql
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "before (loaded = live, 3 Nov 18:17 AEDT): ${#LIVE[@]} definitions"
$P -d $DB -f $FX/fixtures-helpers.sql
$P -d $DB -f $FX/fixtures-before.sql 2>&1 | show
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': applied$')" = 6 ] || { echo "the migration did not apply its six guarded edits"; echo "$OUT" | tail -5; exit 1; }
for s in $EDITED; do a=$(after "$s"); [ -n "$a" ] && [ "$(md5of "$s")" = "$a" ] || { echo "after md5 of $s: $(md5of "$s") (expected $a)"; exit 1; }; echo "after: $s $a"; done
S1=$(q "select md5(string_agg(x, '|' order by x)) from (select r::text x from pipeline.ops_root_causes r union all select m::text from pipeline.ops_remedies m union all select s.key || s.value::text from pipeline.platform_toolset_settings s union all select t.tgname || t.tgrelid::regclass::text from pg_trigger t where not t.tgisinternal) z")
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': already applied$')" = 6 ] || { echo "a second run changed something"; echo "$OUT" | tail -5; exit 1; }
[ "$(q "select md5(string_agg(x, '|' order by x)) from (select r::text x from pipeline.ops_root_causes r union all select m::text from pipeline.ops_remedies m union all select s.key || s.value::text from pipeline.platform_toolset_settings s union all select t.tgname || t.tgrelid::regclass::text from pg_trigger t where not t.tgisinternal) z")" = "$S1" ] || { echo "a second run changed the registers, settings or triggers"; exit 1; }
echo "second run: already applied, unchanged"
$P -d $DB -f $FX/fixtures.sql 2>&1 | show
echo "all ops reopen and AI contract fixtures passed"
