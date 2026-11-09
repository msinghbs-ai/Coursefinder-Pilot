#!/usr/bin/env bash
# Guards: F-PDESC Directive 3 Blocker A (Platform Admin, 9 Nov 2026): migration 20261109120000 edits only the live definitions it records (checked by the md5 of the function body, the same text on PostgreSQL 16 and 17, and it refuses and changes nothing when a live function differs),
# lets the machine admission rule allow the neutral population words in pdesc.machine_neutral_words only where every sentence that uses one is supported by its exact official quote, keeps refusing ranking, outcome, accreditation, award, facility, superlative, finance, visa and figure claims,
# changes no setting value, Layer 4 item, read, description or job, and re-evaluates declined proposals only through the existing settlement of waiting items.
# Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds the database with the pdesc-machine harness (which builds on the pdesc-self-driving, retry-funnel and autonomy harnesses and applies 20261109020000 and 20261109030000),
# proves the old behaviour, applies the migration twice, then runs the scenarios. Drops the databases at the end (PDCC_KEEP=1 keeps them).
set -euo pipefail
cd "$(dirname "$0")/../../.."
export LC_ALL=C # fixed: one byte order for sort and comm, whatever the runner's locale
DB=${PDCC_DB:-g_pdesc_claimctx}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
MIG=supabase/migrations/20261109120000_cf247_pdesc_claim_word_context.sql
F=tests/fixtures/pdesc-claim-context
q() { psql -X -d "$DB" -Atc "$1"; }
[ -n "${PDCC_KEEP:-}" ] || trap 'dropdb --if-exists '$DB' >/dev/null 2>&1; dropdb --if-exists '${DB}_refuse' >/dev/null 2>&1; dropdb --if-exists '${DB}_scale' >/dev/null 2>&1' EXIT
BASE=$(PDM_KEEP=1 PDM_DB=$DB bash tests/fixtures/pdesc-machine/run.sh 2>&1) || { echo "$BASE" | tail -15; echo "the base harness failed"; exit 1; }
echo "base: pdesc-machine harness built the database (20261109020000 and 20261109030000 applied)"

# the edited functions are the live ones (md5 of the function body, pg_proc.prosrc, read 9 Nov 2026, project fxcwkweaxjtknorudmwp)
declare -A LIVE=( ['security.pdesc_machine_text_check_v1(uuid,text,text[])']=d432bc25734a4e6cab634f4b709ad8e5 ['security.provider_description_machine_gate_v1(uuid,text,jsonb)']=60cb6d649d95f63e99b6e6a90db62810
                  ['security.provider_description_machine_admit_v1(uuid)']=3a13bb31181106c9b128c4c905f7b874 ['public.svc_provider_description_record(jsonb)']=3114f845b25fc31ed97eaab0f56ee297 )
for sig in "${!LIVE[@]}"; do
  [ "$(q "select md5(prosrc) from pg_proc where oid = '$sig'::regprocedure")" = "${LIVE[$sig]}" ] || { echo "the loaded $sig differs from live ${LIVE[$sig]}"; exit 1; }
done
echo "loaded: the four functions this change edits = live (body md5 recorded in the migration header)"

# before: the strict rule refuses the neutral sentence, as live did on 9 Nov 2026
psql -X -q -d "$DB" -c "update pipeline.platform_toolset_settings set value='1' where key='pdesc.machine_admit_on'" >/dev/null # scratch database only: switched back below
BEFORE=$(psql -X -d "$DB" -Atc "select security.provider_description_machine_gate_v1(id, 'The university''s essence is found in its students, staff, alumni and donors.', '{\"tier\":\"stored\"}')->>'rule' from catalogue.providers where stable_key='fixture:provider:12'")
psql -X -q -d "$DB" -c "update pipeline.platform_toolset_settings set value='0' where key='pdesc.machine_admit_on'" >/dev/null
[ "$BEFORE" = "machine_text_refused_word" ] || { echo "before the change the neutral sentence was expected to be refused: $BEFORE"; exit 1; }
echo "before: a sentence naming students, staff and alumni is refused by the machine rule (machine_text_refused_word), as live"

