#!/usr/bin/env bash
# CF-247 Scholarship Coverage Recovery on isolated fixtures (mandate 2 Nov 2026 17:41; overnight direction 23:24). Needs a scratch PostgreSQL
# (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database (stubs.sql: live column definitions); loads the
# definitions the migration replaces, edits or reads from their live text (live-defs.json) and checks each md5 against the live md5 read on
# 2 Nov 2026; reproduces the defects on the live definitions (fixtures-before.sql); applies the 20261102140000 migration unchanged (its own md5
# guards and after-md5 checks run), applies it again (no change), then runs fixtures.sql. Drops the throwaway database at the end.
set -euo pipefail
cd "$(dirname "$0")"
DB=${SCHREC_DB:-scholarship_recovery_fixtures}
MIG=../../../supabase/migrations/20261102140000_cf247_scholarship_recovery.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
trap '$P -d postgres -c "drop database if exists $DB" >/dev/null' EXIT
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
$P -d $DB -f stubs.sql
node load-live.mjs | $P -d $DB -o /dev/null
SIGS=$(node -e "const d=require('./live-defs.json');console.log(Object.keys(d).filter(k=>!k.startsWith('_')).join(' '))")
md5s() { for s in $SIGS; do $P -d $DB -Atc "select md5(pg_get_functiondef('$s'::regprocedure))"; done | paste -sd' '; }
LIVE=$(node -e "const d=require('./live-defs.json');console.log(Object.keys(d).filter(k=>!k.startsWith('_')).map(k=>d[k].md5).join(' '))")
BEFORE=$(md5s)
[ "$BEFORE" = "$LIVE" ] || { echo "loaded definitions differ from live"; exit 1; }
echo "before (loaded = live): $(echo $BEFORE | wc -w) definitions"
$P -d $DB -f fixtures-before.sql 2>&1 | show
$P -d $DB -1 -At -f $MIG | grep -c ': applied' | grep -qx 14 || { echo "the migration did not apply all fourteen replacements and edits"; exit 1; }
AFTER=$(md5s); echo "after: $(node -e "const a=process.argv[1].split(' '),b=process.argv[2].split(' ');console.log(a.filter((x,i)=>x!==b[i]).length)" "$AFTER" "$BEFORE") definitions changed"
$P -d $DB -1 -At -f $MIG 2>/dev/null | grep -c 'already applied' | grep -qx 14 || { echo "a second run changed something"; exit 1; }
[ "$(md5s)" = "$AFTER" ] || { echo "a second run changed a definition"; exit 1; }
echo "second run: already applied, unchanged"
$P -d $DB -f fixtures.sql 2>&1 | show
