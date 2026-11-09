#!/usr/bin/env bash
# Guards: Platform Admin 9-10 Nov 2026 on-demand provider descriptions – identity fix must be able to reach the AI step: migration 20261110090000 edits only security.provider_description_signature_v1(text,text,text) and security.provider_description_selection_v1(jsonb) (checked by the md5 of the function body, the same text on PostgreSQL 16 and 17; it refuses and changes nothing when the live function differs, and applying it again changes nothing),
# makes the evidence signature carry the reader that is running (security.pdesc_reader_behaviour_v1, one stored row), so a failure recorded under reader v2 does not block the reservation under reader v3, a failure recorded under v3 still blocks v3, the picker offers a no-AI recovery-knowledge refusal (Sydney's shape) again while a real AI failure, rejected evidence, a changed page and a repeat of the same signature stay parked, and the recorded failures, settings, jobs, reads and every other function are untouched; the forward recovery in supabase/held restores the earlier body byte for byte.
# Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds the database with the pdesc-lease-record-timeouts harness (which applies 20261109182000, 20261109185000 and 20261109233000), applies 20261110040000 (the picker and lease text this change edits and calls), runs the scenarios, applies the migration twice, runs them again, applies the forward recovery and runs them a third time.
set -euo pipefail
cd "$(dirname "$0")/../../.."
export LC_ALL=C # fixed: one byte order for sort and comm, whatever the runner's locale
DB=${PDSR_DB:-g_pdesc_sigreader}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
MIG=supabase/migrations/20261110090000_cf247_pdesc_signature_reader_version.sql
REC=supabase/held/pdesc_signature_reader_forward_recovery.sql
F=tests/fixtures/pdesc-signature-reader
SIG='security.provider_description_signature_v1(text,text,text)'
SEL='security.provider_description_selection_v1(jsonb)'
BEFORE_MD5=b48bbd5b345f2e7b9a1fc6df9958163b
AFTER_MD5=2002daebe8768dc9504b8c53131472e0
SEL_BEFORE_MD5=41c9e5ffaba74453c699fd84e9135648
SEL_AFTER_MD5=7f4a7aa8fea1b81bbf8c1742d749502e
q() { psql -X -d "$DB" -Atc "$1"; }
BASE=$(PDLRT_KEEP=1 PDLRT_DB=$DB bash tests/fixtures/pdesc-lease-record-timeouts/run.sh 2>&1) || { echo "$BASE" | tail -15; echo "the base harness failed"; exit 1; }
echo "base: pdesc-lease-record-timeouts harness built the database (20261109020000, 20261109030000, 20261109120000, 20261109182000, 20261109185000 and 20261109233000 applied)"
W=$(mktemp -d); trap 'rm -rf "$W"; [ -n "${PDSR_KEEP:-}" ] || { dropdb --if-exists '$DB' >/dev/null 2>&1; dropdb --if-exists '${DB}_refuse' >/dev/null 2>&1; }' EXIT
$P -1 -At -f supabase/migrations/20261110040000_cf247_pdesc_basic_profile_upgrade.sql >/dev/null || { echo "the prerequisite migration 20261110040000 failed"; exit 1; }
echo "prerequisite: 20261110040000 applied (the picker and the lease as live has them after #973)"

# the edited function, the recorder and the checker are the live ones (md5 of the function body, pg_proc.prosrc, read 10 Nov 2026, project fxcwkweaxjtknorudmwp)
declare -A LIVE=( ["$SIG"]=$BEFORE_MD5 ["$SEL"]=$SEL_BEFORE_MD5 ['security.provider_description_learning_trg_v1()']=470dd2b0208e0fc6f46f1c95be55a72e ['public.svc_provider_description_reserve_v1(uuid,text,numeric,text)']=8f1f3edfb97f848b4296d6be0333a35b ['public.svc_provider_description_next(integer)']=504678d725b0131785f7e3541a6c3695 )
for sig in "${!LIVE[@]}"; do
  [ "$(q "select md5(prosrc) from pg_proc where oid = '$sig'::regprocedure")" = "${LIVE[$sig]}" ] || { echo "the loaded $sig differs from live ${LIVE[$sig]}"; exit 1; }
