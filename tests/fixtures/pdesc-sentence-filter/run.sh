#!/usr/bin/env bash
# Guards: Platform Admin operating model v1.5 (10 Nov 2026, delivery first): migration 20261110120000 edits only security.provider_description_validate_v1(uuid,text,timestamptz,jsonb) and public.svc_provider_description_record(jsonb) (checked by the md5 of each function body, the same text on PostgreSQL 16 and 17; it refuses and changes nothing when a live function differs, and applying it again changes nothing) and extends the value of the existing setting pdesc.identity_reeval_rules,
# so that one weak sentence no longer sinks a provider-description proposal: with drop_failing (set only by the record of a new read) a sentence that fails a sentence rule is left out, the sentences that pass every rule are kept and stored, and fewer kept sentences than pdesc.min_sentences hold the read with the first failing rule; every other caller of the validator still holds the answer on the first failing sentence; no sentence rule is loosened; no other function, setting, table, trigger, read, Layer 4 item or job changes; the forward recovery in supabase/held restores both earlier bodies byte for byte.
# Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds the database with the pdesc-lease-record-timeouts harness (which applies 20261109182000, 20261109185000 and 20261109233000), applies 20261110040000 and 20261110090000, runs the scenarios, applies the migration twice, runs them again, applies the forward recovery and runs them a third time.
set -euo pipefail
cd "$(dirname "$0")/../../.."
export LC_ALL=C # fixed: one byte order for sort and comm, whatever the runner's locale
DB=${PDSF_DB:-g_pdesc_sentfilter}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
MIG=supabase/migrations/20261110120000_cf247_pdesc_sentence_filter.sql
REC=supabase/held/pdesc_sentence_filter_forward_recovery.sql
REPLAY=supabase/held/pdesc_sentence_filter_replay.sql
F=tests/fixtures/pdesc-sentence-filter
VAL='security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)'
REC_FN='public.svc_provider_description_record(jsonb)'
VAL_BEFORE=c1d56ef145b0673d3c475fdaa677ae1d
VAL_AFTER=7347f51b70a0c4a6cdd01a117080aad5
REC_BEFORE=9b2137954bc05501e55e93c8ef9cf448
REC_AFTER=5dab0348f912018e517671aef376c5b6
q() { psql -X -d "$DB" -Atc "$1"; }
BASE=$(PDLRT_KEEP=1 PDLRT_DB=$DB bash tests/fixtures/pdesc-lease-record-timeouts/run.sh 2>&1) || { echo "$BASE" | tail -15; echo "the base harness failed"; exit 1; }
echo "base: pdesc-lease-record-timeouts harness built the database (20261109020000, 20261109030000, 20261109120000, 20261109182000, 20261109185000 and 20261109233000 applied)"
W=$(mktemp -d); trap 'rm -rf "$W"; [ -n "${PDSF_KEEP:-}" ] || { dropdb --if-exists '$DB' >/dev/null 2>&1; dropdb --if-exists '${DB}_refuse' >/dev/null 2>&1; }' EXIT
for pre in 20261110040000_cf247_pdesc_basic_profile_upgrade 20261110090000_cf247_pdesc_signature_reader_version; do
  $P -1 -At -f supabase/migrations/$pre.sql >/dev/null || { echo "the prerequisite migration $pre failed"; exit 1; }
done
echo "prerequisite: 20261110040000 and 20261110090000 applied (the picker, the lease and the signature as live has them after #973 and #980)"

# the edited functions are the live ones, and so is the setting's earlier value (pg_proc.prosrc md5 and the setting, read 10 Nov 2026, project fxcwkweaxjtknorudmwp)
declare -A LIVE=( ["$VAL"]=$VAL_BEFORE ["$REC_FN"]=$REC_BEFORE )
for sig in "${!LIVE[@]}"; do
  [ "$(q "select md5(prosrc) from pg_proc where oid = '$sig'::regprocedure")" = "${LIVE[$sig]}" ] || { echo "the loaded $sig differs from live ${LIVE[$sig]}"; exit 1; }
done
[ "$(q "select value::text from pipeline.platform_toolset_settings where key = 'pdesc.identity_reeval_rules'")" = '["provider_name_conflict", "provider_name_not_proved", "provider_subunit_source"]' ] || { echo "the loaded setting differs from live"; exit 1; }
echo "loaded: the validator and the recorder = live (body md5 recorded in the migration header); pdesc.identity_reeval_rules lists the three identity rules"

