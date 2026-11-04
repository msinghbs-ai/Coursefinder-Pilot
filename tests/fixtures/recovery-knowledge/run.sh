#!/usr/bin/env bash
# CF-247 recovery knowledge (migration 20261104600000; direction 4 Nov 2026 18:08 §2, §3, §6, §7) on isolated fixtures. Needs a scratch PostgreSQL 16
# (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds the database as ../verification-measures/run.sh does (queue, workstream A's
# real controller, reopen rule, SS-021 F2, first-run verification 20261104460000, the classifier as live), applies verification measures
# 20261104520000 as released (v2.15.469), then stubs.sql (live root causes and remedies; their action and verification functions stood in). Checks
# the definitions this change edits or calls against their live md5s (read 4 Nov 2026 18:10 AEDT), applies the migration (three guarded edits), again
# (nothing changes), then fixtures.sql: the closed loop through the real controller for AER, Course Link and scholarships, and the refusals.
# Drops the database at the end (RK_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${RK_DB:-recovery_knowledge_fixtures}
P="psql -v ON_ERROR_STOP=1 -q -X"
MIG=supabase/migrations/20261104600000_cf247_recovery_knowledge.sql
FRV=tests/fixtures/first-run-verification
VM=tests/fixtures/verification-measures
FX=tests/fixtures/recovery-knowledge
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
q() { $P -d $DB -Atc "$1"; }
md5of() { q "select md5(pg_get_functiondef('$1'::regprocedure))"; }
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null 2>&1
[ -n "${RK_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT

# 1 the database as live (4 Nov 2026 18:10 AEDT)
$P -d $DB -f tests/fixtures/integration-queue/stubs.sql >/dev/null
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261102120000_cf247_integration_queue.sql 2>&1 | show
$P -d $DB -f tests/fixtures/ops-controller/stubs-extra.sql >/dev/null
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261104010000_cf247_ops_controller.sql 2>&1 | show
$P -d $DB -1 -o /dev/null -f tests/fixtures/ops-reopen/ai-guards.sql 2>&1 | show
$P -d $DB -f tests/fixtures/ops-reopen/stubs-extra.sql >/dev/null
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261104100000_cf247_ops_reopen_rule_ai_contract.sql 2>&1 | show
$P -d $DB -1 -o /dev/null -f $FRV/upsert-live.sql
$P -d $DB -f $FRV/stubs.sql >/dev/null 2>&1
$P -d $DB -c "set check_function_bodies = off" -f $FRV/live/security.ops_report_v1.def >/dev/null
$P -d $DB -1 -o /dev/null -f $FRV/har-edit.sql
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261104460000_cf247_first_run_verification.sql
$P -d $DB -f $VM/stubs.sql >/dev/null 2>&1
S=supabase/migrations/20261104390000_cf247_sch_coverage_recovery.sql; F=supabase/migrations/20261104430000_cf247_sch_coverage_classify_fix.sql
{ echo "set check_function_bodies = off;"; awk '/^create or replace function security.scholarship_coverage_classify_v1\(/,/^end \$function\$;/' $S; } | $P -d $DB >/dev/null
{ awk '/^create or replace function pg_temp.edit_once/,/^end \$f\$;/' $F; awk "/^select pg_temp.edit_once\('security.scholarship_coverage_classify_v1\(uuid\[\]\)'/,/^\], array\[1, 1, 1, 1, 1, 1, 1, 1\]\);/" $F; } | $P -d $DB -1 >/dev/null
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261104520000_cf247_verification_measures.sql
$P -d $DB -f $FX/stubs.sql >/dev/null
declare -A LIVE=(
  ["security.ops_authorise_v1(text)"]=ae58963cd1298edeeacae406dc65b314
  ["security.first_run_verify_tick_v1()"]=9c078d17de8d699de2d932ad1eca8fb8
  ["security.self_sustainability_v1(integer)"]=a91e9c8151cca09763cf755ab1da1f56
  ["security.ops_report_v1(integer)"]=518b5bf873549931a15d4173fef793d5
  ["security.integration_issue_upsert_v1(jsonb,text)"]=f9d7bf1a6dbe94ba97c34f10817f56c1
  ["security.integration_issue_transition_v1(bigint,text,text,text,jsonb)"]=3e8fc63663e5120c50f0859da97dd7a8
)
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s") (expected ${LIVE[$s]})"; exit 1; }; done
echo "before (loaded = live 18:10 AEDT): ${#LIVE[@]} definitions"
EDITED=$(grep -E '^--   security\.[a-z_0-9]+\(.*\) +[0-9a-f]{32} -> [0-9a-f]{32}$' $MIG | sed -E 's/^--   (security\.[^ ]+\(.*\)) +[0-9a-f]{32} -> ([0-9a-f]{32})$/\1|\2/')
[ "$(echo "$EDITED" | wc -l)" = 3 ] || { echo "the header must list three edits"; exit 1; }
NEW="'ops_learning_signature_v1', 'ops_learning_lane_v1', 'ops_learning_refusal_v1', 'ops_learning_harvest_v1', 'ops_learning_gate_v1', 'ops_learning_retry_check_v1',
     'ops_learning_record_v1', 'ops_learning_eligibility_set_v1', 'autonomy_audit_v1', 'ops_learning_metrics_v1', 'ops_learning_report_v1', 'ops_learning_tick_v1',
     'ops_authorise_v1', 'first_run_verify_tick_v1', 'self_sustainability_v1'"
FNS="select md5(string_agg(p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)), '|' order by p.oid::regprocedure::text)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('security', 'public', 'pipeline', 'api') and p.prokind = 'f' and p.proname not in ($NEW)"
F0=$(q "$FNS")

# 2 the migration, then again
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': applied$')" = 3 ] || { echo "the migration did not apply its three guarded edits"; echo "$OUT" | tail -5; exit 1; }
while IFS='|' read -r sig after; do [ "$(md5of "$sig")" = "$after" ] || { echo "after md5 of $sig: $(md5of "$sig") (header $after)"; exit 1; }; echo "after: $sig $after"; done <<<"$EDITED"
[ "$(q "$FNS")" = "$F0" ] || { echo "the migration changed a function it does not declare"; exit 1; }
SNAP="select md5(string_agg(x, '|' order by x)) from (select key || value::text x from pipeline.platform_toolset_settings union all select code || authority || active::text from pipeline.ops_remedies
      union all select code || class || detect::text from pipeline.ops_root_causes union all select jobname || schedule || command from cron.job
      union all select code || applied || verified || failed || auto_eligible::text from pipeline.ops_remedy_knowledge union all select kind from pipeline.ops_learning_readings) s"
S1=$(q "$SNAP")
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': already applied$')" = 3 ] || { echo "a second run changed an edited function"; exit 1; }
[ "$(q "$SNAP")" = "$S1" ] && [ "$(q "$FNS")" = "$F0" ] || { echo "a second run changed settings, remedies, root causes, jobs, knowledge or readings"; exit 1; }
echo "second run: already applied, unchanged"

# 3 the cases
$P -d $DB -f $FX/fixtures.sql 2>&1 | show
echo "all recovery-knowledge fixtures passed"