FNS="select p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public', 'api') and p.prokind = 'f' order by 1"
SET="select key || '=' || value::text from pipeline.platform_toolset_settings order by 1"
snap() { q "$FNS" | sort > "$1.fn"; q "$SET" | sort > "$1.set"; q "select count(*) from pipeline.layer4_review_items" > "$1.l4"; q "select count(*) from pipeline.provider_description_reads" > "$1.rd"; q "select count(*) from catalogue.providers where nullif(btrim(description), '') is not null" > "$1.desc"; q "select count(*) from pipeline.provider_description_machine_admissions" > "$1.adm"; (q "select count(*) from cron.job" 2>/dev/null || echo none) > "$1.cron"; }
W=$(mktemp -d); trap 'rm -rf "$W"; [ -n "${PDCC_KEEP:-}" ] || { dropdb --if-exists '$DB' >/dev/null 2>&1; dropdb --if-exists '${DB}_refuse' >/dev/null 2>&1; dropdb --if-exists '${DB}_scale' >/dev/null 2>&1; }' EXIT

# a live function that differs from the recorded one: the migration raises, and nothing at all is applied (the whole migration is one transaction)
RF=${DB}_refuse
dropdb --if-exists $RF >/dev/null 2>&1; createdb -T $DB $RF
psql -X -q -d $RF -v ON_ERROR_STOP=1 -c "do \$\$ begin execute regexp_replace(pg_get_functiondef('public.svc_provider_description_record(jsonb)'::regprocedure), 'begin', 'begin /* changed by hand */'); end \$\$" >/dev/null
rb=$( (psql -X -d $RF -Atc "$FNS" | sort | md5sum; psql -X -d $RF -Atc "$SET" | sort | md5sum; psql -X -d $RF -Atc "select to_regprocedure('security.pdesc_machine_text_check_ctx_v1(uuid,text,text[],jsonb)') is null") )
OUT=$(psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $MIG 2>&1) && { echo "the migration applied over a changed live function"; exit 1; }
grep -qF "differs from the definition this change edits" <<<"$OUT" || { echo "the refusal is not the expected one: $OUT" | tail -3; exit 1; }
ra=$( (psql -X -d $RF -Atc "$FNS" | sort | md5sum; psql -X -d $RF -Atc "$SET" | sort | md5sum; psql -X -d $RF -Atc "select to_regprocedure('security.pdesc_machine_text_check_ctx_v1(uuid,text,text[],jsonb)') is null") )
[ "$rb" = "$ra" ] || { echo "the refused migration changed something"; exit 1; }
dropdb --if-exists $RF >/dev/null 2>&1
echo "refused: a hand-changed live public.svc_provider_description_record is refused ('differs from the definition this change edits') and nothing is applied (no function, setting or new function)"

# apply: the four edited functions go from the recorded live md5 to the recorded after md5; two functions are added; nothing else changes; a second run is a no-op
snap "$W/0"
OUT=$($P -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -8; exit 1; }
for sig in "${!LIVE[@]}"; do
  grep -qF "$sig: applied" <<<"$OUT" || { echo "$sig was not edited"; echo "$OUT" | tail -8; exit 1; }
  after=$(grep -F -- "--   $sig " $MIG | head -1 | sed 's/.*-> *\([0-9a-f]*\).*/\1/')
  [ "$(q "select md5(prosrc) from pg_proc where oid = '$sig'::regprocedure")" = "$after" ] || { echo "$sig after the change differs from the recorded $after"; exit 1; }
