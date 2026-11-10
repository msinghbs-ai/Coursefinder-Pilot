#!/usr/bin/env bash
# Guards: F-PDESC.01-.05 (Platform Admin decision 10 Nov 2026 19:47, sentence-subset recovery of machine-declined provider readings): migration 20261110210000 edits only security.provider_description_machine_admit_v1 and security.data_delivery_pdesc_v1 (checked by the md5 of each function body, refused and nothing applied when a live body differs) and adds only security.provider_description_subset_v1 (read only, not granted to anon or authenticated);
# a reading declined for a word, a figure or page markup in only some sentences is admitted by the existing machine actor and rule from the sentences that pass every check again, with the dropped sentences, original read and evidence recorded, the proposal, read, Layer 4 item and earlier decline kept; identity, lock, rejection, duplicate, below-minimum and all-refused readings stay declined; no setting, word list, read, ledger row, Layer 4 item or description is changed by the migration; the forward recovery returns both bodies byte for byte.
# Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds the database with the pdesc-dd-ai harness (which builds on the pdesc-sentence-filter harness), then applies the migration, runs the scenarios and the earlier machine-admission scenarios. PDSR_KEEP=1 keeps the databases.
set -euo pipefail
cd "$(dirname "$0")/../../.."
export LC_ALL=C # fixed: one byte order for sort and comm, whatever the runner's locale
DB=${PDSR_DB:-g_pdesc_subset}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
M=supabase/migrations/20261110210000_cf247_pdesc_sentence_subset_recovery.sql
R=supabase/held/pdesc_sentence_subset_recovery_forward_recovery.sql
F=tests/fixtures/pdesc-subset-recovery
ADM='security.provider_description_machine_admit_v1(uuid)'; DDP='security.data_delivery_pdesc_v1()'; SUB='security.provider_description_subset_v1(uuid,jsonb)'
ADM_BEFORE=dedf28930cc7a12ad31570dec0d2f334; FS='security.provider_description_fill_status_v1(uuid[],boolean,uuid)'; FS_BEFORE=4a37300325d9da37ba26c92a0eda8279; FS_AFTER=e0fea4e1e736f97b5a7172ecb981501a
ADM_AFTER=ed205f4b6dbdaf1a27b1bdf39479a276; DDP_BEFORE=15b2f9882e77d7fcf0a8a4be2b6df18f; DDP_AFTER=575bded841d3ceca0afc9bdf13bf4d82; SUB_AFTER=5f2d1a514ffcb45582888a2f455c63b8
q() { psql -X -d "$DB" -Atc "$1"; }
BASE=$(PDDA_KEEP=1 PDDA_DB=$DB bash tests/fixtures/pdesc-dd-ai/run.sh 2>&1) || { echo "$BASE" | tail -15; echo "the base harness failed"; exit 1; }
echo "base: pdesc-dd-ai harness built the database (20261109020000 to 20261110150000 as the harnesses apply them)"
W=$(mktemp -d); trap 'rm -rf "$W"; [ -n "${PDSR_KEEP:-}" ] || { dropdb --if-exists '$DB' >/dev/null 2>&1; dropdb --if-exists '${DB}_refuse' >/dev/null 2>&1; }' EXIT
# the status read of Fill fields lives in migration 20261110030000, outside the pdesc harnesses: its live text is loaded from that migration, over a stand-in for the level function it joins
python3 $F/live/extract_fill_status.py "$W/fill_status.sql"; $P -f $F/live/quality_stub.sql; $P -f "$W/fill_status.sql"
[ "$(q "select md5(prosrc) from pg_proc where oid = '$FS'::regprocedure")" = $FS_BEFORE ] || { echo "the loaded $FS differs from live $FS_BEFORE"; exit 1; }
[ "$(q "select md5(prosrc) from pg_proc where oid = '$ADM'::regprocedure")" = $ADM_BEFORE ] && [ "$(q "select md5(prosrc) from pg_proc where oid = '$DDP'::regprocedure")" = $DDP_BEFORE ] || { echo "the loaded admission or Data Delivery stream differs from live"; exit 1; }
echo "loaded: the machine admission ($ADM_BEFORE) and the Data Delivery provider stream ($DDP_BEFORE) = live (body md5 read 10 Nov 2026)"

