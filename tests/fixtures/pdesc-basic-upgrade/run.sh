#!/usr/bin/env bash
# Guards: F-PDESC P0 (Platform Admin directive, 9 Nov 2026: unique, source-backed university descriptions): migration 20261110040000 edits only the five live definitions it records (checked by the md5 of each function body, the same text on PostgreSQL 16 and 17, and it refuses and changes nothing when a live function differs),
# keeps an admitted register-fact profile eligible for source-backed enrichment only while pdesc.registry_upgrade_on is 1 (created OFF), upgrades it only from a quote-verified official page by the machine rule, never touches a provider with a lock, an earlier rejection, a withdrawal or a text a person changed,
# keeps the prior version (admission record, superseded read, restore by withdrawal), holds queued reads that cannot pass the identity test, adds one setting (the switch, created OFF) and one function and changes no other setting, ceiling, job, Layer 4 item, read or description by itself; the forward recovery returns the five bodies byte for byte.
# Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds the database with the pdesc-lease-record-timeouts harness (which builds on pdesc-claim-context and applies 20261109182000, 20261109185000 and 20261109233000), runs the scenarios. PDBU_KEEP=1 keeps the databases.
set -euo pipefail
cd "$(dirname "$0")/../../.."
export LC_ALL=C # fixed: one byte order for sort and comm, whatever the runner's locale
DB=${PDBU_DB:-g_pdesc_basicupg}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
MIG=supabase/migrations/20261110040000_cf247_pdesc_basic_profile_upgrade.sql
REC=supabase/held/pdesc_basic_profile_upgrade_forward_recovery.sql
F=tests/fixtures/pdesc-basic-upgrade
q() { psql -X -d "$DB" -Atc "$1"; }
BASE=$(PDLRT_KEEP=1 PDLRT_DB=$DB bash tests/fixtures/pdesc-lease-record-timeouts/run.sh 2>&1) || { echo "$BASE" | tail -15; echo "the base harness failed"; exit 1; }
echo "base: pdesc-lease-record-timeouts harness built the database (20261109020000, 20261109030000, 20261109120000, 20261109182000, 20261109185000 and 20261109233000 applied)"
W=$(mktemp -d); trap 'rm -rf "$W"; [ -n "${PDBU_KEEP:-}" ] || { dropdb --if-exists '$DB' >/dev/null 2>&1; dropdb --if-exists '${DB}_refuse' >/dev/null 2>&1; }' EXIT

# the edited functions are the live ones (md5 of the function body, pg_proc.prosrc, read 9 Nov 2026 UTC, project fxcwkweaxjtknorudmwp)
declare -A LIVE=( ['security.provider_description_machine_blocked_v1(uuid)']=46634e38c0469cbcbd6c23158dfadc94 ['security.provider_description_machine_admit_v1(uuid)']=5decbd99c8ecd5e0b072d22ed6f68962
  ['security.provider_description_selection_v1(jsonb)']=04acb9419b9965b5d6aab420059c7e84 ['security.provider_description_enqueue_v1()']=803478538da3dd9594ba08be38284c3e ['public.svc_provider_description_next(integer)']=7583808609dc2dea1d3fc251607405a1 )
for sig in "${!LIVE[@]}"; do
  [ "$(q "select md5(prosrc) from pg_proc where oid = '$sig'::regprocedure")" = "${LIVE[$sig]}" ] || { echo "the loaded $sig differs from live ${LIVE[$sig]}"; exit 1; }
done
echo "loaded: the five functions = live (body md5 recorded in the migration header)"

FNS="select p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public', 'api') and p.prokind = 'f' order by 1"
SET="select key || '=' || value::text from pipeline.platform_toolset_settings order by 1"
snap() { q "$FNS" | sort > "$1.fn"; q "$SET" | sort > "$1.set"; q "select count(*) from pipeline.layer4_review_items" > "$1.l4"; q "select count(*) from pipeline.provider_description_reads" > "$1.rd"; q "select count(*) from catalogue.providers where nullif(btrim(description), '') is not null" > "$1.desc"; q "select count(*) from pipeline.provider_description_machine_admissions" > "$1.adm"; q "select count(*) from cron.job" > "$1.cron"; q "select count(*) from pipeline.automation_catalogue" > "$1.cat" 2>/dev/null || echo none > "$1.cat"; }

