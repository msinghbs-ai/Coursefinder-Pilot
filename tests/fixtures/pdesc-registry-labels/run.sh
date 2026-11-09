#!/usr/bin/env bash
# Guards: F-PDESC Directive 3 (Platform Admin, 9 Nov 2026): migration 20261109180000 edits only the two live definitions it records (checked by the md5 of the function body, the same text on PostgreSQL 16 and 17, and it refuses and changes nothing when a live function differs),
# stops the machine text rule declining a register-fact profile for the catalogue's own course labels ("Employment Skills Programmes", "Non AQF Award") while outcome, award and ranking claims are still refused, does not state a city that lost a character,
# looks at a machine-text hold again once when the text rule changed (through the existing registry tier and machine admission only), and changes no setting, ceiling, job, Layer 4 item, read or description by itself.
# Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds the database with the pdesc-claim-context harness (which builds on pdesc-machine and applies 20261109020000, 20261109030000 and 20261109120000), applies the migration twice, runs the scenarios. PDRL_KEEP=1 keeps the databases.
set -euo pipefail
cd "$(dirname "$0")/../../.."
export LC_ALL=C # fixed: one byte order for sort and comm, whatever the runner's locale
DB=${PDRL_DB:-g_pdesc_labels}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
MIG=supabase/migrations/20261109180000_cf247_pdesc_registry_label_words.sql
F=tests/fixtures/pdesc-registry-labels
q() { psql -X -d "$DB" -Atc "$1"; }
BASE=$(PDCC_KEEP=1 PDCC_DB=$DB bash tests/fixtures/pdesc-claim-context/run.sh 2>&1) || { echo "$BASE" | tail -15; echo "the base harness failed"; exit 1; }
echo "base: pdesc-claim-context harness built the database (20261109020000, 20261109030000 and 20261109120000 applied)"
W=$(mktemp -d); trap 'rm -rf "$W"; [ -n "${PDRL_KEEP:-}" ] || { dropdb --if-exists '$DB' >/dev/null 2>&1; dropdb --if-exists '${DB}_refuse' >/dev/null 2>&1; dropdb --if-exists '${DB}_pre' >/dev/null 2>&1; }' EXIT

# the edited functions are the live ones (md5 of the function body, pg_proc.prosrc, read 9 Nov 2026, project fxcwkweaxjtknorudmwp)
declare -A LIVE=( ['security.provider_description_registry_profile_v1(uuid)']=53f35748344bb1bc74b621979724e1b5 ['security.provider_description_registry_tier_v1()']=1f9cbb77a59ab392a2e59b6aff317adb )
for sig in "${!LIVE[@]}"; do
  [ "$(q "select md5(prosrc) from pg_proc where oid = '$sig'::regprocedure")" = "${LIVE[$sig]}" ] || { echo "the loaded $sig differs from live ${LIVE[$sig]}"; exit 1; }
done
echo "loaded: the two functions this change edits = live (body md5 recorded in the migration header)"

# before: the old codes (register wording and code only) refuse the live label "Employment Skills Programmes", as live did
psql -X -q -d "$DB" -c "update pipeline.platform_toolset_settings set value='1' where key='pdesc.machine_admit_on'" >/dev/null
BEFORE=$(q "select security.provider_description_machine_gate_v1(id, 'Fixture College is a college. Its listed courses are in fields including Employment Skills Programmes.', '{\"tier\":\"registry_factual\"}')->>'rule' from catalogue.providers where stable_key='fixture:provider:12'")
psql -X -q -d "$DB" -c "update pipeline.platform_toolset_settings set value='0' where key='pdesc.machine_admit_on'" >/dev/null
[ "$BEFORE" = "machine_text_refused_word" ] || { echo "before the change the label was expected to be refused: $BEFORE"; exit 1; }
echo "before: a register-fact text holding the label 'Employment Skills Programmes' is refused (machine_text_refused_word), as live"

FNS="select p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public', 'api') and p.prokind = 'f' order by 1"
SET="select key || '=' || value::text from pipeline.platform_toolset_settings order by 1"
snap() { q "$FNS" | sort > "$1.fn"; q "$SET" | sort > "$1.set"; q "select count(*) from pipeline.layer4_review_items" > "$1.l4"; q "select count(*) from pipeline.provider_description_reads" > "$1.rd"; q "select count(*) from catalogue.providers where nullif(btrim(description), '') is not null" > "$1.desc"; q "select count(*) from pipeline.provider_description_machine_admissions" > "$1.adm"; (q "select count(*) from cron.job" 2>/dev/null || echo none) > "$1.cron"; }

# a live function that differs from the recorded one: the migration raises, and nothing at all is applied (the whole migration is one transaction)
RF=${DB}_refuse
dropdb --if-exists $RF >/dev/null 2>&1; createdb -T $DB $RF
psql -X -q -d $RF -v ON_ERROR_STOP=1 -c "do \$\$ begin execute regexp_replace(pg_get_functiondef('security.provider_description_registry_tier_v1()'::regprocedure), 'begin', 'begin /* changed by hand */'); end \$\$" >/dev/null
rb=$( (psql -X -d $RF -Atc "$FNS" | sort | md5sum; psql -X -d $RF -Atc "$SET" | sort | md5sum; psql -X -d $RF -Atc "select to_regprocedure('security.pdesc_text_rule_fingerprint_v1()') is null") )
OUT=$(psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $MIG 2>&1) && { echo "the migration applied over a changed live function"; exit 1; }
grep -qF "differs from the definition this change edits" <<<"$OUT" || { echo "the refusal is not the expected one: $OUT" | tail -3; exit 1; }
ra=$( (psql -X -d $RF -Atc "$FNS" | sort | md5sum; psql -X -d $RF -Atc "$SET" | sort | md5sum; psql -X -d $RF -Atc "select to_regprocedure('security.pdesc_text_rule_fingerprint_v1()') is null") )
[ "$rb" = "$ra" ] || { echo "the refused migration changed something"; exit 1; }
dropdb --if-exists $RF >/dev/null 2>&1
echo "refused: a hand-changed live registry tier is refused ('differs from the definition this change edits') and nothing is applied (no function, setting or new function)"