done
echo "loaded: the signature, the picker, the learning trigger, the reservation and the lease = live (body md5 recorded in the migration header)"

run_scen() { psql -X -d "$DB" -Atq -f "$1" 2>&1 | grep -v '^$' || true; }
BEFORE=$(run_scen $F/scenarios.sql); grep -q 'ERROR' <<<"$BEFORE" && { echo "$BEFORE"; exit 1; }
[ "$BEFORE" = "$(cat $F/expected-before.txt)" ] || { echo "before the change the scenarios differ from the expected:"; diff $F/expected-before.txt <(echo "$BEFORE"); exit 1; }
[ "$(sed -n 's/^v2_failure_blocks_v3|//p' <<<"$BEFORE")" = recovery_knowledge_unchanged_failure ] || { echo "the live fault is not reproduced"; exit 1; }
echo "before: $(wc -l < $F/expected-before.txt) scenarios as expected, including the live fault (a failure recorded under reader v2 refuses the reservation under reader v3: recovery_knowledge_unchanged_failure)"

FNS="select p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public', 'api') and p.prokind = 'f' order by 1"
SET="select key || '=' || value::text from pipeline.platform_toolset_settings order by 1"
OUTC="select md5(string_agg(o::text, '|' order by o.id)) from pipeline.ops_remedy_outcomes o"
snap() { q "$FNS" | sort > "$1.fn"; q "$SET" | sort > "$1.set"; q "$OUTC" > "$1.out"; q "select count(*) from pipeline.layer4_review_items" > "$1.l4"; q "select count(*) from pipeline.provider_description_reads" > "$1.rd"; q "select count(*) from pipeline.evidence_artifacts" > "$1.ev"; q "select count(*) from cron.job" > "$1.cron" 2>/dev/null || echo none > "$1.cron"; q "select string_agg(indexname, ',' order by indexname) from pg_indexes where schemaname in ('pipeline','catalogue')" > "$1.ix"; q "select string_agg(table_schema || '.' || table_name || '.' || column_name, ',' order by 1) from information_schema.columns where table_schema in ('pipeline','catalogue','security','public')" > "$1.cols"; q "select string_agg(oid::regclass::text, ',' order by oid::regclass::text) from pg_class where relkind = 'r' and relnamespace::regnamespace::text in ('pipeline','catalogue','security','public')" > "$1.tabs"; q "select string_agg(tgname, ',' order by tgname) from pg_trigger where not tgisinternal" > "$1.trg"; }

# a live function that differs from the recorded one: the migration raises, and nothing at all is applied (the whole migration is one transaction)
RF=${DB}_refuse
for target in "$SIG" "$SEL"; do
  dropdb --if-exists $RF >/dev/null 2>&1; createdb -T $DB $RF
  psql -X -q -d $RF -v ON_ERROR_STOP=1 -c "do \$\$ begin execute regexp_replace(pg_get_functiondef('$target'::regprocedure), 'begin|select md5', case when '$target' = '$SEL' then 'begin /* changed by hand */' else 'select /* changed by hand */ md5' end); end \$\$" >/dev/null
  [ "$(psql -X -d $RF -Atc "select md5(prosrc) from pg_proc where oid = '$target'::regprocedure")" != "${LIVE[$target]}" ] || { echo "the hand change did not change $target"; exit 1; }
  rb=$( (psql -X -d $RF -Atc "$FNS" | sort | md5sum; psql -X -d $RF -Atc "$SET" | sort | md5sum) )
  OUT=$(psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $MIG 2>&1) && { echo "the migration applied over a changed $target"; exit 1; }
  grep -qF "differs from the definition this change edits" <<<"$OUT" || { echo "the refusal is not the expected one: $OUT" | tail -3; exit 1; }
  ra=$( (psql -X -d $RF -Atc "$FNS" | sort | md5sum; psql -X -d $RF -Atc "$SET" | sort | md5sum) )
  [ "$rb" = "$ra" ] || { echo "the refused migration changed something ($target)"; exit 1; }
  # the forward recovery refuses the same hand-changed function
  OUT=$(psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $REC 2>&1) && { echo "the forward recovery ran over a changed $target"; exit 1; }
  grep -qF "differs from both texts this recovery knows" <<<"$OUT" || { echo "the recovery refusal is not the expected one: $OUT" | tail -3; exit 1; }
