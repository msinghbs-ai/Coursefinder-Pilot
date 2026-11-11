#!/usr/bin/env bash
# Guards: F-AER.02 AER self-healing (Platform Admin 11 Nov 2026 05:42 "self sustaining") and G4 database-backed tests: migration 20261111220000 (a) sends a read cut at
# the row limit to the shared recovery rule instead of always to a person, (b) gives corrected reads their own 24-hour allowance apart from new reads; md5-guarded,
# idempotent, refused on a changed live body, and taken back byte for byte by its held forward recovery.
# Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a small database from ../aer-source-recovery (stubs, data,
# Layer 4 seed), adds stubs.sql, loads the live definitions it edits (live/, captured by the read-only Database function snapshot run 42904796361 on 11 Nov 2026;
# body md5 d390d02a5e9b59b6e8ffaadadbf2c7e8 and f995e9521198ae57ab0401564e4e5a20), then runs before.sql, the migration twice, after.sql, the refusal and the recovery.
# Drops the database at the end (ASH_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
export LC_ALL=C # fixed: one byte order for sort, whatever the runner's locale
DB=${ASH_DB:-g_aer_self_healing}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
F=tests/fixtures/aer-self-healing
B=tests/fixtures/aer-source-recovery
M=supabase/migrations/20261111220000_cf247_aer_self_healing_corrections.sql
R=supabase/held/aer_self_healing_corrections_forward_recovery.sql
HELD='security.aer_schedule_held_v1(integer)'; TICK='security.aer_schedule_tick_v1(boolean)'
HELD_BEFORE=d390d02a5e9b59b6e8ffaadadbf2c7e8; TICK_BEFORE=f995e9521198ae57ab0401564e4e5a20
HELD_AFTER=d0863451d50241d239a8db2bb62cd15f; TICK_AFTER=b96163772b72f02b6c9956b1a263224a
q() { psql -X -d "$DB" -Atc "$1"; }
md5s() { q "select md5(prosrc) from pg_proc where oid = '$HELD'::regprocedure" ; q "select md5(prosrc) from pg_proc where oid = '$TICK'::regprocedure"; }
W=$(mktemp -d); trap 'rm -rf "$W"; [ -n "${ASH_KEEP:-}" ] || { dropdb --if-exists '$DB' >/dev/null 2>&1; dropdb --if-exists '${DB}_refuse' >/dev/null 2>&1; }' EXIT
dropdb --if-exists $DB >/dev/null 2>&1; createdb $DB
$P -f $B/stubs.sql
# the settings table of the base stub has only (toolset_key, key, value); the migration writes the full row as live holds it
$P -c "alter table pipeline.platform_toolset_settings add column label text, add column help text, add column kind text, add column min_value numeric, add column max_value numeric, add column unit text, add column sort int, add column section text, add column used_by text, add column reason text, add column updated_at timestamptz"
$P -f $F/stubs.sql
for f in security.aer_schedule_held_v1 security.aer_schedule_tick_v1; do { echo "set check_function_bodies = off;"; cat $F/live/$f.sql; echo ";"; } > $W/$f.sql; $P -f $W/$f.sql; done
[ "$(md5s | tr '\n' ' ')" = "$HELD_BEFORE $TICK_BEFORE " ] || { echo "the loaded definitions differ from live ($HELD_BEFORE, $TICK_BEFORE)"; exit 1; }
$P -f $B/data.sql
$P -f $B/seed_l4.sql
$P -f $F/seed.sql
OUT=$($P -f $F/before.sql 2>&1) || { echo "$OUT" | grep -E 'FAIL|ERROR' | head -3; exit 1; }
echo "before: a cut read the recovery rule makes eligible goes to a person, and the shared cap stops every corrected read (both live defects reproduced)"

FNS="select p.oid::regprocedure::text || ' ' || md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public') and p.prokind = 'f' order by 1"

# a live body that differs from the recorded one: the migration raises and nothing is applied
RF=${DB}_refuse
dropdb --if-exists $RF >/dev/null 2>&1; createdb -T $DB $RF
psql -X -q -d $RF -v ON_ERROR_STOP=1 -c "do \$\$ begin execute replace(pg_get_functiondef('$TICK'::regprocedure), 'v_cost numeric :=', 'v_cost numeric := 0 + '); end \$\$" >/dev/null
rb=$(psql -X -d $RF -Atc "$FNS" | sort | md5sum); sb=$(psql -X -d $RF -Atc "select count(*) from pipeline.platform_toolset_settings")
OUT=$(psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $M 2>&1) && { echo "$M applied over a changed $TICK"; exit 1; }
grep -qF "differs from the definition this change edits" <<<"$OUT" || { echo "the refusal is not the expected one: $OUT" | tail -3; exit 1; }
[ "$rb" = "$(psql -X -d $RF -Atc "$FNS" | sort | md5sum)" ] && [ "$sb" = "$(psql -X -d $RF -Atc "select count(*) from pipeline.platform_toolset_settings")" ] || { echo "the refused migration changed something"; exit 1; }
echo "refused: a hand-changed live tick is refused and nothing is applied (no function edited, no setting added)"
dropdb --if-exists $RF >/dev/null 2>&1

# the migration, then again
q "$FNS" | sort > $W/0.fn
OUT=$($P -1 -At -f $M 2>&1) || { echo "$OUT" | tail -8; exit 1; }
[ "$(md5s | tr '\n' ' ')" = "$HELD_AFTER $TICK_AFTER " ] || { echo "the migration did not leave the recorded md5s: $(md5s | tr '\n' ' ')"; exit 1; }
for want in "$HELD $HELD_BEFORE -> $HELD_AFTER" "$TICK $TICK_BEFORE -> $TICK_AFTER"; do grep -qF -- "--   $want" $M || { echo "the migration header does not record: $want"; exit 1; }; done
q "$FNS" | sort > $W/1.fn
changed=$(comm -23 $W/0.fn $W/1.fn | sed 's/ [0-9a-f]*$//' | sort | tr '\n' ' ')
[ "$changed" = "$HELD $TICK " ] || { echo "functions changed other than the two edited: $changed"; exit 1; }
[ "$(q "select value from pipeline.platform_toolset_settings where key = 'aer.schedule_correction_daily_max'")" = "100" ] || { echo "setting not added at 100"; exit 1; }
OUT=$($P -1 -At -f $M 2>&1) || { echo "$OUT" | tail -8; exit 1; }
q "$FNS" | sort > $W/2.fn; cmp -s $W/1.fn $W/2.fn || { echo "applied again: something changed"; exit 1; }
echo "migration 20261111220000: the two functions go from the recorded live md5s to the recorded after md5s, nothing else changes, setting added at 100; applied again: no change"

OUT=$($P -f $F/after.sql 2>&1) || { echo "$OUT" | grep -E 'FAIL|ERROR' | head -3; exit 1; }
echo "$OUT" | grep -o 'ok: after.*' | sed 's/^/  /'

# the forward recovery restores both bodies byte for byte
OUT=$($P -1 -At -f $R 2>&1) || { echo "$OUT" | tail -8; exit 1; }
[ "$(md5s | tr '\n' ' ')" = "$HELD_BEFORE $TICK_BEFORE " ] || { echo "the recovery did not restore the live md5s"; exit 1; }
[ "$(q "select value from pipeline.platform_toolset_settings where key = 'aer.schedule_correction_daily_max'")" = "0" ] || { echo "recovery did not set the allowance to 0"; exit 1; }
echo "recovery: both bodies back to $HELD_BEFORE and $TICK_BEFORE, allowance 0, nothing deleted"
echo "PASS aer-self-healing"
