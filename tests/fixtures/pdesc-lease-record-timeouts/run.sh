#!/usr/bin/env bash
# Guards: F-PDESC (P0, Platform Admin 9 Nov 2026), lease and record statement time-outs: migration 20261109233000 edits only public.svc_provider_description_next(integer) and public.svc_provider_description_record(jsonb) (checked by the md5 of each function body, the same text on PostgreSQL 16 and 17, and it refuses and changes nothing when either live function differs from the one it was written against), adds one index and no setting, job, table or column, and the lease and the record give the same items, order, content and results before and after.
# Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds the database with the pdesc-claim-context harness, applies 20261109182000 and 20261109185000 (the text this change edits), runs the scenarios, applies the migration twice, runs them again.
set -euo pipefail
cd "$(dirname "$0")/../../.."
export LC_ALL=C # fixed: one byte order for sort and comm, whatever the runner's locale
DB=${PDLRT_DB:-g_pdesc_leasetimeouts}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
MIG=supabase/migrations/20261109233000_cf247_pdesc_lease_record_timeouts.sql
F=tests/fixtures/pdesc-lease-record-timeouts
OP=tests/fixtures/pdesc-lease-one-pass
q() { psql -X -d "$DB" -Atc "$1"; }
BASE=$(PDCC_KEEP=1 PDCC_DB=$DB bash tests/fixtures/pdesc-claim-context/run.sh 2>&1) || { echo "$BASE" | tail -15; echo "the base harness failed"; exit 1; }
echo "base: pdesc-claim-context harness built the database (20261109020000, 20261109030000 and 20261109120000 applied)"
W=$(mktemp -d); trap 'rm -rf "$W"; [ -n "${PDLRT_KEEP:-}" ] || { dropdb --if-exists '$DB' >/dev/null 2>&1; dropdb --if-exists '${DB}_refuse' >/dev/null 2>&1; }' EXIT
for pre in 20261109182000_cf247_pdesc_lease_one_pass 20261109185000_cf247_pdesc_identity_reeval; do
  $P -1 -At -f supabase/migrations/$pre.sql >/dev/null || { echo "the prerequisite migration $pre failed"; exit 1; }
done
echo "prerequisite: 20261109182000 and 20261109185000 applied (the lease and the record as live has them)"

# the edited functions are the live ones, and the ones they call are the live ones (md5 of the function body, pg_proc.prosrc, read 9 Nov 2026, project fxcwkweaxjtknorudmwp)
declare -A LIVE=( ['public.svc_provider_description_next(integer)']=54c8856ec36465059d41d71a5a5d462b ['public.svc_provider_description_record(jsonb)']=f7c3debc11b67d6de7b2c6d47c8c9b9c )
for sig in "${!LIVE[@]}"; do
  [ "$(q "select md5(prosrc) from pg_proc where oid = '$sig'::regprocedure")" = "${LIVE[$sig]}" ] || { echo "the loaded $sig differs from live ${LIVE[$sig]}"; exit 1; }
done
echo "loaded: the lease and the record = live (body md5 recorded in the migration header)"

run_scen() { psql -X -d "$DB" -f "$1" 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\):  //p'; }
strip() { sed 's/ digest=[0-9a-f]*$//'; }
BEFORE=$(run_scen $F/scenarios.sql); echo "$BEFORE" | grep -q '^ERROR' && { echo "$BEFORE"; exit 1; }
BEFORE_OP=$(run_scen $OP/scenarios.sql); echo "$BEFORE_OP" | grep -q '^ERROR' && { echo "$BEFORE_OP"; exit 1; }
[ "$(echo "$BEFORE" | strip)" = "$(cat $F/expected.txt)" ] || { echo "before the change the scenarios differ from the expected:"; diff <(cat $F/expected.txt) <(echo "$BEFORE" | strip); exit 1; }
[ "$(echo "$BEFORE_OP" | strip)" = "$(cat $OP/expected.txt)" ] || { echo "before the change the lease scenarios differ from the expected:"; diff <(cat $OP/expected.txt) <(echo "$BEFORE_OP" | strip); exit 1; }
echo "before: $(( $(wc -l < $F/expected.txt) + $(wc -l < $OP/expected.txt) )) scenarios as expected (live behaviour)"

FNS="select p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public', 'api') and p.prokind = 'f' order by 1"
SET="select key || '=' || value::text from pipeline.platform_toolset_settings order by 1"
snap() { q "$FNS" | sort > "$1.fn"; q "$SET" | sort > "$1.set"; q "select count(*) from pipeline.layer4_review_items" > "$1.l4"; q "select count(*) from pipeline.provider_description_reads" > "$1.rd"; q "select count(*) from pipeline.evidence_artifacts" > "$1.ev"; q "select count(*) from cron.job" > "$1.cron" 2>/dev/null || echo none > "$1.cron"; q "select string_agg(indexname, ',' order by indexname) from pg_indexes where schemaname = 'pipeline'" > "$1.ix"; q "select count(*) from information_schema.columns where table_schema in ('pipeline','catalogue','public')" > "$1.cols"; q "select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname in ('pipeline','catalogue','public') and c.relkind in ('r','v','m')" > "$1.tabs"; }

