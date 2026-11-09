#!/usr/bin/env bash
# Guards: F-PDESC Directive 3 (Platform Admin, 9 Nov 2026), lease statement time-out: migration 20261109182000 edits only public.svc_provider_description_next(integer) (checked by the md5 of the function body, the same text on PostgreSQL 16 and 17, and it refuses and changes nothing when the live function, the stored-copy function or the About pattern function differs from the one it was written against), and the lease hands out the same items, in the same order, with the same content, before and after.
# Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds the database with the pdesc-claim-context harness (which builds on pdesc-machine and applies 20261109020000, 20261109030000 and 20261109120000), runs the scenarios, applies the migration twice, runs them again.
set -euo pipefail
cd "$(dirname "$0")/../../.."
export LC_ALL=C # fixed: one byte order for sort and comm, whatever the runner's locale
DB=${PDLP_DB:-g_pdesc_leasepass}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
MIG=supabase/migrations/20261109182000_cf247_pdesc_lease_one_pass.sql
F=tests/fixtures/pdesc-lease-one-pass
q() { psql -X -d "$DB" -Atc "$1"; }
BASE=$(PDCC_KEEP=1 PDCC_DB=$DB bash tests/fixtures/pdesc-claim-context/run.sh 2>&1) || { echo "$BASE" | tail -15; echo "the base harness failed"; exit 1; }
echo "base: pdesc-claim-context harness built the database (20261109020000, 20261109030000 and 20261109120000 applied)"
W=$(mktemp -d); trap 'rm -rf "$W"; [ -n "${PDLP_KEEP:-}" ] || { dropdb --if-exists '$DB' >/dev/null 2>&1; dropdb --if-exists '${DB}_refuse' >/dev/null 2>&1; }' EXIT

# the edited function is the live one, and the two it relies on are the live ones (md5 of the function body, pg_proc.prosrc, read 9 Nov 2026, project fxcwkweaxjtknorudmwp)
declare -A LIVE=( ['public.svc_provider_description_next(integer)']=cb83dc4e3502d6cc16450c2126368ec9 ['security.provider_description_stored_v1(uuid)']=733d28159a080abdfd5cec244aed2cb9 ['security.pdesc_about_like_patterns_v1()']=29200a6a4ad7f38e0cdd30dbadd79857 )
for sig in "${!LIVE[@]}"; do
  [ "$(q "select md5(prosrc) from pg_proc where oid = '$sig'::regprocedure")" = "${LIVE[$sig]}" ] || { echo "the loaded $sig differs from live ${LIVE[$sig]}"; exit 1; }
done
echo "loaded: the edited function and the two it relies on = live (body md5 recorded in the migration)"

run_scen() { psql -X -d "$DB" -f $F/scenarios.sql 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\):  //p'; }
BEFORE=$(run_scen); echo "$BEFORE" | grep -q '^ERROR' && { echo "$BEFORE"; exit 1; }
EXPECT=$(cat $F/expected.txt); strip() { sed 's/ digest=[0-9a-f]*$//'; }
[ "$(echo "$BEFORE" | strip)" = "$EXPECT" ] || { echo "before the change the scenarios differ from the expected:"; diff <(echo "$EXPECT") <(echo "$BEFORE" | strip); exit 1; }
echo "before: $(echo "$EXPECT" | wc -l) scenarios as expected (live behaviour)"

FNS="select p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public', 'api') and p.prokind = 'f' order by 1"
SET="select key || '=' || value::text from pipeline.platform_toolset_settings order by 1"
snap() { q "$FNS" | sort > "$1.fn"; q "$SET" | sort > "$1.set"; q "select count(*) from pipeline.layer4_review_items" > "$1.l4"; q "select count(*) from pipeline.provider_description_reads" > "$1.rd"; q "select count(*) from cron.job" > "$1.cron" 2>/dev/null || echo none > "$1.cron"; q "select count(*) from pg_indexes where schemaname = 'pipeline'" > "$1.ix"; }