run_scen() { psql -X -d "$DB" -Atq -f "$1" 2>&1 | grep -v '^$' | sed -E 's/^[0-9a-f]{8}-[0-9a-f-]{27}\|/<id>|/' || true; }
BEFORE=$(run_scen $F/scenarios.sql); grep -q 'ERROR' <<<"$BEFORE" && { echo "$BEFORE"; exit 1; }
[ "$BEFORE" = "$(cat $F/expected-before.txt)" ] || { echo "before the change the scenarios differ from the expected:"; diff $F/expected-before.txt <(echo "$BEFORE"); exit 1; }
for wantline in 'aim_flag_keeps_two|held|unsupported_sentence|kept=-1|dropped=-|chars=309' 'copy_flag_keeps_two|held|verbatim_passage|kept=-1|dropped=-|chars=333' 'off_flag_keeps_two|held|quote_not_on_page|kept=-1|dropped=-|chars=269'; do
  grep -qxF "$wantline" <<<"$BEFORE" || { echo "the live fault is not reproduced: $wantline"; exit 1; }
done
echo "before: $(wc -l < $F/expected-before.txt) scenarios as expected, including the live fault (one unsupported, copied or off-page sentence holds the whole answer even when the flag is given)"

FNS="select p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public', 'api') and p.prokind = 'f' order by 1"
SET="select key || '=' || value::text from pipeline.platform_toolset_settings order by 1"
OUTC="select md5(string_agg(o::text, '|' order by o.id)) from pipeline.ops_remedy_outcomes o"
snap() { q "$FNS" | sort > "$1.fn"; q "$SET" | sort > "$1.set"; q "$OUTC" > "$1.out"; q "select count(*) from pipeline.layer4_review_items" > "$1.l4"; q "select count(*) from pipeline.provider_description_reads" > "$1.rd"; q "select count(*) from pipeline.evidence_artifacts" > "$1.ev"; q "select count(*) from cron.job" > "$1.cron" 2>/dev/null || echo none > "$1.cron"; q "select string_agg(indexname, ',' order by indexname) from pg_indexes where schemaname in ('pipeline','catalogue')" > "$1.ix"; q "select string_agg(table_schema || '.' || table_name || '.' || column_name, ',' order by 1) from information_schema.columns where table_schema in ('pipeline','catalogue','security','public')" > "$1.cols"; q "select string_agg(oid::regclass::text, ',' order by oid::regclass::text) from pg_class where relkind = 'r' and relnamespace::regnamespace::text in ('pipeline','catalogue','security','public')" > "$1.tabs"; q "select string_agg(tgname, ',' order by tgname) from pg_trigger where not tgisinternal" > "$1.trg"; q "select count(*) from catalogue.providers where nullif(btrim(description), '') is not null" > "$1.desc"; q "select md5(string_agg(s::text, '|' order by s.key)) from pipeline.platform_toolset_settings s where key <> 'pdesc.identity_reeval_rules'" > "$1.oset"; }

# a live function that differs from the recorded one: the migration raises, and nothing at all is applied (the whole migration is one transaction)
RF=${DB}_refuse
for target in "$VAL" "$REC_FN"; do
  dropdb --if-exists $RF >/dev/null 2>&1; createdb -T $DB $RF
  psql -X -q -d $RF -v ON_ERROR_STOP=1 -c "do \$\$ begin execute regexp_replace(pg_get_functiondef('$target'::regprocedure), '-- provider-description', '-- changed by hand provider-description'); end \$\$" >/dev/null
  [ "$(psql -X -d $RF -Atc "select md5(prosrc) from pg_proc where oid = '$target'::regprocedure")" != "${LIVE[$target]}" ] || { echo "the hand change did not change $target"; exit 1; }
  rb=$( (psql -X -d $RF -Atc "$FNS" | sort | md5sum; psql -X -d $RF -Atc "$SET" | sort | md5sum) )
  OUT=$(psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $MIG 2>&1) && { echo "the migration applied over a changed $target"; exit 1; }
  grep -qF "differs from the definition this change edits" <<<"$OUT" || { echo "the refusal is not the expected one: $OUT" | tail -3; exit 1; }
  ra=$( (psql -X -d $RF -Atc "$FNS" | sort | md5sum; psql -X -d $RF -Atc "$SET" | sort | md5sum) )
  [ "$rb" = "$ra" ] || { echo "the refused migration changed something ($target)"; exit 1; }
  OUT=$(psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $REC 2>&1) && { echo "the forward recovery ran over a changed $target"; exit 1; }
  grep -qF "differs from both texts this recovery knows" <<<"$OUT" || { echo "the recovery refusal is not the expected one: $OUT" | tail -3; exit 1; }
