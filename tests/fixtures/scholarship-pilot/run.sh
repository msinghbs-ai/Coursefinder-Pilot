#!/usr/bin/env bash
# CF-247 scholarships beyond universities: the pilot scope and stop conditions on isolated fixtures (Platform Admin decision 3 Nov 2026 08:44 §4).
# Needs a scratch PostgreSQL (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Rebuilds today's live scholarship definitions from the
# scholarship-recovery fixtures (live text before v2.15.413, checked against the md5s read on 2 Nov; then the 20261103050000 migration, as deployed),
# checks every definition this change replaces or reads equals the live md5 read on 3 Nov 2026 08:47 AEDT (live-md5s.json), applies the
# 20261103090000 migration, applies it again (no change), then runs fixtures.sql. Drops the throwaway database at the end.
set -euo pipefail
cd "$(dirname "$0")"
DB=${SCHPILOT_DB:-scholarship_pilot_fixtures}
REC=../scholarship-recovery
MIG0=../../../supabase/migrations/20261103050000_cf247_scholarship_recovery.sql
MIG=../../../supabase/migrations/20261103090000_cf247_scholarship_nonuni_pilot.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
trap '$P -d postgres -c "drop database if exists $DB" >/dev/null' EXIT
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
$P -d $DB -f $REC/stubs.sql
$P -d $DB -f stubs-pilot.sql
node $REC/load-live.mjs | $P -d $DB -o /dev/null
$P -d $DB -1 -At -f $MIG0 | grep -c ': applied' | grep -qx 14 || { echo "v2.15.413 did not rebuild"; exit 1; }
SIGS=$(node -e "const d=require('./live-md5s.json');console.log(Object.keys(d).filter(k=>!k.startsWith('_')).join(' '))")
md5s() { for s in $SIGS; do $P -d $DB -Atc "select md5(pg_get_functiondef('$s'::regprocedure))"; done | paste -sd' '; }
LIVE=$(node -e "const d=require('./live-md5s.json');console.log(Object.keys(d).filter(k=>!k.startsWith('_')).map(k=>d[k]).join(' '))")
BEFORE=$(md5s)
[ "$BEFORE" = "$LIVE" ] || { echo "rebuilt definitions differ from live: $BEFORE"; exit 1; }
echo "before (rebuilt = live 3 Nov 08:47): $(echo $BEFORE | wc -w) definitions"
$P -d $DB -1 -At -f $MIG | grep -c ': applied' | grep -qx 5 || { echo "the migration did not apply all five replacements and edits"; exit 1; }
AFTER=$(md5s); echo "after: $(node -e "const a=process.argv[1].split(' '),b=process.argv[2].split(' ');console.log(a.filter((x,i)=>x!==b[i]).length)" "$AFTER" "$BEFORE") definitions changed"
for s in $SIGS; do echo "  $s $($P -d $DB -Atc "select md5(pg_get_functiondef('$s'::regprocedure))")"; done
$P -d $DB -1 -At -f $MIG 2>/dev/null | grep -c 'already applied' | grep -qx 5 || { echo "a second run changed something"; exit 1; }
[ "$(md5s)" = "$AFTER" ] || { echo "a second run changed a definition"; exit 1; }
echo "second run: already applied, unchanged"
$P -d $DB -f fixtures.sql 2>&1 | show