# a live function that differs from the recorded one: the migration raises, and nothing at all is applied
RF=${DB}_refuse
for target in 'public.svc_provider_description_next(integer)|declare v jsonb;|declare v jsonb; v_hand int;|the lease' 'public.svc_provider_description_record(jsonb)|begin|begin /* changed by hand */|the record'; do
  IFS='|' read -r sig from to what <<<"$target"
  dropdb --if-exists $RF >/dev/null 2>&1; createdb -T $DB $RF
  psql -X -q -d $RF -v ON_ERROR_STOP=1 -c "do \$\$ begin execute regexp_replace(pg_get_functiondef('$sig'::regprocedure), '$from', '$to'); end \$\$" >/dev/null
  rb=$( (psql -X -d $RF -Atc "$FNS" | sort | md5sum; psql -X -d $RF -Atc "$SET" | sort | md5sum; psql -X -d $RF -Atc "select count(*) from pg_indexes where indexname = 'evidence_artifacts_source_url_idx'") )
  OUT=$(psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $MIG 2>&1) && { echo "the migration applied over a changed $what function"; exit 1; }
  grep -qF "differs from the definition this change edits" <<<"$OUT" || { echo "the refusal is not the expected one: $OUT" | tail -3; exit 1; }
  ra=$( (psql -X -d $RF -Atc "$FNS" | sort | md5sum; psql -X -d $RF -Atc "$SET" | sort | md5sum; psql -X -d $RF -Atc "select count(*) from pg_indexes where indexname = 'evidence_artifacts_source_url_idx'") )
  [ "$rb" = "$ra" ] || { echo "the refused migration changed something ($what)"; exit 1; }
done
dropdb --if-exists $RF >/dev/null 2>&1
echo "refused: a hand-changed lease function and a hand-changed record function are each refused and nothing is applied (no function, setting or index)"

# apply: the two functions go from the recorded live md5 to the recorded after md5; one index is added; nothing else changes; a second run is a no-op
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
[ -z "$(comm -13 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//' | sort | comm -23 - <(echo "$want"))" ] || { echo "the migration added a function"; exit 1; }
for f in set l4 rd ev cron cols tabs; do cmp -s "$W/0.$f" "$W/1.$f" || { echo "the migration changed $f"; exit 1; }; done
[ "$(comm -13 <(tr ',' '\n' < "$W/0.ix") <(tr ',' '\n' < "$W/1.ix"))" = evidence_artifacts_source_url_idx ] && [ "$(comm -23 <(tr ',' '\n' < "$W/0.ix" | sort) <(tr ',' '\n' < "$W/1.ix" | sort))" = "" ] || { echo "the only new index should be evidence_artifacts_source_url_idx"; exit 1; }
[ -n "$(q "select obj_description('pipeline.evidence_artifacts_source_url_idx'::regclass, 'pg_class')")" ] || { echo "the new index has no comment"; exit 1; }
OUT=$($P -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -8; exit 1; }
for sig in "${!LIVE[@]}"; do grep -qF "$sig: already applied" <<<"$OUT" || { echo "the second run was not a no-op for $sig"; exit 1; }; done
snap "$W/2"; for f in fn set l4 rd ev cron ix cols tabs; do cmp -s "$W/1.$f" "$W/2.$f" || { echo "the second run changed $f"; exit 1; }; done
echo "migration: 2 edits from the recorded live md5 to the recorded after md5; 1 index added (evidence_artifacts_source_url_idx); no function, setting, table, column, evidence, Layer 4 item, read or job added or changed; applied again: no change"
for sig in "${!LIVE[@]}"; do
  [ "$(q "select has_function_privilege('anon', '$sig'::regprocedure, 'execute') or has_function_privilege('authenticated', '$sig'::regprocedure, 'execute')")" = f ] || { echo "$sig is open to a public role"; exit 1; }
done

# after: the same items in the same order with the same content (digest of the whole answer), and the same record results
AFTERS=$(run_scen $F/scenarios.sql); echo "$AFTERS" | grep -q '^ERROR' && { echo "$AFTERS"; exit 1; }
[ "$AFTERS" = "$BEFORE" ] || { echo "the answers differ from before the change:"; diff <(echo "$BEFORE") <(echo "$AFTERS"); exit 1; }
AFTER_OP=$(run_scen $OP/scenarios.sql); echo "$AFTER_OP" | grep -q '^ERROR' && { echo "$AFTER_OP"; exit 1; }
[ "$AFTER_OP" = "$BEFORE_OP" ] || { echo "the lease answers differ from before the change:"; diff <(echo "$BEFORE_OP") <(echo "$AFTER_OP"); exit 1; }
echo "after: the $(( $(wc -l < $F/expected.txt) + $(wc -l < $OP/expected.txt) )) scenarios give the same items, order, content and results (digest of the whole answer) as before: providers out of scope or with a draft skipped, the setting limit, a direct read registered as evidence and one queued again, and the nine earlier lease scenarios"

# the shape: the dear per-provider tests run above the limit, the sweep source and the identity answer are found once per read
D=$(q "select pg_get_functiondef('public.svc_provider_description_next(integer)'::regprocedure)")
grep -q 'offset 0' <<<"$D" || { echo "the lease pick has lost its fence (offset 0)"; exit 1; }
[ "$(grep -c 'security.provider_description_stored_v1(' <<<"$D")" = 1 ] || { echo "the lease function no longer finds the stored copy in one pass"; exit 1; }
R=$(q "select pg_get_functiondef('public.svc_provider_description_record(jsonb)'::regprocedure)")
[ "$(grep -c 'security.coverage_sweep_source(' <<<"$R")" = 1 ] || { echo "the record asks for the sweep source in $(grep -c 'security.coverage_sweep_source(' <<<"$R") places (expected one)"; exit 1; }
[ "$(grep -c 'security.provider_description_identity_v1(' <<<"$R")" = 1 ] || { echo "the record asks for the identity answer in $(grep -c 'security.provider_description_identity_v1(' <<<"$R") places (expected one)"; exit 1; }
echo "shape: the lease pick keeps the dear tests above the limit (offset 0 fence); the record finds the sweep source once and the identity answer once per read"
echo "pdesc-lease-record-timeouts: done"