done
# and the migration refuses when the reader function it needs is missing (20261109185000 not applied)
dropdb --if-exists $RF >/dev/null 2>&1; createdb -T $DB $RF
psql -X -q -d $RF -v ON_ERROR_STOP=1 -c "drop function security.pdesc_reader_behaviour_v1()" >/dev/null
OUT=$(psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $MIG 2>&1) && { echo "the migration applied without the reader function"; exit 1; }
grep -qF "required security.pdesc_reader_behaviour_v1() is missing" <<<"$OUT" || { echo "the missing-reader refusal is not the expected one: $OUT" | tail -3; exit 1; }
dropdb --if-exists $RF >/dev/null 2>&1
echo "refused: a hand-changed live signature function and a hand-changed live picker are each refused by the migration and by the forward recovery (nothing applied), and the migration refuses without the reader function"

# the old picker with the new signature (what QA found on #980 before the picker was edited): the reservation passes, but Sydney's shape is still parked, so the picker edit is needed
OLDSEL=$(q "select pg_get_functiondef('$SEL'::regprocedure)")
dropdb --if-exists $RF >/dev/null 2>&1; createdb -T $DB $RF
psql -X -q -d $RF -v ON_ERROR_STOP=1 -1 -f $MIG >/dev/null
printf '%s\n' "$OLDSEL" | psql -X -q -d $RF -v ON_ERROR_STOP=1 >/dev/null
[ "$(psql -X -d $RF -Atc "select md5(prosrc) from pg_proc where oid = '$SEL'::regprocedure")" = "$SEL_BEFORE_MD5" ] || { echo "the old picker was not restored in the clone"; exit 1; }
HALF=$(psql -X -d $RF -Atq -f $F/scenarios.sql 2>&1 | grep -v '^$' || true)
grep -qxF 'v2_failure_blocks_v3|ok' <<<"$HALF" || { echo "with the new signature the reservation should pass"; exit 1; }
grep -qxF 'sydney_shape_picker|unchanged_unsuitable_evidence' <<<"$HALF" || { echo "with the old picker Sydney's shape should still be parked"; exit 1; }
grep -qxF 'sydney_shape_enqueued|not queued' <<<"$HALF" || { echo "with the old picker Sydney's shape should not be queued"; exit 1; }
dropdb --if-exists $RF >/dev/null 2>&1
echo "old picker: with the new signature and the earlier picker the reservation passes, but Sydney's shape is still parked (unchanged_unsuitable_evidence) and not queued: the picker edit is what releases it"