done
# and the migration refuses when the setting it extends is missing
dropdb --if-exists $RF >/dev/null 2>&1; createdb -T $DB $RF
psql -X -q -d $RF -v ON_ERROR_STOP=1 -c "delete from pipeline.platform_toolset_settings where key = 'pdesc.identity_reeval_rules'" >/dev/null
OUT=$(psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $MIG 2>&1) && { echo "the migration applied without the setting"; exit 1; }
grep -qF "required setting pdesc.identity_reeval_rules is missing" <<<"$OUT" || { echo "the missing-setting refusal is not the expected one: $OUT" | tail -3; exit 1; }
dropdb --if-exists $RF >/dev/null 2>&1
echo "refused: a hand-changed live validator and a hand-changed live recorder are each refused by the migration and by the forward recovery (nothing applied), and the migration refuses without its setting"

# apply: the two functions go from the recorded live md5 to the recorded after md5; the one setting value is extended; nothing else changes; a second run is a no-op
snap "$W/0"
OUT=$($P -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -8; exit 1; }
for sig in "$VAL" "$REC_FN"; do grep -qF "$sig: applied" <<<"$OUT" || { echo "$sig was not edited"; echo "$OUT" | tail -8; exit 1; }; done
[ "$(q "select md5(prosrc) from pg_proc where oid = '$VAL'::regprocedure")" = "$VAL_AFTER" ] || { echo "the validator after the change differs from the recorded $VAL_AFTER"; exit 1; }
[ "$(q "select md5(prosrc) from pg_proc where oid = '$REC_FN'::regprocedure")" = "$REC_AFTER" ] || { echo "the recorder after the change differs from the recorded $REC_AFTER"; exit 1; }
grep -qF -- "--   $VAL $VAL_BEFORE -> $VAL_AFTER" $MIG || { echo "the migration header does not record the validator md5 before and after"; exit 1; }
grep -qF -- "--   $REC_FN $REC_BEFORE -> $REC_AFTER" $MIG || { echo "the migration header does not record the recorder md5 before and after"; exit 1; }
snap "$W/1"
want=$(printf '%s\n' "$(q "select '$VAL'::regprocedure::text")" "$(q "select '$REC_FN'::regprocedure::text")" | sort)
changed=$(comm -23 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//' | sort)
[ "$changed" = "$want" ] || { echo "the changed functions differ from the edited ones: $changed"; exit 1; }
[ -z "$(comm -13 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//' | sort | comm -23 - <(echo "$want"))" ] || { echo "the migration added a function"; exit 1; }
for f in out l4 rd ev cron ix cols tabs trg desc oset; do cmp -s "$W/0.$f" "$W/1.$f" || { echo "the migration changed $f"; exit 1; }; done
setdiff=$(comm -3 "$W/0.set" "$W/1.set" | sed 's/^\t*//; s/=.*//' | sort -u)
[ "$setdiff" = "pdesc.identity_reeval_rules" ] || { echo "the migration changed a setting other than pdesc.identity_reeval_rules: $setdiff"; exit 1; }
[ "$(q "select (value ?& array['provider_name_conflict','provider_name_not_proved','provider_subunit_source','verbatim_passage','quote_not_on_page','unsupported_sentence','unsupported_claim','unsupported_numeric_claim','unsupported_marketing','claim_negated_in_source','incomplete_sentence','historic_claim_context'])::text || '|' || jsonb_array_length(value) || '|' || (label <> '')::text || '|' || (help like '%sentence rules%')::text from pipeline.platform_toolset_settings where key = 'pdesc.identity_reeval_rules'")" = 'true|12|true|true' ] || { echo "pdesc.identity_reeval_rules does not list the twelve rules"; exit 1; }
OUT=$($P -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -8; exit 1; }
for sig in "$VAL" "$REC_FN"; do grep -qF "$sig: already applied" <<<"$OUT" || { echo "the second run was not a no-op for $sig"; exit 1; }; done
snap "$W/2"; for f in fn set out l4 rd ev cron ix cols tabs trg desc; do cmp -s "$W/1.$f" "$W/2.$f" || { echo "the second run changed $f"; exit 1; }; done
echo "migration: 2 edits from the recorded live md5 (validator $VAL_BEFORE, recorder $REC_BEFORE) to the recorded after md5 ($VAL_AFTER, $REC_AFTER) and the value of pdesc.identity_reeval_rules extended from 3 to 12 rules; no other function, setting, table, column, trigger, index, recorded outcome, read, Layer 4 item, description or job added or changed; applied again: no change"
[ "$(q "select has_function_privilege('anon', '$VAL'::regprocedure, 'execute') or has_function_privilege('authenticated', '$VAL'::regprocedure, 'execute')")" = f ] || { echo "the validator is open to a public role"; exit 1; }

# after: the same scenarios give the new answers
AFTERS=$(run_scen $F/scenarios.sql); grep -q 'ERROR' <<<"$AFTERS" && { echo "$AFTERS"; exit 1; }
[ "$AFTERS" = "$(cat $F/expected.txt)" ] || { echo "after the change the scenarios differ from the expected:"; diff $F/expected.txt <(echo "$AFTERS"); exit 1; }
for wantline in 'two_good_plain|propose|kept=-1|dropped=-|chars=203' 'aim_plain_holds|held|unsupported_sentence|kept=-1|dropped=-|chars=309' 'aim_flag_keeps_two|propose|kept=2|dropped=unsupported_sentence|chars=203' 'copy_flag_keeps_two|propose|kept=2|dropped=verbatim_passage|chars=203' 'off_flag_keeps_two|propose|kept=2|dropped=quote_not_on_page|chars=203' 'marketing_flag|propose|kept=2|dropped=unsupported_marketing|chars=203' 'ranking_flag|propose|kept=2|dropped=unsupported_claim|chars=203' 'number_flag|propose|kept=2|dropped=unsupported_numeric_claim|chars=203' 'fragment_flag|propose|kept=2|dropped=incomplete_sentence|chars=203' 'all_copied_holds|held|verbatim_passage|kept=-1|dropped=verbatim_passage,verbatim_passage|chars=0' 'six_sentences_flag|held|sentence_count|kept=-1|dropped=-|chars=611' 'flag_false_holds|held|unsupported_sentence' 'e2e_aim_read|proposed|missing|proposal=2|dropped=unsupported_sentence|item=2|text_has_aim=false'; do
  grep -qxF "$wantline" <<<"$AFTERS" || { echo "missing result: $wantline"; exit 1; }
done
echo "after: $(wc -l < $F/expected.txt) scenarios as expected: a sentence that is unsupported, copied, off the page, marketing, a ranking claim, a wrong number or a fragment is left out and the rest kept (each under its own rule); too few kept, six sentences, all copied and the answer without the flag are still held; a proposal made with a dropped sentence stores and sends to Layer 4 only the kept sentences"

# the replay: a read-only query that tests every stored sentence alone with the validator agrees with the filter on a held read
cat > "$W/replay_check.sql" <<'SQL'
begin;
create or replace function pg_temp.pid(n int) returns uuid language sql as $f$ select id from catalogue.providers where stable_key = 'fixture:provider:' || n::text $f$;
-- a held read of provider 2 (the Aurora-style fixture) carrying three stored sentences, two of them supported and one adding an aim: the replay keeps two and the validator, run on the read's own sentences, keeps two
insert into pipeline.provider_description_reads(provider_id, state, rule, source_url, source_captured_at, read_via, evidence_id, proposal)
select pg_temp.pid(2), 'held', 'unsupported_sentence', 'https://p2.example.edu/about', e.captured_at, 'stored', d.evidence_id,
       jsonb_build_object('sentences', jsonb_build_array(
         jsonb_build_object('text', 'Birch Valley University offers education in forest ecology and sustainable agriculture.', 'quote', 'Birch Valley University offers education in forest ecology and sustainable agriculture.', 'on_page', true),
         jsonb_build_object('text', 'The university is dedicated to solving the world''s biggest problems through forest research.', 'quote', 'Its teaching and learning focus on woodland conservation and agricultural science, supporting the development of knowledge in these fields.', 'on_page', true),
         jsonb_build_object('text', 'Teaching focuses on woodland conservation and agricultural science and develops knowledge through learning in these fields.', 'quote', 'Its teaching and learning focus on woodland conservation and agricultural science, supporting the development of knowledge in these fields.', 'on_page', true)))
  from fixture.documents d join pipeline.evidence_artifacts e on e.id = d.evidence_id where d.provider_id = pg_temp.pid(2);
SQL
sed -n '/^with p as/,/^  from gated group by rollup/p' $REPLAY | sed 's/^  from gated group by rollup.*$/  from gated group by rollup (rule) order by rule nulls last;/' >> "$W/replay_check.sql"
echo "rollback;" >> "$W/replay_check.sql"
RP=$(psql -X -d $DB -v ON_ERROR_STOP=1 -Atq -f "$W/replay_check.sql" 2>&1) || { echo "$RP"; exit 1; }
[ "$(awk -F'|' '$1 == "" {print $2 "|" $3 "|" $5 "|" $6}' <<<"$RP")" = '1|1|3.0|2.0' ] || { echo "the replay does not keep two of the three stored sentences: $RP"; exit 1; }
echo "replay: supabase/held/pdesc_sentence_filter_replay.sql (one read-only SELECT) tests each stored sentence alone with the validator and keeps two of the three on a held read, as the filter does"

# forward recovery: the earlier bodies are restored byte for byte, the old behaviour returns, running it again changes nothing, the migration applies again
snap "$W/3"
$P -1 -At -f $REC >/dev/null 2>&1 || { echo "the forward recovery failed"; exit 1; }
[ "$(q "select md5(prosrc) from pg_proc where oid = '$VAL'::regprocedure")" = "$VAL_BEFORE" ] || { echo "the forward recovery did not restore the earlier validator body"; exit 1; }
[ "$(q "select md5(prosrc) from pg_proc where oid = '$REC_FN'::regprocedure")" = "$REC_BEFORE" ] || { echo "the forward recovery did not restore the earlier recorder body"; exit 1; }
[ "$(q "select value::text from pipeline.platform_toolset_settings where key = 'pdesc.identity_reeval_rules'")" = '["provider_name_conflict", "provider_name_not_proved", "provider_subunit_source"]' ] || { echo "the forward recovery did not put back the three identity rules"; exit 1; }
snap "$W/4"
[ "$(comm -23 "$W/3.fn" "$W/4.fn" | sed 's/ [0-9a-f]*$//' | sort)" = "$want" ] || { echo "the forward recovery changed more than the two functions"; exit 1; }
for f in out l4 rd ev cron ix cols tabs trg desc oset; do cmp -s "$W/3.$f" "$W/4.$f" || { echo "the forward recovery changed $f"; exit 1; }; done
RECS=$(run_scen $F/scenarios.sql); [ "$RECS" = "$BEFORE" ] || { echo "after the forward recovery the scenarios differ from the live behaviour:"; diff <(echo "$BEFORE") <(echo "$RECS"); exit 1; }
$P -1 -At -f $REC >/dev/null 2>&1 || { echo "the forward recovery failed the second time"; exit 1; }
snap "$W/5"; for f in fn set out; do cmp -s "$W/4.$f" "$W/5.$f" || { echo "the second recovery run changed $f"; exit 1; }; done
OUT=$($P -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -8; exit 1; }
[ "$(q "select md5(prosrc) from pg_proc where oid = '$VAL'::regprocedure")" = "$VAL_AFTER" ] && [ "$(q "select md5(prosrc) from pg_proc where oid = '$REC_FN'::regprocedure")" = "$REC_AFTER" ] || { echo "the migration did not apply again after the recovery"; exit 1; }
echo "recovery: supabase/held/pdesc_sentence_filter_forward_recovery.sql restores body md5 $VAL_BEFORE and $REC_BEFORE byte for byte and the three identity rules, changes nothing else, gives the live behaviour again, is a no-op the second time; the migration applies again after it"
echo "pdesc-sentence-filter: done"
