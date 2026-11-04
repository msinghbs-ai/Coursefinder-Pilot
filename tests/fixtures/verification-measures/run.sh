#!/usr/bin/env bash
# CF-247 verification measures (migration 20261104500000; direction 4 Nov 2026 10:00 §6, §7, §10, §11) on isolated fixtures. Needs a scratch
# PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds the database as ../first-run-verification/run.sh does (the
# queue, workstream A, the reopen rule, SS-021 F2, ops_report_v1 at 3ba694dc), applies first-run verification 20261104460000 as released (v2.15.464),
# then stubs.sql and the scholarship classifier as live (its definition from 20261104390000 with the v2.15.461 edit from 20261104430000). Checks
# the six definitions this change edits against their live md5s (read 4 Nov 2026 11:10 AEDT), applies the migration (six guarded edits), again
# (nothing changes), then fixtures.sql. Drops the database at the end (VM_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${VM_DB:-verification_measures_fixtures}
P="psql -v ON_ERROR_STOP=1 -q -X"
MIG=supabase/migrations/20261104500000_cf247_verification_measures.sql
FRV=tests/fixtures/first-run-verification
FX=tests/fixtures/verification-measures
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
q() { $P -d $DB -Atc "$1"; }
md5of() { q "select md5(pg_get_functiondef('$1'::regprocedure))"; }
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null 2>&1
[ -n "${VM_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT

# 1 the database as live (4 Nov 2026 11:10 AEDT)
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
$P -d $DB -f $FX/stubs.sql >/dev/null 2>&1
S=supabase/migrations/20261104390000_cf247_sch_coverage_recovery.sql; F=supabase/migrations/20261104430000_cf247_sch_coverage_classify_fix.sql
{ echo "set check_function_bodies = off;"; awk '/^create or replace function security.scholarship_coverage_classify_v1\(/,/^end \$function\$;/' $S; } | $P -d $DB >/dev/null
{ awk '/^create or replace function pg_temp.edit_once/,/^end \$f\$;/' $F; awk "/^select pg_temp.edit_once\('security.scholarship_coverage_classify_v1\(uuid\[\]\)'/,/^\], array\[1, 1, 1, 1, 1, 1, 1, 1\]\);/" $F; } | $P -d $DB -1 >/dev/null
declare -A LIVE=(
  ["security.integration_issue_upsert_v1(jsonb,text)"]=b0a1a64982680ae5d588c2d73b779e4e
  ["security.scholarship_coverage_classify_v1(uuid[])"]=c072494c5e0082e2a8b58a06dfd94a00
  ["security.progress_measure_v1(text,timestamp with time zone)"]=36447d3fd694efceaab38339fcd5ff12
  ["security.progress_zero_reason_v1(text,jsonb)"]=9554405ed2ef504b3dfceb29acec165d
  ["security.release_first_run_register_v1(text,jsonb,jsonb,timestamp with time zone,text)"]=22788bb62eb9fcccad30c414da3923c0
  ["security.self_sustainability_v1(integer)"]=77c269232cdea05bafe2e46b51d5ac8f
  ["security.ops_report_v1(integer)"]=518b5bf873549931a15d4173fef793d5
  ["security.first_run_verify_jobs_v1()"]=4989fe1dc42f1886fac85d02fb96075f
  ["security.integration_issue_transition_v1(bigint,text,text,text,jsonb)"]=3e8fc63663e5120c50f0859da97dd7a8
)
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s") (expected ${LIVE[$s]})"; exit 1; }; done
echo "before (loaded = live 11:10 AEDT): ${#LIVE[@]} definitions"
EDITED=$(grep -E '^--   security\.[a-z_0-9]+\(.*\) +[0-9a-f]{32} -> [0-9a-f]{32}$' $MIG | sed -E 's/^--   (security\.[^ ]+\(.*\)) +[0-9a-f]{32} -> ([0-9a-f]{32})$/\1|\2/')
[ "$(echo "$EDITED" | wc -l)" = 6 ] || { echo "the header must list six edits"; exit 1; }
FNS="select md5(string_agg(p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)), '|' order by p.oid::regprocedure::text)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('security', 'public', 'pipeline', 'api') and p.prokind = 'f' and p.proname not in ('integration_issue_upsert_v1', 'scholarship_coverage_classify_v1',
       'progress_measure_v1', 'progress_zero_reason_v1', 'release_first_run_register_v1', 'self_sustainability_v1', 'integration_issue_severity_v1', 'recovery_condition_gaps_v1',
       'pipeline_progress_table_v1')"
F0=$(q "$FNS")

# 2 the migration, then again
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': applied$')" = 6 ] || { echo "the migration did not apply its six guarded edits"; echo "$OUT" | tail -5; exit 1; }
while IFS='|' read -r sig after; do [ "$(md5of "$sig")" = "$after" ] || { echo "after md5 of $sig: $(md5of "$sig") (header $after)"; exit 1; }; echo "after: $sig $after"; done <<<"$EDITED"
[ "$(q "$FNS")" = "$F0" ] || { echo "the migration changed a function it does not declare"; exit 1; }
[ "$(md5of 'security.ops_report_v1(integer)')" = 518b5bf873549931a15d4173fef793d5 ] || { echo "ops_report_v1 changed"; exit 1; }
SNAP="select md5(string_agg(x, '|' order by x)) from (select key || value::text x from pipeline.platform_toolset_settings union all select jobname || measure_key from pipeline.job_output_contracts
      union all select jobname || schedule || command from cron.job) s"
S1=$(q "$SNAP")
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': already applied$')" = 6 ] || { echo "a second run changed an edited function"; exit 1; }
[ "$(q "$SNAP")" = "$S1" ] && [ "$(q "$FNS")" = "$F0" ] || { echo "a second run changed settings, contracts, jobs or functions"; exit 1; }
echo "second run: already applied, unchanged"

# 3 the cases
$P -d $DB -f $FX/fixtures.sql 2>&1 | show
echo "all verification-measures fixtures passed"
