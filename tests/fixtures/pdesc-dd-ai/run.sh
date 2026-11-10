#!/usr/bin/env bash
# Guards: Platform Admin order 10 Nov 2026 12:07 (Data Delivery shows the provider-description AI cost, remaining allowance and the Basic -> Enriched outcome): migration 20261110150000 adds security.data_delivery_pdesc_v1 (read only, Admin only) and edits only security.data_delivery_v1 (one new key, provider_ai, for the stream pdesc), md5-guarded; it refuses and changes nothing when the live Data Delivery function is not the recorded one; applying it twice changes nothing; the held forward recovery returns data_delivery_v1 to the live text byte for byte; the counts behave as scenarios.sql says (spend, reservations, remaining allowance, estimated settlements, admitted routes, upgrade reads) and the worker's identity.seen is stored by the record function.
# Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds the database with the pdesc-sentence-filter harness (which builds on the pdesc-machine harness), loads the live security.data_delivery_v1 (live/, body md5 b67bd181c58546076da48e7b5f00a2a4, read 10 Nov 2026), then applies the migration twice. Drops the database at the end (PDDA_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
export LC_ALL=C # fixed: one byte order for sort and comm, whatever the runner's locale
DB=${PDDA_DB:-g_pdesc_dd_ai}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
M=supabase/migrations/20261110150000_cf247_dd_provider_ai_allowance.sql
R=supabase/held/dd_provider_ai_allowance_forward_recovery.sql
F=tests/fixtures/pdesc-dd-ai
DDV='security.data_delivery_v1()'; PD='security.data_delivery_pdesc_v1()'
DDV_BEFORE=b67bd181c58546076da48e7b5f00a2a4; DDV_AFTER=849453412a8b9a448118e7b87362752a; PD_AFTER=15b2f9882e77d7fcf0a8a4be2b6df18f
q() { psql -X -d "$DB" -Atc "$1"; }
BASE=$(PDSF_KEEP=1 PDSF_DB=$DB bash tests/fixtures/pdesc-sentence-filter/run.sh 2>&1) || { echo "$BASE" | tail -15; echo "the base harness failed"; exit 1; }
echo "base: pdesc-sentence-filter harness built the database (20261109020000 to 20261110120000 as the harness applies them)"
W=$(mktemp -d); trap 'rm -rf "$W"; [ -n "${PDDA_KEEP:-}" ] || { dropdb --if-exists '$DB' >/dev/null 2>&1; dropdb --if-exists '${DB}_refuse' >/dev/null 2>&1; }' EXIT
$P -f $F/live/security.data_delivery_v1.sql
[ "$(q "select md5(prosrc) from pg_proc where oid = '$DDV'::regprocedure")" = $DDV_BEFORE ] || { echo "the loaded $DDV differs from live $DDV_BEFORE"; exit 1; }
echo "loaded: security.data_delivery_v1 = live (body md5 $DDV_BEFORE, read 10 Nov 2026)"

FNS="select p.oid::regprocedure::text || ' ' || md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public', 'api') and p.prokind = 'f' order by 1"
SET="select key || '=' || value::text from pipeline.platform_toolset_settings order by 1"
snap() { q "$FNS" | sort > "$1.fn"; q "$SET" | sort > "$1.set"; q "select count(*) from pipeline.layer4_review_items" > "$1.l4"; q "select md5(string_agg(r::text, '|' order by r.id)) from pipeline.provider_description_reads r" > "$1.rd"; q "select count(*) from pipeline.ai_spend_ledger" > "$1.led"; q "select count(*) from pipeline.provider_description_machine_admissions" > "$1.adm"; q "select md5(string_agg(p.description, '|' order by p.id)) from catalogue.providers p" > "$1.desc"; }
same() { for f in "${@:3}"; do cmp -s "$1.$f" "$2.$f" || { echo "changed: $f"; exit 1; }; done; }

# a live data_delivery_v1 that differs from the recorded one: the migration raises, the forward recovery raises, and nothing at all is applied
RF=${DB}_refuse
dropdb --if-exists $RF >/dev/null 2>&1; createdb -T $DB $RF
psql -X -q -d $RF -v ON_ERROR_STOP=1 -c "do \$\$ begin execute replace(pg_get_functiondef('$DDV'::regprocedure), 'v_ui int :=', 'v_ui int := 0 + '); end \$\$" >/dev/null
[ "$(psql -X -d $RF -Atc "select md5(prosrc) from pg_proc where oid = '$DDV'::regprocedure")" != $DDV_BEFORE ] || { echo "the hand change did not change $DDV"; exit 1; }
rb=$( (psql -X -d $RF -Atc "$FNS" | sort | md5sum; psql -X -d $RF -Atc "select to_regprocedure('$PD') is null") )
OUT=$(psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $M 2>&1) && { echo "$M applied over a changed $DDV"; exit 1; }
grep -qF "differs from the definition this change edits" <<<"$OUT" || { echo "the refusal is not the expected one: $OUT" | tail -3; exit 1; }
ra=$( (psql -X -d $RF -Atc "$FNS" | sort | md5sum; psql -X -d $RF -Atc "select to_regprocedure('$PD') is null") )
[ "$rb" = "$ra" ] || { echo "the refused migration changed something"; exit 1; }
OUT=$(psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $R 2>&1) && { echo "the forward recovery ran over a changed $DDV"; exit 1; }
grep -qF "differs from both texts this recovery knows" <<<"$OUT" || { echo "the recovery refusal is not the expected one: $OUT" | tail -3; exit 1; }
dropdb --if-exists $RF >/dev/null 2>&1
echo "refused: a hand-changed live Data Delivery function is refused by the migration and by its forward recovery, and nothing is applied (no function added)"

