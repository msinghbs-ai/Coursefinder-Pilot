#!/usr/bin/env bash
# CF-247 Layer 4 action lifecycle (migration 20261104540000; Platform Admin decision 4 Nov 2026 12:24) on isolated fixtures. Needs a scratch
# PostgreSQL 16 (never a Supabase project): PGHOST/PGUSER point at it. Builds a throwaway database:
#   1 ../human-assisted-recovery/run.sh (it must pass) builds the live Layer 4 functions with v2.15.463 and the v2.15.466 hotfix; then the
#     Inbox paging migration 20261104440000 (live order: 440000 before 450000; its guarded edit of the Inbox is independent of them);
#     the four definitions this change edits or wraps are checked against the live md5s read 4 Nov 2026 12:28 AEDT;
#   2 stubs.sql (the production columns the earlier stubs left out, the live corrected-read shape and the reader's outcome);
#   3 the migration, then again (the second run changes nothing);
#   4 seed.sql (RMIT IQ-00279, the §9 cases, one waiting item of every kind) and fixtures.sql (C1-C10).
# Drops the database at the end (L4LC_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${L4LC_DB:-l4_action_lifecycle_fixtures}
P="psql -v ON_ERROR_STOP=1 -q -X"
MIG=supabase/migrations/20261104540000_cf247_l4_action_lifecycle.sql
FX=tests/fixtures/l4-action-lifecycle
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
q() { $P -d $DB -Atc "$1"; }
md5of() { q "select md5(pg_get_functiondef('$1'::regprocedure))"; }
after() { grep -F -- "--   $1 " $MIG | head -1 | sed 's/.*-> *\([0-9a-f]*\).*/\1/'; }
[ -n "${L4LC_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT

# 1 the live Layer 4 functions
HAR_KEEP=1 HAR_DB=$DB bash tests/fixtures/human-assisted-recovery/run.sh > /dev/null
$P -d $DB -1 -At -f supabase/migrations/20261104440000_cf247_l4_inbox_paging.sql > /dev/null
declare -A LIVE=(
  ["security.layer4_aer_recovery_detail_v1(text)"]=636c1764788b008fb7456365d600b452
  ["security.layer4_aer_recovery_decide_v1(text,text,text,text)"]=841234cb4826983b3297d39a34cb0978
  ["security.layer4_aer_recovery_state_v1(uuid)"]=caf0e61bfcf983fb421638afd3aea795
  ["public.admin_layer4_inbox(text,jsonb)"]=29705b99108e7a0b4d68fea398565d36
  ["security.layer4_inbox_items_v2(uuid,text,text[],boolean)"]=1e3af24861d931c1d63d30bb87ffa0d6
  ["security.layer4_intervention_inbox_decide_v1(text,text,text,text)"]=d3cc593f9446495d57761b9d8a761e44
)
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "before (loaded = live 4 Nov 2026 12:28 AEDT): ${#LIVE[@]} definitions"

# 2 stubs
$P -d $DB -f $FX/stubs.sql > /dev/null 2>&1

# 3 the migration, then again
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
grep -q 'admin_layer4_inbox(text,jsonb): applied' <<<"$OUT" || { echo "the Inbox edit was not applied"; exit 1; }
for s in "security.layer4_aer_recovery_detail_v1(text)" "security.layer4_aer_recovery_decide_v1(text,text,text,text)" "public.admin_layer4_inbox(text,jsonb)"; do
  A=$(after "$s"); [ -n "$A" ] && [ "$(md5of "$s")" = "$A" ] || { echo "after md5 of $s: $(md5of "$s") (header: $A)"; exit 1; }
  echo "after: $s ${LIVE[$s]} -> $A"; done
for s in "security.layer4_aer_recovery_state_v1(uuid)" "security.layer4_inbox_items_v2(uuid,text,text[],boolean)" "security.layer4_intervention_inbox_decide_v1(text,text,text,text)"; do
  [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "the migration changed $s, which it does not own"; exit 1; }; done
SNAP="select md5(string_agg(x, '|' order by x)) from (select 's:' || s.key || s.value::text || s.updated_at x from pipeline.platform_toolset_settings s
  union all select 'g:' || g.kind || g.name from pipeline.component_register g union all select 'j:' || j.jobname from cron.job j
  union all select 'f:' || p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('security', 'public') and p.prokind = 'f') z"
S1=$(q "$SNAP")
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
grep -q 'admin_layer4_inbox(text,jsonb): already applied' <<<"$OUT" || { echo "the second run did not find the Inbox edit applied"; exit 1; }
[ "$(q "$SNAP")" = "$S1" ] || { echo "a second run changed settings, registers, jobs or functions"; exit 1; }
echo "applied twice: the second run changed nothing; state, the item list and the intervention decision are untouched"

# 4 the cases
$P -d $DB -f $FX/seed.sql > /dev/null
$P -d $DB -f $FX/fixtures.sql 2>&1 | show
echo "all Layer 4 action lifecycle fixtures passed"