# a live function that differs from the recorded one: the migration raises, and nothing at all is applied (the whole migration is one transaction)
for target in 'security.provider_description_machine_admit_v1(uuid)' 'public.svc_provider_description_next(integer)'; do
  RF=${DB}_refuse
  dropdb --if-exists $RF >/dev/null 2>&1; createdb -T $DB $RF
  psql -X -q -d $RF -v ON_ERROR_STOP=1 -c "do \$\$ begin execute regexp_replace(pg_get_functiondef('$target'::regprocedure), 'begin', 'begin /* changed by hand */'); end \$\$" >/dev/null
  rb=$( (psql -X -d $RF -Atc "$FNS" | sort | md5sum; psql -X -d $RF -Atc "$SET" | sort | md5sum; psql -X -d $RF -Atc "select to_regprocedure('security.provider_description_basic_profile_v1(uuid)') is null") )
  OUT=$(psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $MIG 2>&1) && { echo "the migration applied over a changed $target"; exit 1; }
  grep -qF "differs from the definition this change edits" <<<"$OUT" || { echo "the refusal is not the expected one: $OUT" | tail -3; exit 1; }
  ra=$( (psql -X -d $RF -Atc "$FNS" | sort | md5sum; psql -X -d $RF -Atc "$SET" | sort | md5sum; psql -X -d $RF -Atc "select to_regprocedure('security.provider_description_basic_profile_v1(uuid)') is null") )
  [ "$rb" = "$ra" ] || { echo "the refused migration changed something ($target)"; exit 1; }
  dropdb --if-exists $RF >/dev/null 2>&1
done
echo "refused: a hand-changed live machine admission and a hand-changed live lease are each refused ('differs from the definition this change edits') and nothing is applied (no function, setting or new function)"

# apply: the five functions go from the recorded live md5 to the recorded after md5; one function and one setting are added; nothing else changes; a second run is a no-op
snap "$W/0"
OUT=$($P -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -8; exit 1; }
for sig in "${!LIVE[@]}"; do
  grep -qF "$sig: applied" <<<"$OUT" || { echo "$sig was not edited"; echo "$OUT" | tail -8; exit 1; }
  after=$(grep -F -- "--   $sig " $MIG | head -1 | sed 's/.*-> *\([0-9a-f]*\).*/\1/')
  [ "$(q "select md5(prosrc) from pg_proc where oid = '$sig'::regprocedure")" = "$after" ] || { echo "$sig after the change differs from the recorded $after"; exit 1; }
