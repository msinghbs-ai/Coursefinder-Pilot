#!/usr/bin/env bash
# Guards: Platform Admin operating model v1.5 (10 Nov 2026, delivery first), the provider reader's AI reservation leak and its starved upgrade lane: migration 20261110140000 edits only security.provider_description_fire_v1() and security.provider_description_validate_v1(uuid,text,timestamptz,jsonb) and adds security.provider_description_settle_abandoned_v1() (checked by the md5 of each function body, the same text on PostgreSQL 16 and 17; it refuses and changes nothing when a live function differs); an abandoned reservation is settled at the dearer of the floor and the observed cost of a read, never above the reservation and never zero, the ledger row is written by the existing trigger, a live lease is untouched, the run is bounded by pdesc.queue_cap and idempotent, and an expired reading read is requeued by the fire; the duplicate test gives the same result as before for every description; migration 20261110141000 edits only security.provider_description_enqueue_v1() so that the upgrade lane is gated on its own queued count; the forward recoveries return the earlier bodies byte for byte.
# Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it (superuser: the gate scenarios count function calls with track_functions). Builds the database with the pdesc-sentence-filter harness (which builds on pdesc-lease-record-timeouts and applies 20261110040000, 20261110090000 and 20261110120000), applies 20261109110000 (the fire as live has it), runs the scenarios. PRS_KEEP=1 keeps the databases.
set -euo pipefail
cd "$(dirname "$0")/../../.."
export LC_ALL=C # fixed: one byte order for sort and comm, whatever the runner's locale
DB=${PRS_DB:-g_pdesc_resv_settle}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
M1=supabase/migrations/20261110140000_cf247_pdesc_reservation_settlement.sql
M2=supabase/migrations/20261110141000_cf247_pdesc_upgrade_lane_gate.sql
R1=supabase/held/pdesc_reservation_settlement_forward_recovery.sql
R2=supabase/held/pdesc_upgrade_lane_gate_forward_recovery.sql
F=tests/fixtures/pdesc-reservation-settlement
FIRE='security.provider_description_fire_v1()'
VAL='security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)'
ENQ='security.provider_description_enqueue_v1()'
SETTLE='security.provider_description_settle_abandoned_v1()'
FIRE_BEFORE=21662da5fc9c4e15facbaef47b63a50f; FIRE_AFTER=e518081dfb0882f93c264813b6ce3788
VAL_BEFORE=7347f51b70a0c4a6cdd01a117080aad5; VAL_AFTER=91a7c9b7757cace6006af37df2bdc40a
ENQ_BEFORE=e97170e51cb27dee62db0cef3e07bb43; ENQ_AFTER=6506620f2895f0b977e40261f4ff6afd
SETTLE_AFTER=6d27f04c5555ecdb7f8c4efb26abdcfb
q() { psql -X -d "$DB" -Atc "$1"; }
BASE=$(PDSF_KEEP=1 PDSF_DB=$DB bash tests/fixtures/pdesc-sentence-filter/run.sh 2>&1) || { echo "$BASE" | tail -15; echo "the base harness failed"; exit 1; }
echo "base: pdesc-sentence-filter harness built the database (20261109020000 to 20261110120000 as the harness applies them)"
W=$(mktemp -d); trap 'rm -rf "$W"; [ -n "${PRS_KEEP:-}" ] || { dropdb --if-exists '$DB' >/dev/null 2>&1; dropdb --if-exists '${DB}_refuse' >/dev/null 2>&1; }' EXIT
$P -1 -At -f supabase/migrations/20261109110000_cf247_pdesc_fire_window_jitter.sql >/dev/null || { echo "the prerequisite migration 20261109110000 failed"; exit 1; }
echo "prerequisite: 20261109110000 applied (the fire as live has it)"