FNS="select p.oid::regprocedure::text || ' ' || md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public', 'api') and p.prokind = 'f' order by 1"
SET="select key || '=' || value::text from pipeline.platform_toolset_settings order by 1"
snap() { q "$FNS" | sort > "$1.fn"; q "$SET" | sort > "$1.set"; q "select count(*) from pipeline.layer4_review_items" > "$1.l4"; q "select md5(string_agg(r::text, '|' order by r.id)) from pipeline.provider_description_reads r" > "$1.rd"; q "select count(*) from pipeline.ai_spend_ledger" > "$1.led"; q "select count(*) from pipeline.provider_description_machine_admissions" > "$1.adm"; q "select md5(string_agg(p.description, '|' order by p.id)) from catalogue.providers p" > "$1.desc"; q "select count(*) from cron.job" > "$1.cron"; }
same() { for f in "${@:3}"; do cmp -s "$1.$f" "$2.$f" || { echo "changed: $f"; exit 1; }; done; }

# a live admission that differs from the recorded one: the migration and the forward recovery both refuse, and nothing is applied
RF=${DB}_refuse
for target in "$ADM" "$DDP" "$FS"; do
  dropdb --if-exists $RF >/dev/null 2>&1; createdb -T $DB $RF
  psql -X -q -d $RF -v ON_ERROR_STOP=1 -c "do \$\$ begin execute regexp_replace(pg_get_functiondef('$target'::regprocedure), 'begin', 'begin /* changed by hand */'); end \$\$" >/dev/null
  [ "$(psql -X -d $RF -Atc "select md5(prosrc) from pg_proc where oid = '$target'::regprocedure")" != "$(q "select md5(prosrc) from pg_proc where oid = '$target'::regprocedure")" ] || { echo "the hand change did not change $target"; exit 1; }
  rb=$( (psql -X -d $RF -Atc "$FNS" | sort | md5sum; psql -X -d $RF -Atc "select to_regprocedure('$SUB') is null") )
  OUT=$(psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $M 2>&1) && { echo "the migration applied over a changed $target"; exit 1; }
  grep -qF "differs from the definition this change edits" <<<"$OUT" || { echo "the refusal is not the expected one: $OUT" | tail -3; exit 1; }
  ra=$( (psql -X -d $RF -Atc "$FNS" | sort | md5sum; psql -X -d $RF -Atc "select to_regprocedure('$SUB') is null") )
  [ "$rb" = "$ra" ] || { echo "the refused migration changed something ($target)"; exit 1; }
  OUT=$(psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $R 2>&1) && { echo "the forward recovery ran over a changed $target"; exit 1; }
  grep -qF "differs from both texts this recovery knows" <<<"$OUT" || { echo "the recovery refusal is not the expected one: $OUT" | tail -3; exit 1; }
done
dropdb --if-exists $RF >/dev/null 2>&1
echo "refused: a hand-changed live admission and a hand-changed live Data Delivery stream are each refused by the migration and by the forward recovery, and nothing is applied (no function added)"