done
snap "$W/1"
want=$(for sig in "${!LIVE[@]}"; do echo "${sig#public.}"; done | sort) # regprocedure prints a public function without its schema
changed=$(comm -23 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//' | sort)
[ "$changed" = "$want" ] || { echo "the changed functions differ from the edited ones"; diff <(echo "$want") <(echo "$changed"); exit 1; }
added=$(comm -13 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//' | sort | comm -23 - <(echo "$want"))
[ "$added" = "security.provider_description_basic_profile_v1(uuid)" ] || { echo "the added function is not just the profile rule: $added"; exit 1; }
lost=$(comm -23 "$W/0.set" "$W/1.set" || true)
[ -z "$lost" ] || { echo "the migration changed setting values: $lost"; exit 1; }
newset=$(comm -13 "$W/0.set" "$W/1.set" | sed 's/=.*//' | sort | tr '\n' ' ')
[ "$newset" = 'pdesc.registry_upgrade_on ' ] || { echo "the only new setting should be pdesc.registry_upgrade_on: $newset"; exit 1; }
[ "$(q "select value::text from pipeline.platform_toolset_settings where key = 'pdesc.registry_upgrade_on'")" = 0 ] || { echo "the upgrade switch was not created OFF"; exit 1; }
for f in l4 rd desc adm cron cat; do cmp -s "$W/0.$f" "$W/1.$f" || { echo "the migration changed $f"; exit 1; }; done
[ -n "$(q "select obj_description('security.provider_description_basic_profile_v1(uuid)'::regprocedure, 'pg_proc')")" ] || { echo "the new function has no comment"; exit 1; }
OUT=$($P -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -8; exit 1; }
for sig in "${!LIVE[@]}"; do grep -qF "$sig: already applied" <<<"$OUT" || { echo "the second run was not a no-op for $sig"; exit 1; }; done
snap "$W/2"; for f in fn set l4 rd desc adm cron cat; do cmp -s "$W/1.$f" "$W/2.$f" || { echo "the second run changed $f"; exit 1; }; done
echo "migration: 5 edits from the recorded live md5 to the recorded after md5; 1 function and 1 setting added (pdesc.registry_upgrade_on created OFF), no value changed; no Layer 4 item, read, admission, description, job or catalogue row changed; applied again: no change"

# the scenarios
OUT=$(psql -X -d "$DB" -v ON_ERROR_STOP=1 -f $F/scenarios.sql 2>&1 | grep -E '^[a-z0-9_]+\|') || { echo "the scenarios failed"; psql -X -d "$DB" -v ON_ERROR_STOP=1 -f $F/scenarios.sql 2>&1 | tail -8; exit 1; }
if [ "$OUT" != "$(cat $F/expected.txt)" ]; then echo "the scenarios differ from $F/expected.txt:"; diff <(cat $F/expected.txt) <(echo "$OUT"); exit 1; fi
echo "scenarios: $(echo "$OUT" | wc -l) results match $F/expected.txt"
snap "$W/3"; for f in fn set l4 rd desc adm cron cat; do cmp -s "$W/2.$f" "$W/3.$f" || { echo "the scenarios left a change behind ($f)"; exit 1; }; done
echo "scenarios: every block rolled back (no function, setting, Layer 4 item, read, admission, description or job left behind)"

# the earlier scenarios give the same result with the migration applied (switch off: the reader is as before)
for S in pdesc-machine pdesc-claim-context; do
  OUT=$(psql -X -d "$DB" -v ON_ERROR_STOP=1 -f tests/fixtures/$S/scenarios.sql 2>&1 | grep -E '^[a-z0-9_]+\|') || { echo "the earlier $S scenarios failed"; exit 1; }
  if [ "$OUT" != "$(cat tests/fixtures/$S/expected.txt)" ]; then echo "the earlier $S scenarios differ after the migration:"; diff <(cat tests/fixtures/$S/expected.txt) <(echo "$OUT"); exit 1; fi
  echo "earlier: the $(echo "$OUT" | wc -l) $S scenarios give the same result after the migration"
done
run_scen() { psql -X -d "$DB" -f "$1" 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\):  //p'; }
strip() { sed 's/ digest=[0-9a-f]*$//'; }
for S in pdesc-lease-record-timeouts pdesc-lease-one-pass; do
  GOT=$(run_scen tests/fixtures/$S/scenarios.sql); echo "$GOT" | grep -q '^ERROR' && { echo "$GOT"; exit 1; }
  [ "$(echo "$GOT" | strip)" = "$(cat tests/fixtures/$S/expected.txt)" ] || { echo "the earlier $S scenarios differ after the migration:"; diff <(cat tests/fixtures/$S/expected.txt) <(echo "$GOT" | strip); exit 1; }
  echo "earlier: the $(wc -l < tests/fixtures/$S/expected.txt) $S scenarios give the same items, order and results after the migration"
done
OUT=$(psql -X -d "$DB" -v ON_ERROR_STOP=1 -f tests/fixtures/pdesc-retry-funnel/scenarios.sql 2>&1 | grep -E '\|') || { echo "the retry-funnel scenarios failed"; exit 1; }
echo "$OUT" | grep -q 'held_same_copy|unchanged_unsuitable_evidence' && echo "$OUT" | grep -q 'held_new_copy|eligible' || { echo "the retry-funnel behaviour changed: $OUT"; exit 1; }
echo "earlier: a held read on the same copy stays parked and one on a changed copy is retried (pdesc-retry-funnel)"

# forward recovery: the five bodies return byte for byte, the settings and the profile rule stay, and the migration can be applied again
snap "$W/pre"
$P -1 -At -f $REC >/dev/null || { echo "the forward recovery failed"; exit 1; }
for sig in "${!LIVE[@]}"; do
  [ "$(q "select md5(prosrc) from pg_proc where oid = '$sig'::regprocedure")" = "${LIVE[$sig]}" ] || { echo "$sig after the forward recovery differs from live ${LIVE[$sig]}"; exit 1; }
done
snap "$W/4"
[ "$(cat "$W/4.set")" = "$(cat "$W/pre.set")" ] || { echo "the forward recovery changed settings"; exit 1; }
for f in l4 rd desc adm cron cat; do cmp -s "$W/pre.$f" "$W/4.$f" || { echo "the forward recovery changed $f"; exit 1; }; done
$P -1 -At -f $REC >/dev/null || { echo "the forward recovery is not repeatable"; exit 1; }
OUT=$($P -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -8; exit 1; }
for sig in "${!LIVE[@]}"; do grep -qF "$sig: applied" <<<"$OUT" || { echo "after the recovery the migration did not apply for $sig"; exit 1; }; done
echo "recovery: the five bodies return to the live md5 byte for byte (settings, reads, admissions and descriptions untouched); repeatable; the migration applies again afterwards"
echo "pdesc-basic-upgrade: done"