# the edited functions are the live ones (md5 of the function body, pg_proc.prosrc, read 10 Nov 2026 UTC, project fxcwkweaxjtknorudmwp), and so are the ones the change relies on
declare -A LIVE=( ["$FIRE"]=$FIRE_BEFORE ["$VAL"]=$VAL_BEFORE ["$ENQ"]=$ENQ_BEFORE ['public.svc_provider_description_record(jsonb)']=5dab0348f912018e517671aef376c5b6 ['public.svc_provider_description_reserve_v1(uuid,text,numeric,text)']=8f1f3edfb97f848b4296d6be0333a35b
  ['public.svc_provider_description_next(integer)']=504678d725b0131785f7e3541a6c3695 ['security.provider_description_selection_v1(jsonb)']=7f4a7aa8fea1b81bbf8c1742d749502e )
for sig in "${!LIVE[@]}"; do
  [ "$(q "select md5(prosrc) from pg_proc where oid = '$sig'::regprocedure")" = "${LIVE[$sig]}" ] || { echo "the loaded $sig differs from live ${LIVE[$sig]}"; exit 1; }
done
echo "loaded: the fire, the validator, the enqueue, the record, the reserve, the lease and the selection = live (body md5 recorded in the migration headers)"

run_scen() { psql -X -d "$DB" -Atq -f "$1" 2>&1 | grep -aE '^([a-z0-9_]+\||.*ERROR)' || true; }
check() { # name, got, expected file
  grep -q 'ERROR' <<<"$2" && { echo "$1 failed:"; echo "$2" | grep ERROR | head -3; exit 1; }
  [ "$2" = "$(cat "$3")" ] || { echo "$1 differs from $3:"; diff "$3" <(echo "$2"); exit 1; }
}
check "duplicate scenarios (before)" "$(run_scen $F/duplicate-scenarios.sql)" $F/expected-duplicate.txt
check "gate scenarios (before)" "$(run_scen $F/gate-scenarios.sql)" $F/expected-gate-before.txt
grep -qx 'full_queue_provider1_queued|0' $F/expected-gate-before.txt && grep -qx 'many_queued_lane_ran|0' $F/expected-gate-before.txt || { echo "the live starvation is not in the before file"; exit 1; }
echo "before: $(wc -l < $F/expected-duplicate.txt) duplicate scenarios as expected (live behaviour) and $(wc -l < $F/expected-gate-before.txt) gate scenarios as expected, including the live starvation (a full queue of missing-description reads: the upgrade lane does not run, the profile provider is not queued)"

FNS="select p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public', 'api') and p.prokind = 'f' order by 1"
SET="select key || '=' || value::text from pipeline.platform_toolset_settings order by 1"
snap() { q "$FNS" | sort > "$1.fn"; q "$SET" | sort > "$1.set"; q "select count(*) from pipeline.layer4_review_items" > "$1.l4"; q "select md5(string_agg(r::text, '|' order by r.id)) from pipeline.provider_description_reads r" > "$1.rd"; q "select count(*) from pipeline.ai_spend_ledger" > "$1.led"; q "select count(*) from pipeline.provider_description_machine_admissions" > "$1.adm"; q "select count(*) from cron.job" > "$1.cron"; q "select md5(string_agg(description, '|' order by id)) from catalogue.providers" > "$1.desc"; q "select count(*) from pipeline.automation_catalogue" > "$1.cat" 2>/dev/null || echo none > "$1.cat"; }
same() { for f in "${@:3}"; do cmp -s "$1.$f" "$2.$f" || { echo "changed: $f"; exit 1; }; done; }

