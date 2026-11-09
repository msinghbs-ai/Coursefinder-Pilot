#!/usr/bin/env bash
# CF-247 AER lock agreement (migration 20261109190000; Platform Admin 9 Nov 2026 "Continue fixing ... the AER lock mismatch autonomously.") on isolated fixtures.
# Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database:
#   1 the AER database as live after the selector fix (../aer-selector-fix/run.sh: the rule as live 35281a19, D-R2 as live 2e93bd9b, the held step, the measure);
#     the definitions this change edits or calls are checked against their live md5 (read 9 Nov 2026);
#   2 stubs.sql (the setting D-R2 reads, as live) and seed.sql (locks on cases in the production shape: the page-field pair set by hand on 5 Oct 2026, one on
#     official_url alone, one on entry_requirements, one on a field D-R2 does not list; then the lane run);
#   3 fixtures.sql part before: the mismatch reproduced with the live definitions;
#   4 the migration (one guarded edit to its after md5), then again (nothing changes; no other function, setting or lock changes);
#   5 fixtures.sql part after: the rule and D-R2 agree on what a lock blocks, both directions of the setting, the floor, every other item unchanged;
#   6 the md5 guard: a drifted definition is refused and nothing is edited.
# Drops the database at the end (ALA_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${ALA_DB:-aer_lock_agreement_fixtures}
P="psql -v ON_ERROR_STOP=1 -q -X"
MIG=supabase/migrations/20261109190000_cf247_aer_rule_lock_agreement.sql
FX=tests/fixtures/aer-lock-agreement
q() { $P -d $DB -Atc "$1"; }
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
md5of() { q "select md5(pg_get_functiondef('$1'::regprocedure))"; }
after() { grep -F -- "--   $1 " $MIG | head -1 | sed 's/.*-> *\([0-9a-f]*\).*/\1/'; }
[ -n "${ALA_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT

# 1 the AER database as live after the selector fix
ASF_KEEP=1 ASF_DB=$DB bash tests/fixtures/aer-selector-fix/run.sh >/dev/null
declare -A LIVE=(
  ["security.aer_recovery_rule_v1(uuid)"]=35281a190b1465699ef3cc7eccaf6d41
  ["security.course_entry_correction_check_v1(uuid,uuid,text,jsonb,jsonb)"]=2e93bd9b3bc0c2ca7628f3a407b8f57f
)
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "definitions this change edits or calls (loaded = live 9 Nov 2026): ${#LIVE[@]}"

# 2 the setting as live, the locks, the lane run; the snapshots the later parts compare with
$P -d $DB -f $FX/stubs.sql >/dev/null
$P -d $DB -f $FX/seed.sql >/dev/null
q "create table fxl.before as select i.id item, security.aer_recovery_rule_v1(i.id)->>'class' cls, security.aer_recovery_rule_v1(i.id)->>'condition_key' ckey, (security.aer_recovery_rule_v1(i.id)->>'eligible')::boolean eligible
     from pipeline.layer4_review_items i where i.status = 'pending' and i.field_code = 'course_entry_first_read';
   create table fxl.locks_before as select count(*) n, md5(string_agg(entity_id::text || field || mode || coalesce(set_by::text, '') || set_at::text, '|' order by entity_id, field)) h from pipeline.manual_locks"

q "create table fxl.measure_before as select (security.progress_measure_v1('aer_technical_correction', now() - interval '1 day')->>'eligible')::int n"

# 3 the mismatch reproduced
$P -d $DB -v part=before -f $FX/fixtures.sql 2>&1 | show

# 4 the migration, then again
FNS="select md5(string_agg(p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)), '|' order by p.oid::regprocedure::text)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('security', 'public', 'api', 'pipeline') and p.prokind = 'f' and p.oid <> 'security.aer_recovery_rule_v1(uuid)'::regprocedure"
SNAP="select md5(string_agg(x, '|' order by x)) from (select key || value::text || updated_at::text || coalesce(used_by, '') x from pipeline.platform_toolset_settings
      union all select key || producer_jobs::text from pipeline.progress_transitions union all select failure_class || action from pipeline.work_recovery_policies
      union all select 'lock' || entity_id::text || field || mode || set_at::text from pipeline.manual_locks) s"
F0=$(q "$FNS"); S0=$(q "$SNAP")
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(grep -c ': applied$' <<<"$OUT")" = 1 ] || { echo "the migration did not apply its guarded edit"; echo "$OUT" | tail -5; exit 1; }
s=security.aer_recovery_rule_v1\(uuid\)
[ "$(md5of "security.aer_recovery_rule_v1(uuid)")" = "$(after "security.aer_recovery_rule_v1(uuid)")" ] || { echo "rule after: $(md5of security.aer_recovery_rule_v1\(uuid\)), expected $(after security.aer_recovery_rule_v1\(uuid\))"; exit 1; }
[ "$(q "$FNS")" = "$F0" ] || { echo "the migration changed a function it does not declare"; exit 1; }
[ "$(q "$SNAP")" = "$S0" ] || { echo "the migration changed a setting, transition, policy or lock"; exit 1; }
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(grep -c ': already applied$' <<<"$OUT")" = 1 ] || { echo "the second run was not a no-op"; exit 1; }
[ "$(q "$SNAP")" = "$S0" ] && [ "$(q "$FNS")" = "$F0" ] || { echo "the second run changed settings, locks or functions"; exit 1; }
echo "migration: one guarded edit to its after md5; D-R2, the held step, the measure and every other function untouched; no setting or lock changed; applied again: no change"

# 5 after
$P -d $DB -v part=after -f $FX/fixtures.sql 2>&1 | show
[ "$(q "select (n::text || h) = (select count(*)::text || md5(string_agg(entity_id::text || field || mode || coalesce(set_by::text, '') || set_at::text, '|' order by entity_id, field)) from pipeline.manual_locks) from fxl.locks_before")" = t ] || { echo "a lock changed"; exit 1; }

# 6 the md5 guard: a drifted definition is refused, nothing is edited
$P -d $DB -c "do \$\$ begin execute replace(pg_get_functiondef('security.aer_recovery_rule_v1(uuid)'::regprocedure), 'begin', 'begin -- drift'); end \$\$"
D1=$(md5of "security.aer_recovery_rule_v1(uuid)")
if OUT=$($P -d $DB -1 -At -f $MIG 2>&1); then echo "the migration edited a definition that is not the live one"; exit 1; fi
grep -q "differs from the definition this change edits" <<<"$OUT" || { echo "the guard did not name the drift: $OUT"; exit 1; }
[ "$(md5of "security.aer_recovery_rule_v1(uuid)")" = "$D1" ] || { echo "the refused migration changed the definition"; exit 1; }
echo "ok: the md5 guard refuses a drifted definition and edits nothing"
echo "aer-lock-agreement fixtures: passed"
