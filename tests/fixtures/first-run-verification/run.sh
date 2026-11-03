#!/usr/bin/env bash
# CF-247 first-run verification, progress contract and recovery-loop repair (migration 20261104460000; mandate 4 Nov 2026 08:16 §3-§5, §10) on
# isolated fixtures. Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database as the
# other controller fixtures do: the integration queue stubs and migration 20261102120000, ../ops-controller/stubs-extra.sql and workstream A's
# migration 20261104010000 (the real controller, its triggers and the remedy seeds), the reopen rule 20261104100000 and SS-021 F2 from 20261104320000
# (upsert-live.sql), so the queue writer is the live one (b0a1a649); stubs.sql (the live shapes this change reads); live/security.ops_report_v1.def
# (5a1e21cc) with the human-assisted recovery edit (har-edit.sql) to 3ba694dc, the definition this change edits. Then the migration (one guarded
# edit), again (nothing changes), and fixtures.sql (the production failures of 3-4 Nov 2026 replayed). Drops the database at the end
# (FRV_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${FRV_DB:-first_run_verification_fixtures}
P="psql -v ON_ERROR_STOP=1 -q -X"
MIG=supabase/migrations/20261104460000_cf247_first_run_verification.sql
FX=tests/fixtures/first-run-verification
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
q() { $P -d $DB -Atc "$1"; }
md5of() { q "select md5(pg_get_functiondef('$1'::regprocedure))"; }
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null 2>&1
[ -n "${FRV_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT

# 1 the database as live (4 Nov 2026 08:20 AEDT)
$P -d $DB -f tests/fixtures/integration-queue/stubs.sql
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261102120000_cf247_integration_queue.sql 2>&1 | show
$P -d $DB -f tests/fixtures/ops-controller/stubs-extra.sql
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261104010000_cf247_ops_controller.sql 2>&1 | show
$P -d $DB -1 -o /dev/null -f tests/fixtures/ops-reopen/ai-guards.sql 2>&1 | show
$P -d $DB -f tests/fixtures/ops-reopen/stubs-extra.sql
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261104100000_cf247_ops_reopen_rule_ai_contract.sql 2>&1 | show
# upsert-live.sql is SS-021 F2 as in its migration, byte for byte
A=supabase/migrations/20261104320000_cf247_work_continuity_adopt.sql
diff <(sed -n '3,$p' $FX/upsert-live.sql) <({ awk '/^create or replace function pg_temp.edit_once/,/^end \$f\$;/' $A; awk '/^create or replace function security.integration_issue_allowed_v1/,/^revoke all on function security.integration_issue_allowed_v1/' $A;
  awk "/^select pg_temp.edit_once\('security.integration_issue_upsert_v1\(jsonb,text\)'/,/array\[1, 1, 1\]\);/" $A; }) >/dev/null || { echo "upsert-live.sql differs from migration 20261104320000"; exit 1; }
$P -d $DB -1 -o /dev/null -f $FX/upsert-live.sql
$P -d $DB -f $FX/stubs.sql
$P -d $DB -c "set check_function_bodies = off" -f $FX/live/security.ops_report_v1.def >/dev/null
[ "$(md5of 'security.ops_report_v1(integer)')" = 5a1e21cc42f8f54cbf0d9f3f7fe81c71 ] || { echo "loaded ops_report_v1 differs from live 5a1e21cc"; exit 1; }
$P -d $DB -1 -o /dev/null -f $FX/har-edit.sql
declare -A LIVE=(
  ["security.integration_issue_upsert_v1(jsonb,text)"]=b0a1a64982680ae5d588c2d73b779e4e
  ["security.integration_issue_transition_v1(bigint,text,text,text,jsonb)"]=3e8fc63663e5120c50f0859da97dd7a8
  ["security.integration_issue_close_v1(bigint,text,jsonb)"]=4cae8eaee7444e0aa942b2702eb10bc6
  ["security.ops_report_v1(integer)"]=3ba694dc078995d88a983e8e92b2f425
)
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs: $(md5of "$s") (expected ${LIVE[$s]})"; exit 1; }; done
echo "before (loaded = live, or the human-assisted recovery release for ops_report_v1): ${#LIVE[@]} definitions"
FNS="select md5(string_agg(p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)), '|' order by p.oid::regprocedure::text)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('security', 'public', 'pipeline', 'api') and p.prokind = 'f' and p.proname <> 'ops_report_v1' and p.oid not in (select c.oid from pg_proc c join pg_namespace s on s.oid = c.pronamespace
       where s.nspname = 'security' and c.proname in ('cron_field_match_v1', 'cron_next_run_v1', 'progress_measure_v1', 'progress_zero_reason_v1', 'progress_read_v1',
       'recovery_error_class_v1', 'release_first_run_register_v1', 'first_run_verify_jobs_v1', 'recovery_issue_text_v1', 'recovery_link_duplicates_v1',
       'recovery_route_engineering_v1', 'first_run_verify_tick_v1', 'self_sustainability_v1'))"
F0=$(q "$FNS")

# 2 the migration, then again
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': applied$')" = 1 ] || { echo "the migration did not apply its one guarded edit"; echo "$OUT" | tail -5; exit 1; }
AFTER=$(grep -F -- '--   security.ops_report_v1(integer)' $MIG | head -1 | sed 's/.*-> *\([0-9a-f]*\).*/\1/')
[ "$(md5of 'security.ops_report_v1(integer)')" = "$AFTER" ] || { echo "ops_report_v1 after: $(md5of 'security.ops_report_v1(integer)') (header says $AFTER)"; exit 1; }
[ "$(q "$FNS")" = "$F0" ] || { echo "the migration changed a function it does not declare"; exit 1; }
echo "after: security.ops_report_v1(integer) 3ba694dc078995d88a983e8e92b2f425 -> $AFTER; no other existing function changed"
SNAP="select md5(string_agg(x, '|' order by x)) from (select key || value::text x from pipeline.platform_toolset_settings union all select code || class || detect::text from pipeline.ops_root_causes
      union all select code || authority from pipeline.ops_remedies union all select jobname || schedule || command from cron.job union all select jobname from pipeline.automation_catalogue
      union all select key || coalesce(next_key, '') from pipeline.progress_transitions union all select pattern || error_class from pipeline.recovery_error_classes) s"
S1=$(q "$SNAP")
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': already applied$')" = 1 ] || { echo "a second run changed the edited function"; exit 1; }
[ "$(q "$SNAP")" = "$S1" ] && [ "$(q "$FNS")" = "$F0" ] || { echo "a second run changed settings, root causes, remedies, jobs, transitions or functions"; exit 1; }
echo "second run: already applied, unchanged"
[ "$(q "select command from cron.job where jobname = 'first-run-verify'")" = "select security.first_run_verify_tick_v1()" ] || { echo "job command"; exit 1; }

# 3 the cases
$P -d $DB -f $FX/fixtures.sql 2>&1 | show
echo "all first-run verification fixtures passed"