done
snap "$W/1"
want=$(for sig in "${!LIVE[@]}"; do echo "$sig"; done | sed 's/^public\.//' | sort) # fixed: regprocedure prints public functions without the schema
changed=$(comm -23 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//' | sort)
[ "$changed" = "$want" ] || { echo "the changed functions differ from the edited ones"; diff <(echo "$want") <(echo "$changed"); exit 1; }
added=$(comm -13 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//' | sort | comm -23 - <(echo "$want"))
made=$({ grep -oE "^create or replace function (security|public)\.[a-z_0-9]+\(" $MIG || true; } | sed 's/create or replace function //; s/($//; s/^public\.//' | sort -u)
addednames=$(echo "$added" | sed 's/(.*//' | sort -u)
[ "$addednames" = "$made" ] || { echo "the added functions differ from those the migration creates"; diff <(echo "$made") <(echo "$addednames"); exit 1; }
[ "$(echo "$addednames" | grep -c .)" = 2 ] || { echo "expected two added functions: $addednames"; exit 1; }
lost=$(comm -23 "$W/0.set" "$W/1.set" || true)
[ -z "$lost" ] || { echo "the migration changed setting values: $lost"; exit 1; }
newset=$(comm -13 "$W/0.set" "$W/1.set")
[ "$newset" = 'pdesc.machine_neutral_words=["students", "staff", "alumni"]' ] || { echo "the only new setting should be pdesc.machine_neutral_words: $newset"; exit 1; }
for f in l4 rd desc adm cron; do cmp -s "$W/0.$f" "$W/1.$f" || { echo "the migration changed $f"; exit 1; }; done
OUT=$($P -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -8; exit 1; }
for sig in "${!LIVE[@]}"; do grep -qF "$sig: already applied" <<<"$OUT" || { echo "the second run was not a no-op for $sig"; exit 1; }; done
snap "$W/2"; for f in fn set l4 rd desc adm cron; do cmp -s "$W/1.$f" "$W/2.$f" || { echo "the second run changed $f"; exit 1; }; done
echo "migration: 4 edit(s) from the recorded live md5 to the recorded after md5; $(echo "$addednames" | grep -c .) function(s) added; one setting added (pdesc.machine_neutral_words), no value changed; no Layer 4 item, read, admission, description or job changed; applied again: no change"

# the new functions are not callable by the public roles, and the setting is complete (label, range, unit, section, used_by)
for sig in 'security.pdesc_machine_neutral_supported_v1(text,jsonb)' 'security.pdesc_machine_text_check_ctx_v1(uuid,text,text[],jsonb)'; do
  for role in public anon authenticated; do
    [ "$(q "select has_function_privilege('$role', '$sig'::regprocedure, 'execute')")" = f ] || { echo "$role can execute $sig"; exit 1; }
  done
  [ -n "$(q "select obj_description('$sig'::regprocedure, 'pg_proc')")" ] || { echo "$sig has no comment"; exit 1; }
done
echo "grants: the two new functions are revoked from public, anon and authenticated and carry a comment"

OUT=$(psql -X -d "$DB" -v ON_ERROR_STOP=1 -f $F/scenarios.sql 2>&1 | grep -E '^[a-z0-9_]+\|') || { echo "the scenarios failed"; psql -X -d "$DB" -v ON_ERROR_STOP=1 -f $F/scenarios.sql 2>&1 | tail -8; exit 1; }
if [ "$OUT" != "$(cat $F/expected.txt)" ]; then echo "the scenarios differ from $F/expected.txt:"; diff <(cat $F/expected.txt) <(echo "$OUT"); exit 1; fi
echo "scenarios: $(echo "$OUT" | wc -l) results match $F/expected.txt"

# the earlier machine scenarios still give the same result with the migration applied
OUT=$(psql -X -d "$DB" -v ON_ERROR_STOP=1 -f tests/fixtures/pdesc-machine/scenarios.sql 2>&1 | grep -E '^[a-z0-9_]+\|') || { echo "the earlier machine scenarios failed"; exit 1; }
if [ "$OUT" != "$(cat tests/fixtures/pdesc-machine/expected.txt)" ]; then echo "the earlier machine scenarios differ after the migration:"; diff <(cat tests/fixtures/pdesc-machine/expected.txt) <(echo "$OUT"); exit 1; fi
echo "earlier: the $(echo "$OUT" | wc -l) pdesc-machine scenarios give the same result after the migration"
echo "pdesc-claim-context: done"
