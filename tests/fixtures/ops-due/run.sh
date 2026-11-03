#!/usr/bin/env bash
# CF-247 P0 workstream A (Integration Controller 3 Nov 2026 20:05; migration 20261104130000) on isolated fixtures. Scratch PostgreSQL only.
# Builds the v2.15.436 state: the integration queue (20261102120000), the controller (20261104010000), the IQ-00067 false reopenings on the
# definitions of that time (../ops-reopen/fixtures-before.sql), the reopen rule (20261104100000); checks the controller tick against its live
# md5 (read 3 Nov 2026 20:04 AEDT); replays 19:24 and 19:54 (fixtures-before.sql: the verification skipped); applies the migration (after-md5
# checked), again (already applied), and runs fixtures.sql. OPS_A3_KEEP=1 keeps the database.
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${OPS_A3_DB:-ops_due_fixtures}
FX=tests/fixtures/ops-due
MIG=supabase/migrations/20261104130000_cf247_ops_verify_due_minute.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
md5of() { $P -d $DB -Atc "select md5(pg_get_functiondef('$1'::regprocedure))"; }
LIVE=b4df5f8106fcbaca1bfcd933f532a55f
AFTER=$(sed -n 's/^--   security.ops_controller_tick_v1() *[0-9a-f]* -> \([0-9a-f]*\)$/\1/p' $MIG)
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null 2>&1
[ -n "${OPS_A3_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT
$P -d $DB -f tests/fixtures/integration-queue/stubs.sql
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261102120000_cf247_integration_queue.sql 2>/dev/null
$P -d $DB -f tests/fixtures/ops-controller/stubs-extra.sql
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261104010000_cf247_ops_controller.sql 2>/dev/null
$P -d $DB -c "set check_function_bodies = off" -f tests/fixtures/ops-reopen/ai-guards.sql
$P -d $DB -f tests/fixtures/ops-reopen/stubs-extra.sql
$P -d $DB -f tests/fixtures/ops-reopen/fixtures-helpers.sql
$P -d $DB -f tests/fixtures/ops-reopen/fixtures-before.sql 2>&1 | show
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261104100000_cf247_ops_reopen_rule_ai_contract.sql
[ "$(md5of 'security.ops_controller_tick_v1()')" = $LIVE ] || { echo "the tick differs from live v2.15.436: $(md5of 'security.ops_controller_tick_v1()')"; exit 1; }
echo "before (loaded = live v2.15.436): security.ops_controller_tick_v1() $LIVE"
$P -d $DB -f $FX/fixtures-before.sql 2>&1 | show
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': applied$')" = 1 ] || { echo "the migration did not apply its edit"; echo "$OUT" | tail -5; exit 1; }
[ "$(md5of 'security.ops_controller_tick_v1()')" = "$AFTER" ] || { echo "after md5: $(md5of 'security.ops_controller_tick_v1()') (expected $AFTER)"; exit 1; }
echo "after: security.ops_controller_tick_v1() $AFTER"
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': already applied$')" = 1 ] || { echo "a second run changed something"; exit 1; }
echo "second run: already applied"
$P -d $DB -f $FX/fixtures.sql 2>&1 | show
echo "all ops due fixtures passed"