# the migration: data_delivery_v1 goes from the recorded live md5 to the recorded after md5; one function is added; nothing else changes; a second run is a no-op
snap "$W/0"
OUT=$($P -1 -At -f $M 2>&1) || { echo "$OUT" | tail -8; exit 1; }
[ "$(q "select md5(prosrc) from pg_proc where oid = '$DDV'::regprocedure")" = $DDV_AFTER ] && [ "$(q "select md5(prosrc) from pg_proc where oid = '$PD'::regprocedure")" = $PD_AFTER ] || { echo "the migration did not leave the recorded md5s"; exit 1; }
for want in "$DDV $DDV_BEFORE -> $DDV_AFTER" "$PD (new) -> $PD_AFTER"; do grep -qF -- "--   $want" $M || { echo "the migration header does not record: $want"; exit 1; }; done
snap "$W/1"
changed=$(comm -23 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//' | sort); added=$(comm -13 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//' | sort)
[ "$changed" = "$DDV" ] || { echo "functions changed other than $DDV: $changed"; exit 1; }
[ "$added" = "$(printf '%s\n' "$DDV" "$PD" | sort)" ] || { echo "unexpected functions added or edited: $added"; exit 1; }
same "$W/0" "$W/1" set l4 rd led adm desc
# only the Data Delivery function's text differs: the edit is one inserted line after the 'stages' key
EDIT=$(diff <(sed 's/\r//' $F/live/security.data_delivery_v1.sql) <(q "select pg_get_functiondef('$DDV'::regprocedure)") | grep -E '^[<>]' || true)
[ "$(grep -c '^<' <<<"$EDIT" || true)" = 0 ] && [ "$(grep -c '^>' <<<"$EDIT")" = 1 ] && grep -qF "'provider_ai', case when s.stream = 'pdesc' then security.data_delivery_pdesc_v1() end," <<<"$EDIT" || { echo "the edit is not one inserted provider_ai line: $EDIT"; exit 1; }
[ "$(q "select position('''stages'', case when s.stream = ''cdesc'' then security.data_delivery_cdesc_stages_v1() end,' in prosrc) > 0 and position('data_delivery_pdesc_v1' in prosrc) > position('data_delivery_cdesc_stages_v1' in prosrc) from pg_proc where oid = '$DDV'::regprocedure")" = t ] || { echo "the provider_ai key does not follow the stages key"; exit 1; }
OUT=$($P -1 -At -f $M 2>&1) || { echo "$OUT" | tail -8; exit 1; }
snap "$W/2"; same "$W/1" "$W/2" fn set l4 rd led adm desc
echo "migration 20261110150000: Data Delivery goes from the recorded live md5 to the recorded after md5 (one inserted line, the key provider_ai after stages), one function is added (read only, no grant to anon or authenticated), no setting, read, ledger row, admission or description changed; applied again: no change"

# the scenarios
check() { # name, got, expected file
  grep -q 'ERROR' <<<"$2" && { echo "$1 failed:"; echo "$2" | grep ERROR | head -3; exit 1; }
  [ "$2" = "$(cat "$3")" ] || { echo "$1 differs from $3:"; diff "$3" <(echo "$2"); exit 1; }
}
GOT=$(psql -X -d $DB -Atq -f $F/scenarios.sql 2>&1 | grep -aE '^([a-z0-9_]+\||.*ERROR)' || true)
check "scenarios" "$GOT" $F/expected.txt
echo "scenarios: $(wc -l < $F/expected.txt) as expected (spend and reservations, remaining allowance floored at 0, the daily guard, estimated settlements, admitted by route, upgrade reads, a count that cannot be made, read only, speed at the live size, and the worker's identity.seen stored by the record function)"

# the forward recovery returns the Data Delivery function to the live text, byte for byte, and leaves the new function; repeatable; the migration applies again after it
$P -1 -At -f $R >/dev/null
[ "$(q "select md5(prosrc) from pg_proc where oid = '$DDV'::regprocedure")" = $DDV_BEFORE ] || { echo "the recovery did not restore $DDV"; exit 1; }
[ "$(q "select pg_get_functiondef('$DDV'::regprocedure)")" = "$(cat $F/live/security.data_delivery_v1.sql | sed 's/\r//')" ] || { echo "the restored definition is not the live definition byte for byte"; exit 1; }
[ "$(q "select to_regprocedure('$PD') is not null")" = t ] || { echo "the recovery removed the new function"; exit 1; }
$P -1 -At -f $R >/dev/null
$P -1 -At -f $M >/dev/null
[ "$(q "select md5(prosrc) from pg_proc where oid = '$DDV'::regprocedure")" = $DDV_AFTER ] || { echo "the migration did not apply again after the recovery"; exit 1; }
snap "$W/3"; same "$W/1" "$W/3" fn set l4 rd led adm desc
echo "recovery: the forward recovery returns security.data_delivery_v1 to the live definition byte for byte (the new function stays, unused), is repeatable, and the migration applies again after it"
echo "pdesc-dd-ai: done"