# a live function that differs from the recorded one: each migration raises, the forward recovery raises, and nothing at all is applied
RF=${DB}_refuse
for pair in "$M1|$FIRE" "$M1|$VAL" "$M2|$ENQ"; do
  mig=${pair%%|*}; target=${pair#*|}
  dropdb --if-exists $RF >/dev/null 2>&1; createdb -T $DB $RF
  psql -X -q -d $RF -v ON_ERROR_STOP=1 -c "do \$\$ begin execute regexp_replace(pg_get_functiondef('$target'::regprocedure), '-- provider-description', '-- changed by hand provider-description'); end \$\$" >/dev/null
  [ "$(psql -X -d $RF -Atc "select md5(prosrc) from pg_proc where oid = '$target'::regprocedure")" != "${LIVE[$target]}" ] || { echo "the hand change did not change $target"; exit 1; }
  rb=$( (psql -X -d $RF -Atc "$FNS" | sort | md5sum; psql -X -d $RF -Atc "$SET" | sort | md5sum; psql -X -d $RF -Atc "select to_regprocedure('$SETTLE') is null") )
  OUT=$(psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $mig 2>&1) && { echo "$mig applied over a changed $target"; exit 1; }
  grep -qF "differs from the definition this change edits" <<<"$OUT" || { echo "the refusal is not the expected one: $OUT" | tail -3; exit 1; }
  ra=$( (psql -X -d $RF -Atc "$FNS" | sort | md5sum; psql -X -d $RF -Atc "$SET" | sort | md5sum; psql -X -d $RF -Atc "select to_regprocedure('$SETTLE') is null") )
  [ "$rb" = "$ra" ] || { echo "the refused migration changed something ($target)"; exit 1; }
  rec=$R1; [ "$mig" = "$M2" ] && rec=$R2
  OUT=$(psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $rec 2>&1) && { echo "the forward recovery ran over a changed $target"; exit 1; }
  grep -qF "differs from both texts this recovery knows" <<<"$OUT" || { echo "the recovery refusal is not the expected one: $OUT" | tail -3; exit 1; }
done
dropdb --if-exists $RF >/dev/null 2>&1
echo "refused: a hand-changed live fire, validator and enqueue are each refused by the migration that edits them and by its forward recovery, and nothing is applied (no function, setting or new function)"

# 20261110140000: the fire and the validator go from the recorded live md5 to the recorded after md5; one function is added; nothing else changes; a second run is a no-op
snap "$W/0"
OUT=$($P -1 -At -f $M1 2>&1) || { echo "$OUT" | tail -8; exit 1; }
for sig in "$FIRE" "$VAL"; do grep -qF "$sig: applied" <<<"$OUT" || { echo "$sig was not edited"; echo "$OUT" | tail -8; exit 1; }; done
[ "$(q "select md5(prosrc) from pg_proc where oid = '$FIRE'::regprocedure")" = $FIRE_AFTER ] && [ "$(q "select md5(prosrc) from pg_proc where oid = '$VAL'::regprocedure")" = $VAL_AFTER ] && [ "$(q "select md5(prosrc) from pg_proc where oid = '$SETTLE'::regprocedure")" = $SETTLE_AFTER ] || { echo "the fire, the validator or the settlement has not the recorded body md5"; exit 1; }
for want in "$FIRE $FIRE_BEFORE -> $FIRE_AFTER" "$VAL $VAL_BEFORE -> $VAL_AFTER" "$SETTLE (new) -> $SETTLE_AFTER"; do grep -qF -- "--   $want" $M1 || { echo "the migration header does not record: $want"; exit 1; }; done
snap "$W/1"
want=$(printf '%s\n' "$FIRE" "security.provider_description_validate_v1(uuid,text,timestamp with time zone,jsonb)" | sort) # regprocedure prints timestamptz in full
changed=$(comm -23 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//' | sort)
[ "$changed" = "$want" ] || { echo "the changed functions differ from the edited ones"; diff <(echo "$want") <(echo "$changed"); exit 1; }
added=$(comm -13 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//' | sort | comm -23 - <(echo "$want"))
[ "$added" = "security.provider_description_settle_abandoned_v1()" ] || { echo "the added function is not just the settlement: $added"; exit 1; }
[ -z "$(comm -23 "$W/0.set" "$W/1.set" || true)" ] && [ -z "$(comm -13 "$W/0.set" "$W/1.set" || true)" ] || { echo "the migration changed a setting value or added a setting"; exit 1; }
[ "$(q "select count(*) from pipeline.platform_toolset_settings where key in ('pdesc.queue_cap', 'pdesc.read_cost_floor_usd') and used_by like '%provider_description_settle_abandoned_v1%'")" = 2 ] || { echo "the used_by lines do not name the settlement"; exit 1; }
same "$W/0" "$W/1" l4 rd led adm cron desc cat
[ -n "$(q "select obj_description('$SETTLE'::regprocedure, 'pg_proc')")" ] || { echo "the new function has no comment"; exit 1; }
OUT=$($P -1 -At -f $M1 2>&1) || { echo "$OUT" | tail -8; exit 1; }
for sig in "$FIRE" "$VAL"; do grep -qF "$sig: already applied" <<<"$OUT" || { echo "the second run was not a no-op for $sig"; exit 1; }; done
snap "$W/2"; same "$W/1" "$W/2" fn set l4 rd led adm cron desc cat
echo "migration 20261110140000: the fire and the validator go from the recorded live md5 to the recorded after md5, the settlement is added (1 function, comment, no grant to anon or authenticated), the used_by of 2 settings names it, no setting value, read, ledger row, admission, description, job or catalogue row changed; applied again: no change"

# the privileges, the settlement and the fire (every block rolls back)
check "settlement scenarios" "$(run_scen $F/scenarios.sql)" $F/expected.txt
snap "$W/3"; same "$W/2" "$W/3" fn set l4 rd led adm cron desc cat
echo "settlement: $(wc -l < $F/expected.txt) scenarios as expected (cost at the dearer of the floor and the observed cost of a read, capped by the reservation; ledger row written by the existing trigger; a live lease untouched; idempotent; bounded by pdesc.queue_cap, oldest first; the ceiling budget the stuck reservations used is free again; the fire requeues an expired reading read and gives its try back; no privilege for anon or authenticated) and every block rolled back"
check "duplicate scenarios (after)" "$(run_scen $F/duplicate-scenarios.sql)" $F/expected-duplicate.txt
echo "duplicate test: the same $(wc -l < $F/expected-duplicate.txt) results after the change as before it (a copy, a close copy, other case and punctuation, just under the share, a longer text, the share setting at and just above the similarity, the closest of two, a waiting proposal, and the count never below the true overlap)"
check "sentence-filter scenarios" "$(psql -X -d "$DB" -Atq -f tests/fixtures/pdesc-sentence-filter/scenarios.sql 2>&1 | grep -v '^$' | sed -E 's/^[0-9a-f]{8}-[0-9a-f-]{27}\|/<id>|/' || true)" tests/fixtures/pdesc-sentence-filter/expected.txt
echo "earlier: the sentence-filter scenarios give the same result with the new validator and fire"

# 20261110141000: the enqueue only
snap "$W/4"
OUT=$($P -1 -At -f $M2 2>&1) || { echo "$OUT" | tail -8; exit 1; }
grep -qF "$ENQ: applied" <<<"$OUT" || { echo "$ENQ was not edited"; exit 1; }
[ "$(q "select md5(prosrc) from pg_proc where oid = '$ENQ'::regprocedure")" = $ENQ_AFTER ] || { echo "the enqueue has not the recorded body md5"; exit 1; }
grep -qF -- "--   $ENQ $ENQ_BEFORE -> $ENQ_AFTER" $M2 || { echo "the migration header does not record the enqueue md5"; exit 1; }
snap "$W/5"
[ "$(comm -23 "$W/4.fn" "$W/5.fn" | sed 's/ [0-9a-f]*$//')" = "$ENQ" ] && [ -z "$(comm -13 "$W/4.fn" "$W/5.fn" | sed 's/ [0-9a-f]*$//' | grep -vxF "$ENQ" || true)" ] || { echo "the migration changed more than the enqueue"; exit 1; }
same "$W/4" "$W/5" set l4 rd led adm cron desc cat
OUT=$($P -1 -At -f $M2 2>&1) || { echo "$OUT" | tail -8; exit 1; }
grep -qF "$ENQ: already applied" <<<"$OUT" || { echo "the second run was not a no-op"; exit 1; }
snap "$W/6"; same "$W/5" "$W/6" fn set l4 rd led adm cron desc cat
echo "migration 20261110141000: the enqueue goes from the recorded live md5 to the recorded after md5, nothing else is added or changed; applied again: no change"
check "gate scenarios (after)" "$(run_scen $F/gate-scenarios.sql)" $F/expected-gate.txt
snap "$W/7"; same "$W/6" "$W/7" fn set l4 rd led adm cron desc cat
echo "gate: $(wc -l < $F/expected-gate.txt) scenarios as expected (a full queue of missing-description reads no longer stops the upgrade lane; the lane's own queue is bounded by pdesc.queue_per_run and pdesc.queue_cap; the switch still decides; an edited profile is not counted) and every block rolled back"
for S in pdesc-basic-upgrade pdesc-machine; do
  OUT=$(psql -X -d "$DB" -v ON_ERROR_STOP=1 -f tests/fixtures/$S/scenarios.sql 2>&1 | grep -aE '^[a-z0-9_]+\|') || { echo "the earlier $S scenarios failed"; exit 1; }
  [ "$OUT" = "$(cat tests/fixtures/$S/expected.txt)" ] || { echo "the earlier $S scenarios differ after the migrations:"; diff tests/fixtures/$S/expected.txt <(echo "$OUT"); exit 1; }
  echo "earlier: the $(wc -l < tests/fixtures/$S/expected.txt) $S scenarios give the same result after the migrations"
done

# forward recoveries: the earlier bodies return byte for byte, the behaviour returns, they are repeatable, and the migrations apply again afterwards
snap "$W/pre"
$P -1 -At -f $R2 >/dev/null || { echo "the gate forward recovery failed"; exit 1; }
[ "$(q "select md5(prosrc) from pg_proc where oid = '$ENQ'::regprocedure")" = $ENQ_BEFORE ] || { echo "the gate recovery did not restore the enqueue byte for byte"; exit 1; }
check "gate scenarios (after the gate recovery)" "$(run_scen $F/gate-scenarios.sql)" $F/expected-gate-before.txt
$P -1 -At -f $R2 >/dev/null || { echo "the gate forward recovery is not repeatable"; exit 1; }
$P -1 -At -f $R1 >/dev/null || { echo "the settlement forward recovery failed"; exit 1; }
[ "$(q "select md5(prosrc) from pg_proc where oid = '$FIRE'::regprocedure")" = $FIRE_BEFORE ] && [ "$(q "select md5(prosrc) from pg_proc where oid = '$VAL'::regprocedure")" = $VAL_BEFORE ] || { echo "the settlement recovery did not restore the fire and the validator byte for byte"; exit 1; }
[ "$(q "select count(*) from pipeline.platform_toolset_settings where used_by like '%provider_description_settle_abandoned_v1%'")" = 0 ] || { echo "the recovery left the used_by lines"; exit 1; }
snap "$W/rec"
same "$W/pre" "$W/rec" set l4 rd led adm cron desc cat
check "duplicate scenarios (after the settlement recovery)" "$(run_scen $F/duplicate-scenarios.sql)" $F/expected-duplicate.txt
$P -1 -At -f $R1 >/dev/null || { echo "the settlement forward recovery is not repeatable"; exit 1; }
OUT=$($P -1 -At -f $M1 2>&1) || { echo "$OUT" | tail -8; exit 1; }
for sig in "$FIRE" "$VAL"; do grep -qF "$sig: applied" <<<"$OUT" || { echo "after the recovery the migration did not apply for $sig"; exit 1; }; done
OUT=$($P -1 -At -f $M2 2>&1) || { echo "$OUT" | tail -8; exit 1; }
grep -qF "$ENQ: applied" <<<"$OUT" || { echo "after the recovery the gate migration did not apply"; exit 1; }
echo "recovery: both forward recoveries return the fire, the validator and the enqueue to the live md5 byte for byte (settings values, reads, ledger, admissions and descriptions untouched; the settlement function stays, unused); repeatable; the migrations apply again afterwards"
echo "pdesc-reservation-settlement: done"
