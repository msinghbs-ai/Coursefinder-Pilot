#!/usr/bin/env bash
# Guards: Platform Admin directive 10 Nov 2026 14:02 (rapidly increase source-backed entry-requirement coverage across all eligible AU/NZ providers) and G4 database-backed tests: migration 20261110160000 (a) stops parked Layer 4 holds from using the capacity of the scheduled entry reading, with the limit unchanged and the fair mode untouched, (b) names the route of every provider with no source, (c) adds the AER Data Delivery key; md5-guarded, idempotent, read only, and taken back by its held forward recovery.
# Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a small database (stubs.sql: only the tables and helpers the change reads), loads the live definitions it edits (live/, bodies md5
# 705375f3705eb739cbc2bc2b9d64de53 and a9796f1cf7a3308c01972f2a4226eb90, read 10 Nov 2026; Data Delivery as 20261110150000 leaves it, 849453412a8b9a448118e7b87362752a) and the page score function of migration 20261107150000,
# then runs before.sql, the migration twice, after.sql, the refusals and the forward recovery. Drops the database at the end (ASR_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
export LC_ALL=C # fixed: one byte order for sort and comm, whatever the runner's locale
DB=${ASR_DB:-g_aer_source_recovery}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
F=tests/fixtures/aer-source-recovery
M=supabase/migrations/20261110160000_cf247_aer_source_recovery.sql
R=supabase/held/aer_source_recovery_forward_recovery.sql
SCORE=supabase/migrations/20261107150000_cf247_aer_source_stored_discovery.sql
DDM=supabase/migrations/20261110150000_cf247_dd_provider_ai_allowance.sql
TICK='security.aer_schedule_tick_v1(boolean)'; FIND='security.aer_current_findings_v1()'; DDV='security.data_delivery_v1()'
TICK_BEFORE=705375f3705eb739cbc2bc2b9d64de53; FIND_BEFORE=a9796f1cf7a3308c01972f2a4226eb90; DDV_PDESC=849453412a8b9a448118e7b87362752a
TICK_AFTER=f995e9521198ae57ab0401564e4e5a20; FIND_AFTER=13b3a30c15b10135a2441158fc80f48c; DDV_AFTER=04b560cfb6b79758e2b694c96771be33
q() { psql -X -d "$DB" -Atc "$1"; }
W=$(mktemp -d); trap 'rm -rf "$W"; [ -n "${ASR_KEEP:-}" ] || { dropdb --if-exists '$DB' >/dev/null 2>&1; dropdb --if-exists '${DB}_refuse' >/dev/null 2>&1; }' EXIT
dropdb --if-exists $DB >/dev/null 2>&1; createdb $DB
$P -f $F/stubs.sql
# the page score function, as migration 20261107150000 creates it (lines from its create to the closing $function$)
awk '/^create or replace function security.entry_source_score_v1/{f=1} f{print} f&&/^\$function\$;/{exit}' $SCORE > $W/score.sql
[ -s $W/score.sql ] || { echo "could not extract the score function"; exit 1; }
$P -f $W/score.sql
# the live definitions (functions are created with their bodies unchecked, as live holds them)
for f in security.aer_schedule_tick_v1 security.aer_current_findings_v1; do { echo "set check_function_bodies = off;"; cat $F/live/$f.sql; echo ";"; } > $W/$f.sql; $P -f $W/$f.sql; done
[ "$(q "select md5(prosrc) from pg_proc where oid = '$TICK'::regprocedure")" = $TICK_BEFORE ] || { echo "the loaded $TICK differs from live $TICK_BEFORE"; exit 1; }
[ "$(q "select md5(prosrc) from pg_proc where oid = '$FIND'::regprocedure")" = $FIND_BEFORE ] || { echo "the loaded $FIND differs from live $FIND_BEFORE"; exit 1; }
# Data Delivery as live holds it after 20261110150000: the live text (b67bd181...) plus that migration's one inserted line
python3 - "$W" <<'PY'
import sys, re
w = sys.argv[1]
live = open('tests/fixtures/pdesc-dd-ai/live/security.data_delivery_v1.sql').read().replace('\r', '')
mig = open('supabase/migrations/20261110150000_cf247_dd_provider_ai_allowance.sql').read()
m = re.search(r"array\[\$o\$(.*?)\$o\$\],\s*array\[\$n\$(.*?)\$n\$\]", mig, re.S)
assert m and live.count(m.group(1)) == 1
open(w + '/dd.sql', 'w').write('set check_function_bodies = off;\n' + live.replace(m.group(1), m.group(2)) + ';\n')
PY
$P -f $W/dd.sql
[ "$(q "select md5(prosrc) from pg_proc where oid = '$DDV'::regprocedure")" = $DDV_PDESC ] || { echo "the loaded $DDV is not the one 20261110150000 leaves ($DDV_PDESC)"; exit 1; }
echo "loaded: the tick, the findings function and Data Delivery as live (body md5 $TICK_BEFORE, $FIND_BEFORE, $DDV_PDESC), the page score function of 20261107150000"
$P -f $F/data.sql
$P -f $F/seed_l4.sql
OUT=$($P -f $F/before.sql 2>&1) || { echo "$OUT" | grep -E 'FAIL|ERROR' | head -3; exit 1; }
echo "before: 12 pending items against the limit of 10 stop every new course read; the no_source finding names no route (the live defect, reproduced)"

