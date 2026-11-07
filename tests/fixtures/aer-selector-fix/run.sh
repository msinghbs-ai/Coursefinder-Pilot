#!/usr/bin/env bash
# CF-247 AER selector fix (migration 20261104620000; v2.15.473 first-run verification, Integration Controller 4 Nov 2026 20:02) on isolated
# fixtures. Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database:
#   1 the AER database as live after v2.15.473: ../aer-recovery-selector/run.sh (605 waiting items in live proportion, migration 20261104580000),
#     kept; then security.progress_measure_v1 as live (20261104460000 with the v2.15.469 edit of 20261104520000), the AER transitions and the row
#     limit (stubs.sql, security.course_entry_max_rows_v1 from 20261102010000); every definition this change edits checked against its live md5;
#   2 seed.sql: production at 19:13 (entry settings all touched after the items were read, values unchanged; the held step's scan reaching holds
#     before the eligible items; two corrected reads that replaced their read with no lane item), then the live lane run;
#   3 fixtures.sql part 1 (before): reproduces the defects with the live definitions;
#   4 the migration (three guarded edits to their after md5s, one producer row), then again (nothing changes);
#   5 fixtures.sql part 2 (after).
# Drops the database at the end (ASF_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${ASF_DB:-aer_selector_fix_fixtures}
P="psql -v ON_ERROR_STOP=1 -q -X"
MIG=supabase/migrations/20261104620000_cf247_aer_selector_fix.sql
FX=tests/fixtures/aer-selector-fix
FRV=supabase/migrations/20261104460000_cf247_first_run_verification.sql
VM=supabase/migrations/20261104520000_cf247_verification_measures.sql
E13=supabase/migrations/20261102010000_cf247_e13_entry_completeness_gate.sql
q() { $P -d $DB -Atc "$1"; }
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
md5of() { q "select md5(pg_get_functiondef('$1'::regprocedure))"; }
after() { grep -F -- "--   $1 " $MIG | head -1 | sed 's/.*-> *\([0-9a-f]*\).*/\1/'; }
[ -n "${ASF_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT

# 1 the AER database as live after v2.15.473
AERS_KEEP=1 AERS_DB=$DB bash tests/fixtures/aer-recovery-selector/run.sh >/dev/null
$P -d $DB -f $FX/stubs.sql >/dev/null
{ echo "set check_function_bodies = off;"; sed -n '/^create or replace function security.course_entry_max_rows_v1/,/^\$\$;/p' $E13
  sed -n '/^create or replace function security.progress_measure_v1/,/^end \$function\$;/p' $FRV; } | $P -d $DB >/dev/null
{ awk '/^create or replace function pg_temp.edit_once/,/^end \$f\$;/' $VM
  awk "/^select pg_temp.edit_once\('security.progress_measure_v1/,/\]\], array\[1, 1, 1\]\);/" $VM; } | $P -d $DB -1 >/dev/null
declare -A LIVE=(
  ["security.aer_recovery_rule_v1(uuid)"]=b194475a46186bc674a3364816a8b06b
  ["security.aer_schedule_held_v1(integer)"]=c866167b55d2494c366fd2700a518ff8
  ["security.progress_measure_v1(text,timestamp with time zone)"]=40c0c972abc353be8f6eee35c79750e9
  ["security.aer_technical_recovery_v1()"]=08322eb59fc9081ed7a684bddcfc6b64
  ["security.course_entry_max_rows_v1(uuid)"]=8d3555d998355422a1309dda0fbb0fc8
)
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "definitions this change edits or calls (loaded = live 4 Nov 2026 20:08-20:13): ${#LIVE[@]}"

# 2 production at 19:13, 3 the defects with the live definitions
$P -d $DB -f $FX/seed.sql >/dev/null
$P -d $DB -v part=before -f $FX/fixtures.sql 2>&1 | show

# 4 the migration, then again
EDITED="'security.aer_recovery_rule_v1(uuid)'::regprocedure, 'security.aer_schedule_held_v1(integer)'::regprocedure, 'security.progress_measure_v1(text,timestamp with time zone)'::regprocedure"
FNS="select md5(string_agg(p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)), '|' order by p.oid::regprocedure::text)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('security', 'public', 'api', 'pipeline') and p.prokind = 'f' and p.oid not in ($EDITED)"
SNAP="select md5(string_agg(x, '|' order by x)) from (select key || value::text || updated_at::text x from pipeline.platform_toolset_settings
      union all select key || producer_jobs::text from pipeline.progress_transitions union all select failure_class || action from pipeline.work_recovery_policies) s"
F0=$(q "$FNS")
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(grep -c ': applied$' <<<"$OUT")" = 3 ] || { echo "the migration did not apply its three guarded edits"; echo "$OUT" | tail -5; exit 1; }
for s in "security.aer_recovery_rule_v1(uuid)" "security.aer_schedule_held_v1(integer)" "security.progress_measure_v1(text,timestamp with time zone)"; do
  [ "$(md5of "$s")" = "$(after "$s")" ] || { echo "$s after: $(md5of "$s"), expected $(after "$s")"; exit 1; }
done
[ "$(q "$FNS")" = "$F0" ] || { echo "the migration changed a function it does not declare"; exit 1; }
[ "$(q "select producer_jobs::text from pipeline.progress_transitions where key = 'aer_technical_correction'")" = "{aer-scheduled-read}" ] || { echo "producer not changed"; exit 1; }
S1=$(q "$SNAP")
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(grep -c ': already applied$' <<<"$OUT")" = 3 ] || { echo "the second run was not a no-op"; exit 1; }
[ "$(q "$SNAP")" = "$S1" ] && [ "$(q "$FNS")" = "$F0" ] || { echo "the second run changed settings, transitions, policies or functions"; exit 1; }
echo "migration: three guarded edits to their after md5s and the producer row; nothing else changed; applied again: no change"

# 5 after
$P -d $DB -v part=after -f $FX/fixtures.sql 2>&1 | show
echo "aer-selector-fix fixtures: passed"