# apply: the two edited functions go from the recorded live md5 to the recorded after md5; one function is added; nothing else changes; a second run is a no-op
snap "$W/0"
OUT=$($P -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -8; exit 1; }
for sig in "${!LIVE[@]}"; do
  grep -qF "$sig: applied" <<<"$OUT" || { echo "$sig was not edited"; echo "$OUT" | tail -8; exit 1; }
  after=$(grep -F -- "--   $sig " $MIG | head -1 | sed 's/.*-> *\([0-9a-f]*\).*/\1/')
  [ "$(q "select md5(prosrc) from pg_proc where oid = '$sig'::regprocedure")" = "$after" ] || { echo "$sig after the change differs from the recorded $after"; exit 1; }
done
snap "$W/1"
want=$(for sig in "${!LIVE[@]}"; do echo "$sig"; done | sort)
changed=$(comm -23 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//' | sort)
# the two edited functions also change their comment only through comment on function (not part of the definition md5), so the changed set is exactly the edited functions
[ "$changed" = "$want" ] || { echo "the changed functions differ from the edited ones"; diff <(echo "$want") <(echo "$changed"); exit 1; }
added=$(comm -13 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//' | sort | comm -23 - <(echo "$want"))
[ "$added" = "security.pdesc_text_rule_fingerprint_v1()" ] || { echo "the added functions are not just the fingerprint: $added"; exit 1; }
cmp -s "$W/0.set" "$W/1.set" || { echo "the migration changed a setting"; diff "$W/0.set" "$W/1.set"; exit 1; }
for f in l4 rd desc adm cron; do cmp -s "$W/0.$f" "$W/1.$f" || { echo "the migration changed $f"; exit 1; }; done
OUT=$($P -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -8; exit 1; }
for sig in "${!LIVE[@]}"; do grep -qF "$sig: already applied" <<<"$OUT" || { echo "the second run was not a no-op for $sig"; exit 1; }; done
snap "$W/2"; for f in fn set l4 rd desc adm cron; do cmp -s "$W/1.$f" "$W/2.$f" || { echo "the second run changed $f"; exit 1; }; done
echo "migration: 2 edit(s) from the recorded live md5 to the recorded after md5; 1 function added; no setting, Layer 4 item, read, admission, description or job changed; applied again: no change"
[ "$(q "select has_function_privilege('anon', 'security.pdesc_text_rule_fingerprint_v1()'::regprocedure, 'execute') or has_function_privilege('authenticated', 'security.pdesc_text_rule_fingerprint_v1()'::regprocedure, 'execute')")" = f ] || { echo "a public role can execute the fingerprint"; exit 1; }
[ -n "$(q "select obj_description('security.pdesc_text_rule_fingerprint_v1()'::regprocedure, 'pg_proc')")" ] || { echo "the fingerprint has no comment"; exit 1; }
echo "grants: the new function is revoked from public, anon and authenticated and carries a comment"

OUT=$(psql -X -d "$DB" -v ON_ERROR_STOP=1 -f $F/scenarios.sql 2>&1 | grep -E '^[a-z0-9_]+\|') || { echo "the scenarios failed"; psql -X -d "$DB" -v ON_ERROR_STOP=1 -f $F/scenarios.sql 2>&1 | tail -8; exit 1; }
if [ "$OUT" != "$(cat $F/expected.txt)" ]; then echo "the scenarios differ from $F/expected.txt:"; diff <(cat $F/expected.txt) <(echo "$OUT"); exit 1; fi
echo "scenarios: $(echo "$OUT" | wc -l) results match $F/expected.txt"

# the earlier machine scenarios and the claim-context scenarios still give the same result with the migration applied
OUT=$(psql -X -d "$DB" -v ON_ERROR_STOP=1 -f tests/fixtures/pdesc-machine/scenarios.sql 2>&1 | grep -E '^[a-z0-9_]+\|') || { echo "the earlier machine scenarios failed"; exit 1; }
if [ "$OUT" != "$(cat tests/fixtures/pdesc-machine/expected.txt)" ]; then echo "the earlier machine scenarios differ after the migration:"; diff <(cat tests/fixtures/pdesc-machine/expected.txt) <(echo "$OUT"); exit 1; fi
echo "earlier: the $(echo "$OUT" | wc -l) pdesc-machine scenarios give the same result after the migration"
OUT=$(psql -X -d "$DB" -v ON_ERROR_STOP=1 -f tests/fixtures/pdesc-claim-context/scenarios.sql 2>&1 | grep -E '^[a-z0-9_]+\|') || { echo "the claim-context scenarios failed"; exit 1; }
if [ "$OUT" != "$(cat tests/fixtures/pdesc-claim-context/expected.txt)" ]; then echo "the claim-context scenarios differ after the migration:"; diff <(cat tests/fixtures/pdesc-claim-context/expected.txt) <(echo "$OUT"); exit 1; fi
echo "earlier: the $(echo "$OUT" | wc -l) pdesc-claim-context scenarios give the same result after the migration"
echo "pdesc-registry-labels: done"