# the migration: two functions go from the recorded live md5 to the recorded after md5; one function is added; nothing else changes; a second run is a no-op
snap "$W/0"
OUT=$($P -1 -At -f $M 2>&1) || { echo "$OUT" | tail -8; exit 1; }
for want in "$ADM $ADM_BEFORE -> $ADM_AFTER" "$DDP $DDP_BEFORE -> $DDP_AFTER" "$FS $FS_BEFORE -> $FS_AFTER" "$SUB (new) -> $SUB_AFTER"; do grep -qF -- "--   $want" $M || { echo "the migration header does not record: $want"; exit 1; }; done
[ "$(q "select md5(prosrc) from pg_proc where oid = '$ADM'::regprocedure")" = $ADM_AFTER ] && [ "$(q "select md5(prosrc) from pg_proc where oid = '$DDP'::regprocedure")" = $DDP_AFTER ] && [ "$(q "select md5(prosrc) from pg_proc where oid = '$FS'::regprocedure")" = $FS_AFTER ] && [ "$(q "select md5(prosrc) from pg_proc where oid = '$SUB'::regprocedure")" = $SUB_AFTER ] || { echo "the migration did not leave the recorded md5s"; exit 1; }
snap "$W/1"
changed=$(comm -23 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//' | sort); added=$(comm -13 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//' | sort)
[ "$changed" = "$(printf '%s\n' "$ADM" "$DDP" "${FS/public./}" | sort)" ] || { echo "functions changed other than the three edited: $changed"; exit 1; }
[ "$added" = "$(printf '%s\n' "$ADM" "$DDP" "$FS" "$SUB" | sort)" ] || { echo "unexpected functions added or edited: $added"; exit 1; }
same "$W/0" "$W/1" set l4 rd led adm desc cron
[ -n "$(q "select obj_description('$SUB'::regprocedure, 'pg_proc')")" ] || { echo "the new function has no comment"; exit 1; }
[ "$(q "select has_function_privilege('anon', '$SUB', 'execute') or has_function_privilege('authenticated', '$SUB', 'execute') or has_function_privilege('public', '$SUB', 'execute')")" = f ] || { echo "the new function is granted"; exit 1; }
OUT=$($P -1 -At -f $M 2>&1) || { echo "$OUT" | tail -8; exit 1; }
grep -qF "$ADM: already applied" <<<"$OUT" && grep -qF "$DDP: already applied" <<<"$OUT" || { echo "the second run was not a no-op"; exit 1; }
snap "$W/2"; same "$W/1" "$W/2" fn set l4 rd led adm desc cron
echo "migration 20261110210000: the machine admission, the provider Data Delivery stream and the Fill fields status read go from the recorded live md5 to the recorded after md5, one read-only function is added (no grant to anon or authenticated), no setting, word list, read, ledger row, Layer 4 item, description or job changed; applied again: no change"

# the scenarios
check() { # name, got, expected file
  grep -q 'ERROR' <<<"$2" && { echo "$1 failed:"; echo "$2" | grep ERROR | head -3; exit 1; }
  [ "$2" = "$(cat "$3")" ] || { echo "$1 differs from $3:"; diff "$3" <(echo "$2"); exit 1; }
}
GOT=$(psql -X -d $DB -Atq -f $F/scenarios.sql 2>&1 | grep -aE '^([a-z0-9_]+\||.*ERROR)' || true)
check "scenarios" "$GOT" $F/expected.txt
echo "scenarios: $(wc -l < $F/expected.txt) as expected (the Monash shape recovered by the settlement and at the record, a figure alone, a clean reading unchanged, and not recovered: below the minimum, every sentence refused, identity finding, manual lock, earlier rejection, description held, switch off, duplicate remainder, a settled item, a legacy reading whose name sat in the dropped sentence; Data Delivery counts)"
snap "$W/3"; same "$W/2" "$W/3" fn set l4 rd led adm desc cron
echo "scenarios: every block rolled back (no function, setting, Layer 4 item, read, ledger row, description or job left behind)"

# the earlier scenarios give the same result with the migration applied
for S in pdesc-machine pdesc-claim-context pdesc-basic-upgrade; do
  GOT=$(psql -X -d $DB -v ON_ERROR_STOP=1 -f tests/fixtures/$S/scenarios.sql 2>&1 | grep -E '^[a-z0-9_]+\|' || true)
  # the one deliberate change: a reading with ONE promotional sentence (ranked, best) among clean ones used to wait whole for a person; its clean sentences are now admitted (claim-context-after.txt differs from the earlier expected file in exactly those three results)
  E=tests/fixtures/$S/expected.txt; [ "$S" != pdesc-claim-context ] || E=$F/claim-context-after.txt
  check "the earlier $S scenarios" "$GOT" $E
  if [ "$S" = pdesc-claim-context ]; then
    CH=$(diff tests/fixtures/$S/expected.txt $E | grep '^[<>]' | cut -c3- | cut -d'|' -f1 | sort -u | tr '\n' ' ' || true)
    [ "$CH" = "record_declined record_tally waiting_promotional waiting_promotional_settle " ] || { echo "the claim-context change is not exactly the promotional-sentence results: $CH"; exit 1; }
    echo "earlier: the $(wc -l < tests/fixtures/$S/expected.txt) $S scenarios give the same result after the migration except the three where one promotional sentence no longer holds the clean ones (record_tally, record_declined, waiting_promotional)"
  else
    echo "earlier: the $(wc -l < tests/fixtures/$S/expected.txt) $S scenarios give the same result after the migration"
  fi
done
GOT=$(psql -X -d $DB -Atq -f tests/fixtures/pdesc-dd-ai/scenarios.sql 2>&1 | grep -aE '^([a-z0-9_]+\||.*ERROR)' || true)
check "the earlier pdesc-dd-ai scenarios" "$GOT" $F/dd-ai-after.txt
# the one deliberate change: the list of keys of the empty stream gains subset_recovery (additive; every existing key and value is the same)
[ "$(diff tests/fixtures/pdesc-dd-ai/expected.txt $F/dd-ai-after.txt | grep '^[<>]' | cut -c3- | cut -d'|' -f1 | sort -u | tr '\n' ' ' || true)" = "empty_keys " ] && [ "$(diff <(sed 's/subset_recovery,//' $F/dd-ai-after.txt) tests/fixtures/pdesc-dd-ai/expected.txt | wc -l)" = 0 ] || { echo "the pdesc-dd-ai change is not just the additive key"; exit 1; }
echo "earlier: the $(wc -l < tests/fixtures/pdesc-dd-ai/expected.txt) pdesc-dd-ai scenarios give the same result after the migration; the only difference is the additive key subset_recovery in the key list (existing keys and values unchanged)"
snap "$W/4"; same "$W/2" "$W/4" fn # the earlier scenario files set switches outside their blocks, so settings and rows are compared again after the recovery instead

# the forward recovery returns both bodies byte for byte, leaves the new function, is repeatable, and the migration applies again after it
$P -1 -At -f $R >/dev/null
[ "$(q "select md5(prosrc) from pg_proc where oid = '$ADM'::regprocedure")" = $ADM_BEFORE ] && [ "$(q "select md5(prosrc) from pg_proc where oid = '$DDP'::regprocedure")" = $DDP_BEFORE ] && [ "$(q "select md5(prosrc) from pg_proc where oid = '$FS'::regprocedure")" = $FS_BEFORE ] || { echo "the recovery did not restore the three bodies"; exit 1; }
[ "$(q "select to_regprocedure('$SUB') is not null")" = t ] || { echo "the recovery removed the new function"; exit 1; }
$P -1 -At -f $R >/dev/null
$P -1 -At -f $M >/dev/null
[ "$(q "select md5(prosrc) from pg_proc where oid = '$ADM'::regprocedure")" = $ADM_AFTER ] && [ "$(q "select md5(prosrc) from pg_proc where oid = '$FS'::regprocedure")" = $FS_AFTER ] || { echo "the migration did not apply again after the recovery"; exit 1; }
snap "$W/5"; same "$W/4" "$W/5" fn set l4 rd led adm desc cron
echo "recovery: the forward recovery returns the admission, the provider Data Delivery stream and the Fill fields status read to the live text byte for byte (the new function stays, unused), is repeatable, and the migration applies again after it"
echo "pdesc-subset-recovery: done"