# a live function that differs from the recorded one: the migration raises, and nothing at all is applied
RF=${DB}_refuse
dropdb --if-exists $RF >/dev/null 2>&1; createdb -T $DB $RF
psql -X -q -d $RF -v ON_ERROR_STOP=1 -c "do \$\$ begin execute regexp_replace(pg_get_functiondef('security.provider_description_stored_v1(uuid)'::regprocedure), 'with w as', '/* changed by hand */ with w as'); end \$\$" >/dev/null
rb=$( (psql -X -d $RF -Atc "$FNS" | sort | md5sum; psql -X -d $RF -Atc "$SET" | sort | md5sum) )
OUT=$(psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $MIG 2>&1) && { echo "the migration applied over a changed stored-copy function"; exit 1; }
grep -qF "differs from the definition this change was written against" <<<"$OUT" || { echo "the refusal is not the expected one: $OUT" | tail -3; exit 1; }
ra=$( (psql -X -d $RF -Atc "$FNS" | sort | md5sum; psql -X -d $RF -Atc "$SET" | sort | md5sum) )
[ "$rb" = "$ra" ] || { echo "the refused migration changed something"; exit 1; }
# the same for the edited function itself
psql -X -q -d $RF -v ON_ERROR_STOP=1 -c "do \$\$ begin execute regexp_replace(pg_get_functiondef('security.provider_description_stored_v1(uuid)'::regprocedure), '/\\* changed by hand \\*/ ', ''); end \$\$" >/dev/null
psql -X -q -d $RF -v ON_ERROR_STOP=1 -c "do \$\$ begin execute regexp_replace(pg_get_functiondef('public.svc_provider_description_next(integer)'::regprocedure), 'declare v jsonb;', 'declare v jsonb; v_hand int;'); end \$\$" >/dev/null
OUT=$(psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $MIG 2>&1) && { echo "the migration applied over a changed lease function"; exit 1; }
grep -qF "differs from the definition this change edits" <<<"$OUT" || { echo "the refusal is not the expected one: $OUT" | tail -3; exit 1; }
dropdb --if-exists $RF >/dev/null 2>&1
echo "refused: a hand-changed stored-copy function and a hand-changed lease function are each refused and nothing is applied"

# apply: the lease function goes from the recorded live md5 to the recorded after md5; nothing else changes (no function added, no setting, no index, no job); a second run is a no-op
snap "$W/0"
OUT=$($P -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -8; exit 1; }
sig='public.svc_provider_description_next(integer)'
grep -qF "$sig: applied" <<<"$OUT" || { echo "$sig was not edited"; echo "$OUT" | tail -8; exit 1; }
after=$(grep -F -- "--   $sig " $MIG | head -1 | sed 's/.*-> *\([0-9a-f]*\).*/\1/')
[ "$(q "select md5(prosrc) from pg_proc where oid = '$sig'::regprocedure")" = "$after" ] || { echo "$sig after the change differs from the recorded $after"; exit 1; }
snap "$W/1"
changed=$(comm -23 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//' | sort)
short=${sig#public.} # regprocedure prints a public function without its schema
[ "$changed" = "$short" ] || { echo "the changed functions differ from the edited one: $changed"; exit 1; }
[ -z "$(comm -13 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//' | sort | comm -23 - <(echo "$short"))" ] || { echo "the migration added a function"; exit 1; }
for f in set l4 rd cron ix; do cmp -s "$W/0.$f" "$W/1.$f" || { echo "the migration changed $f"; exit 1; }; done
OUT=$($P -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -8; exit 1; }
grep -qF "$sig: already applied" <<<"$OUT" || { echo "the second run was not a no-op"; exit 1; }
snap "$W/2"; for f in fn set l4 rd cron ix; do cmp -s "$W/1.$f" "$W/2.$f" || { echo "the second run changed $f"; exit 1; }; done
echo "migration: 1 edit from the recorded live md5 to the recorded after md5 ($after); no function added, no setting, index, Layer 4 item, read or job changed; applied again: no change"
[ "$(q "select has_function_privilege('anon', '$sig'::regprocedure, 'execute') or has_function_privilege('authenticated', '$sig'::regprocedure, 'execute')")" = f ] || { echo "the lease function is open to a public role"; exit 1; }

# after: the same items in the same order with the same content (digest of the whole answer), and the same as the expected lines
AFTERS=$(run_scen); echo "$AFTERS" | grep -q '^ERROR' && { echo "$AFTERS"; exit 1; }
[ "$AFTERS" = "$BEFORE" ] || { echo "the lease answers differ from before the change:"; diff <(echo "$BEFORE") <(echo "$AFTERS"); exit 1; }
echo "after: the $(echo "$EXPECT" | wc -l) scenarios give the same items, order and content (digest of the whole answer) as before: About copies found, a news address, an underscore prefix, an upper-case name, a path with too many parts, a copy past the age limit, an expired and a running lease, the newest of two copies, nothing queued"

# the one pass: a provider with open work has its stored copy found once per lease (the page rule runs once per copy, not three times per queued row)
n=$(q "select pg_get_functiondef('public.svc_provider_description_next(integer)'::regprocedure)" | grep -c 'security.provider_description_stored_v1(')
[ "$n" = 1 ] || { echo "the lease function calls provider_description_stored_v1 in $n lines (expected the one pass)"; exit 1; }
echo "pdesc-lease-one-pass: done"