# apply: the two functions go from the recorded live md5 to the recorded after md5; nothing else changes; a second run is a no-op
snap "$W/0"
OUT=$($P -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -8; exit 1; }
for sig in "$SIG" "$SEL"; do grep -qF "$sig: applied" <<<"$OUT" || { echo "$sig was not edited"; echo "$OUT" | tail -8; exit 1; }; done
[ "$(q "select md5(prosrc) from pg_proc where oid = '$SIG'::regprocedure")" = "$AFTER_MD5" ] || { echo "the signature after the change differs from the recorded $AFTER_MD5"; exit 1; }
[ "$(q "select md5(prosrc) from pg_proc where oid = '$SEL'::regprocedure")" = "$SEL_AFTER_MD5" ] || { echo "the picker after the change differs from the recorded $SEL_AFTER_MD5"; exit 1; }
grep -qF -- "--   security.provider_description_signature_v1(text,text,text) $BEFORE_MD5 -> $AFTER_MD5" $MIG || { echo "the migration header does not record the signature md5 before and after"; exit 1; }
grep -qF -- "--   security.provider_description_selection_v1(jsonb) $SEL_BEFORE_MD5 -> $SEL_AFTER_MD5" $MIG || { echo "the migration header does not record the picker md5 before and after"; exit 1; }
snap "$W/1"
want=$(printf '%s\n' "security.provider_description_signature_v1(text,text,text)" "security.provider_description_selection_v1(jsonb)" | sort)
changed=$(comm -23 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//' | sort)
[ "$changed" = "$want" ] || { echo "the changed functions differ from the edited ones: $changed"; exit 1; }
[ -z "$(comm -13 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//' | sort | comm -23 - <(echo "$want"))" ] || { echo "the migration added a function"; exit 1; }
for f in set out l4 rd ev cron ix cols tabs trg; do cmp -s "$W/0.$f" "$W/1.$f" || { echo "the migration changed $f"; exit 1; }; done
OUT=$($P -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -8; exit 1; }
for sig in "$SIG" "$SEL"; do grep -qF "$sig: already applied" <<<"$OUT" || { echo "the second run was not a no-op for $sig"; exit 1; }; done
snap "$W/2"; for f in fn set out l4 rd ev cron ix cols tabs trg; do cmp -s "$W/1.$f" "$W/2.$f" || { echo "the second run changed $f"; exit 1; }; done
echo "migration: 2 edits from the recorded live md5 (signature $BEFORE_MD5, picker $SEL_BEFORE_MD5) to the recorded after md5 ($AFTER_MD5, $SEL_AFTER_MD5); no other function, setting, table, column, trigger, index, recorded outcome, read, Layer 4 item or job added or changed; applied again: no change"
[ "$(q "select has_function_privilege('anon', '$SIG'::regprocedure, 'execute') or has_function_privilege('authenticated', '$SIG'::regprocedure, 'execute')")" = f ] || { echo "the signature is open to a public role"; exit 1; }

# after: the same scenarios give the new answers
AFTERS=$(run_scen $F/scenarios.sql); grep -q 'ERROR' <<<"$AFTERS" && { echo "$AFTERS"; exit 1; }
[ "$AFTERS" = "$(cat $F/expected.txt)" ] || { echo "after the change the scenarios differ from the expected:"; diff $F/expected.txt <(echo "$AFTERS"); exit 1; }
for wantline in 'sydney_shape_picker|eligible' 'sydney_shape_enqueued|queued' 'memory_matches_current_reader_picker|unchanged_unsuitable_evidence' 'real_ai_failure_other_rule_picker|unchanged_unsuitable_evidence' 'real_ai_failure_same_rule_picker|unchanged_unsuitable_evidence' 'rejected_latest_picker|unchanged_unsuitable_evidence' 'rejected_earlier_picker|unchanged_unsuitable_evidence' 'changed_page_picker|retry_wait' 'repeat_same_signature_picker|unchanged_unsuitable_evidence' 'repeat_new_reader_picker|eligible' 'v2_failure_blocks_v2|recovery_knowledge_unchanged_failure' 'v2_failure_blocks_v3|ok' 'v3_failure_blocks_v3|recovery_knowledge_unchanged_failure' 'v3_failure_blocks_v4|ok' 'rejected_evidence_still_refused_v3|unchanged_rejected_evidence' 'ai_ceiling_still_applies|ai_ceiling' 'no_reader_signature_is_legacy|true'; do
  grep -qxF "$wantline" <<<"$AFTERS" || { echo "missing result: $wantline"; exit 1; }
done
echo "after: $(wc -l < $F/expected.txt) scenarios as expected: a failure under reader v2 does not block the reservation under v3; a failure under v3 still blocks v3 (not a later v4); no reader on record gives the earlier signature; rejected evidence and the AI ceiling still refuse; the picker and the lease release a v2 failure once the reader is v3; Sydney's shape (a no-AI recovery-knowledge hold) is offered and queued again, while a real AI failure, a reservation left, a rejected page, a changed page and a repeat under the same signature stay parked"

# the cost: the reader is one row of its own table, read once per signature; it never reads the reads
D=$(q "select pg_get_functiondef('$SIG'::regprocedure)")
[ "$(grep -o 'security.pdesc_reader_behaviour_v1()' <<<"$D" | wc -l)" = 1 ] || { echo "the signature must ask for the reader exactly once"; exit 1; }
[ "$(q "select (prosrc like '%pdesc_reader_state%' and prosrc not like '%provider_description_reads%' and prosrc not like '%generate_series%')::text from pg_proc where oid = 'security.pdesc_reader_behaviour_v1()'::regprocedure")" = true ] || { echo "the reader function reads something other than its one-row table"; exit 1; }
[ "$(q "select count(*) from pipeline.pdesc_reader_state")" -le 1 ] || { echo "the reader state has more than one row"; exit 1; }
echo "shape: the signature asks for the reader once; the reader is one primary-key row of pipeline.pdesc_reader_state and never reads the reads"

# forward recovery: the earlier bodies are restored byte for byte, the old behaviour returns, running it again changes nothing, the migration applies again
snap "$W/3"
$P -1 -At -f $REC >/dev/null 2>&1 || { echo "the forward recovery failed"; exit 1; }
[ "$(q "select md5(prosrc) from pg_proc where oid = '$SIG'::regprocedure")" = "$BEFORE_MD5" ] || { echo "the forward recovery did not restore the earlier signature body"; exit 1; }
[ "$(q "select md5(prosrc) from pg_proc where oid = '$SEL'::regprocedure")" = "$SEL_BEFORE_MD5" ] || { echo "the forward recovery did not restore the earlier picker body"; exit 1; }
snap "$W/4"
[ "$(comm -23 "$W/3.fn" "$W/4.fn" | sed 's/ [0-9a-f]*$//' | sort)" = "$want" ] || { echo "the forward recovery changed more than the two functions"; exit 1; }
for f in set out l4 rd ev cron ix cols tabs trg; do cmp -s "$W/3.$f" "$W/4.$f" || { echo "the forward recovery changed $f"; exit 1; }; done
RECS=$(run_scen $F/scenarios.sql); [ "$RECS" = "$BEFORE" ] || { echo "after the forward recovery the scenarios differ from the live behaviour:"; diff <(echo "$BEFORE") <(echo "$RECS"); exit 1; }
$P -1 -At -f $REC >/dev/null 2>&1 || { echo "the forward recovery failed the second time"; exit 1; }
snap "$W/5"; for f in fn set out; do cmp -s "$W/4.$f" "$W/5.$f" || { echo "the second recovery run changed $f"; exit 1; }; done
OUT=$($P -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -8; exit 1; }
[ "$(q "select md5(prosrc) from pg_proc where oid = '$SIG'::regprocedure")" = "$AFTER_MD5" ] && [ "$(q "select md5(prosrc) from pg_proc where oid = '$SEL'::regprocedure")" = "$SEL_AFTER_MD5" ] || { echo "the migration did not apply again after the recovery"; exit 1; }
echo "recovery: supabase/held/pdesc_signature_reader_forward_recovery.sql restores body md5 $BEFORE_MD5 and $SEL_BEFORE_MD5 byte for byte, changes nothing else, gives the live behaviour again, is a no-op the second time; the migration applies again after it"
echo "pdesc-signature-reader: done"