FNS="select p.oid::regprocedure::text || ' ' || md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public', 'api') and p.prokind = 'f' order by 1"
DATA="select (select md5(string_agg(r::text, '|' order by r.id)) from pipeline.layer4_review_items r) || (select md5(string_agg(r::text, '|' order by r.id)) from pipeline.work_items r) || (select md5(string_agg(r::text, '|' order by r.key)) from pipeline.platform_toolset_settings r) || (select md5(string_agg(r::text, '|' order by r.jobid)) from cron.job r) || (select count(*) from pipeline.entry_matrix_sources)"
snap() { q "$FNS" | sort > "$1.fn"; q "$DATA" > "$1.data"; }
same() { for f in "${@:3}"; do cmp -s "$1.$f" "$2.$f" || { echo "changed: $f"; exit 1; }; done; }

# a live function that differs from the recorded one: the migration raises and nothing at all is applied; so does the forward recovery
RF=${DB}_refuse
dropdb --if-exists $RF >/dev/null 2>&1; createdb -T $DB $RF
psql -X -q -d $RF -v ON_ERROR_STOP=1 -c "do \$\$ begin execute replace(pg_get_functiondef('$TICK'::regprocedure), 'v_cost numeric :=', 'v_cost numeric := 0 + '); end \$\$" >/dev/null
[ "$(psql -X -d $RF -Atc "select md5(prosrc) from pg_proc where oid = '$TICK'::regprocedure")" != $TICK_BEFORE ] || { echo "the hand change did not change $TICK"; exit 1; }
rb=$( (psql -X -d $RF -Atc "$FNS" | sort | md5sum) )
OUT=$(psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $M 2>&1) && { echo "$M applied over a changed $TICK"; exit 1; }
grep -qF "differs from the definition this change edits" <<<"$OUT" || { echo "the refusal is not the expected one: $OUT" | tail -3; exit 1; }
ra=$( (psql -X -d $RF -Atc "$FNS" | sort | md5sum) )
[ "$rb" = "$ra" ] || { echo "the refused migration changed something"; exit 1; }
echo "refused: a hand-changed live tick is refused by the migration and nothing is applied (no function added, none edited)"
dropdb --if-exists $RF >/dev/null 2>&1

# the migration
snap "$W/0"
OUT=$($P -1 -At -f $M 2>&1) || { echo "$OUT" | tail -8; exit 1; }
[ "$(q "select md5(prosrc) from pg_proc where oid = '$TICK'::regprocedure")" = $TICK_AFTER ] && [ "$(q "select md5(prosrc) from pg_proc where oid = '$FIND'::regprocedure")" = $FIND_AFTER ] && [ "$(q "select md5(prosrc) from pg_proc where oid = '$DDV'::regprocedure")" = $DDV_AFTER ] || { echo "the migration did not leave the recorded md5s"; exit 1; }
for want in "security.aer_schedule_tick_v1(boolean) $TICK_BEFORE -> $TICK_AFTER" "security.aer_current_findings_v1() $FIND_BEFORE -> $FIND_AFTER" "security.data_delivery_v1() $DDV_PDESC -> $DDV_AFTER"; do grep -qF -- "--   $want" $M || { echo "the migration header does not record: $want"; exit 1; }; done
snap "$W/1"
changed=$(comm -23 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//' | sort); added=$(comm -13 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//' | sort)
[ "$changed" = "$(printf '%s\n' "$DDV" "$FIND" "$TICK" | sort)" ] || { echo "functions changed other than the three edited: $changed"; exit 1; }
[ "$(comm -13 <(echo "$changed") <(echo "$added") | tr '\n' ' ')" = "security.aer_no_source_route_v1() security.aer_parked_items_v1() security.data_delivery_aer_v1() " ] || { echo "unexpected functions added: $added"; exit 1; }
same "$W/0" "$W/1" data
OUT=$($P -1 -At -f $M 2>&1) || { echo "$OUT" | tail -8; exit 1; }
snap "$W/2"; same "$W/1" "$W/2" fn data
echo "migration 20261110160000: the tick, the findings function and Data Delivery go from the recorded live md5s to the recorded after md5s, three read-only functions are added, no layer 4 item, work item, setting, job or source changed; applied again: no change"

# the scenarios
OUT=$($P -f $F/after.sql 2>&1) || { echo "$OUT" | grep -E 'ERROR|FAIL' | head -5; exit 1; }
echo "$OUT" | grep -qE 'FAIL|ERROR' && { echo "$OUT" | grep -E 'FAIL|ERROR' | head -5; exit 1; }
echo "scenarios: $(grep -c 'NOTICE:  ok:' <<<"$OUT") checks passed (parked holds, capacity with the limit kept and the fair mode left as is, the six routes, the finding's evidence, the Data Delivery key, read only)"

# the forward recovery: the three edits are taken back; the new functions stay (unused); repeatable; the migration applies again after it
$P -1 -At -f $R >/dev/null
[ "$(q "select md5(prosrc) from pg_proc where oid = '$TICK'::regprocedure")" = $TICK_BEFORE ] && [ "$(q "select md5(prosrc) from pg_proc where oid = '$FIND'::regprocedure")" = $FIND_BEFORE ] && [ "$(q "select md5(prosrc) from pg_proc where oid = '$DDV'::regprocedure")" = $DDV_PDESC ] || { echo "the recovery did not restore the live bodies"; exit 1; }
[ "$(q "select to_regprocedure('security.data_delivery_aer_v1()') is not null")" = t ] || { echo "the recovery removed a new function"; exit 1; }
$P -1 -At -f $R >/dev/null
$P -1 -At -f $M >/dev/null
[ "$(q "select md5(prosrc) from pg_proc where oid = '$TICK'::regprocedure")" = $TICK_AFTER ] && [ "$(q "select md5(prosrc) from pg_proc where oid = '$DDV'::regprocedure")" = $DDV_AFTER ] || { echo "the migration did not apply again after the recovery"; exit 1; }
echo "recovery: the forward recovery returns the three functions to the live bodies (md5s above), is repeatable, and the migration applies again after it"
echo "aer-source-recovery: done"
