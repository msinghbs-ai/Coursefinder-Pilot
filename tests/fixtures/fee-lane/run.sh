#!/usr/bin/env bash
# CF-247 FEE lane (migrations 20261108110000 plausibility guard, 20261108111000 decision memory) on isolated fixtures. Needs a scratch PostgreSQL 16
# (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database g_fees_lane_fixtures:
#   1 the IQ-00111 fixture database (../fee-units-holds/run.sh: the live reader definitions, then migration 20261104140000), so
#     public.svc_fee_ai_record is at its live md5 5ec65e53403933b98381bd5c9c79b6d1 (read live 8 Nov 2026);
#   2 stubs.sql: the live columns the two migrations touch that the IQ-00111 fixture left out, and cron / automation_catalogue stand-ins;
#   3 the guard migration, twice (the second changes nothing); the decision memory migration, twice ("already applied");
#   4 fixtures.sql: every case. Drops the database at the end (FEE_LANE_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")"
ROOT=../../..
DB=${FEE_LANE_DB:-g_fees_lane_fixtures}
G=$ROOT/supabase/migrations/20261108110000_cf247_fee_plausibility_guard.sql
M=$ROOT/supabase/migrations/20261108111000_cf247_fee_decision_memory.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
q() { $P -d $DB -Atc "$1"; }
md5of() { q "select md5(pg_get_functiondef('$1'::regprocedure))"; }
trap '[ -n "${FEE_LANE_KEEP:-}" ] || $P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT
FEE_UNITS_DB=$DB FEE_UNITS_KEEP=1 bash ../fee-units-holds/run.sh >/dev/null
REC='public.svc_fee_ai_record(uuid,jsonb,numeric,text)'
[ "$(md5of "$REC")" = 5ec65e53403933b98381bd5c9c79b6d1 ] || { echo "loaded $REC differs from live: $(md5of "$REC")"; exit 1; }
echo "definitions this change edits (loaded = live 8 Nov 2026): 1"
$P -d $DB -f stubs.sql
snap() { q "select md5(string_agg(x, '|' order by x)) from (select 's:' || s.toolset_key || s.key || s.value::text x from pipeline.platform_toolset_settings s
  union all select 'g:' || g.kind || g.name from pipeline.component_register g union all select 'j:' || jobname || schedule from cron.job union all select 'a:' || jobname from pipeline.automation_catalogue
  union all select 'f:' || p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public')) z"; }
OUT=$($P -d $DB -1 -At -f $G 2>&1) || { echo "$OUT" | tail -5; exit 1; }
S1=$(snap); OUT=$($P -d $DB -1 -At -f $G 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(snap)" = "$S1" ] || { echo "a second run of the guard migration changed something"; exit 1; }
echo "guard migration applied twice: the second run changed nothing"
AFTER=$(sed -n "s/.*svc_fee_ai_record(uuid,jsonb,numeric,text) 5ec65e53403933b98381bd5c9c79b6d1 -> \([0-9a-f]\{32\}\).*/\1/p" $M | head -1)
OUT=$($P -d $DB -1 -At -f $M 2>&1) || { echo "$OUT" | tail -5; exit 1; }
echo "$OUT" | grep -qxF "$REC: applied" || { echo "the guarded edit did not apply"; echo "$OUT" | tail -3; exit 1; }
[ "$(md5of "$REC")" = "$AFTER" ] || { echo "after md5 $(md5of "$REC"), expected $AFTER"; exit 1; }
S2=$(snap); OUT=$($P -d $DB -1 -At -f $M 2>&1) || { echo "$OUT" | tail -5; exit 1; }
echo "$OUT" | grep -qxF "$REC: already applied" || { echo "second run did not report already applied"; exit 1; }
[ "$(snap)" = "$S2" ] || { echo "a second run of the decision memory migration changed something"; exit 1; }
echo "decision memory: svc_fee_ai_record 5ec65e53403933b98381bd5c9c79b6d1 -> $AFTER; applied twice, the second changed nothing"
$P -d $DB -f fixtures.sql 2>&1 | show
echo "cases: $(grep -c "fx.ok(" fixtures.sql)"
