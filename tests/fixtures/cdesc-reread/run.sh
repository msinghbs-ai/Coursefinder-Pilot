#!/usr/bin/env bash
# Guards: F-CDESC first-cycle check of Pilot #1047: migration 20261112190000 edits exactly one body (the gap function, md5 from the one 20261112170000 left to the stated md5), changes only the claim-words setting value (with a
# control event) and only the reasons of worker v0.72.0's unsupported_sentence and quote_not_on_page holds made by cdesc-source-grounded-v1; applies twice with no change; stops over a changed live body with nothing applied; its held
# recovery restores the body, the setting and the reasons; and behaves as scenarios.sql says, with every REGRESSION check failing on the database from before it. Scratch PostgreSQL only. Builds on cdesc-source-grounded. CRR_KEEP=1 keeps the databases.
set -euo pipefail
cd "$(dirname "$0")/../../.."
export LC_ALL=C # fixed: one byte order for sort and comm
DB=${CRR_DB:-g_cdesc_reread}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
M=supabase/migrations/20261112190000_cf247_cdesc_first_cycle_reread.sql
HELD=supabase/held/cdesc_reread_forward_recovery.sql
F=tests/fixtures/cdesc-reread
SIG='security.enrich_course_text_gaps_v1(text[])'; BEFORE=ddba9b553a63a9e38c49782a0b0d29c9; AFTER=d117edb4198b81a692e93af9a937110e
q() { psql -X -d "$1" -Atc "$2"; }
W=$(mktemp -d)
cleanup() { local code=$?; trap - EXIT; rm -rf "$W"; if [ -z "${CRR_KEEP:-}" ]; then for d in "$DB" "${DB}_old" "${DB}_csg" "${DB}_t" "${DB}_rf" "${DB}_s"; do dropdb --if-exists "$d" >/dev/null 2>&1 || true; done; fi; exit "$code"; }
trap cleanup EXIT
BASE=$(CSG_KEEP=1 CSG_DB=${DB}_csg bash tests/fixtures/cdesc-source-grounded/run.sh 2>&1) || { echo "$BASE" | tail -15; echo "the cdesc-source-grounded harness failed"; exit 1; }
for d in ${DB}_csg_old ${DB}_csg_sub ${DB}_csg_sub_old ${DB}_csg_sub_thr ${DB}_csg_sub_thr_old; do dropdb --if-exists "$d" >/dev/null 2>&1 || true; done
echo "base: the cdesc-source-grounded harness built the database (migrations up to 20261112170000)"
dropdb --if-exists "$DB" >/dev/null 2>&1 || true; createdb -T "${DB}_csg" "$DB"
[ "$(q $DB "select md5(prosrc) from pg_proc where oid = '$SIG'::regprocedure")" = $BEFORE ] || { echo "the loaded gap function is not the one 20261112170000 left"; exit 1; }
grep -qF -- "$SIG  $BEFORE -> $AFTER" $M || { echo "the header does not record the edit"; exit 1; }
# readings the relabel must and must not touch
psql -X -q -v ON_ERROR_STOP=1 -d $DB <<'SQL'
insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state, source, reason, value) select j, c.provider_id, c.id, f, st, so, r, v::jsonb from (select x.*, row_number() over () rn from (values
 ('00000000-0000-4000-c000-0000000000f2'::uuid, 'description', 'skipped', 'ai_stored', 'held: unsupported_sentence: a sentence is not supported by its quote (0.4): x', '{"prompt_version": "cdesc-source-grounded-v1", "reader": {"worker": "coverage-sweep-worker-v0.72.0"}}'),
 ('00000000-0000-4000-c000-0000000000f2', 'description', 'skipped', 'ai_stored', 'held: quote_not_on_page: a sentence''s words are not on the course page: x', '{"prompt_version": "cdesc-source-grounded-v1", "reader": {"worker": "coverage-sweep-worker-v0.72.0"}}'),
 ('00000000-0000-4000-c000-0000000000f2', 'description', 'skipped', 'ai_stored', 'held: copied_sentence: x', '{"prompt_version": "cdesc-source-grounded-v1", "reader": {"worker": "coverage-sweep-worker-v0.72.0"}}'),
 ('00000000-0000-4000-c000-0000000000f2', 'description', 'skipped', 'ai_stored', 'held: unsupported_sentence: x', '{"prompt_version": "cdesc-source-grounded-v1", "reader": {"worker": "coverage-sweep-worker-v0.72.1"}}'),
 ('00000000-0000-4000-c000-0000000000f2', 'description', 'skipped', 'ai_stored', 'held: unsupported_sentence: x', '{"reader": {"prompt": "course-text-v2", "worker": "coverage-sweep-worker-v0.71.0"}}')) x(j, f, st, so, r, v)) x join (select id, provider_id, row_number() over (order by id) rn from catalogue.courses) c on c.rn = x.rn;
SQL
dropdb --if-exists "${DB}_old" >/dev/null 2>&1; createdb -T "$DB" "${DB}_old"
FNS="select p.oid::regprocedure::text || ' ' || md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public', 'api', 'pipeline', 'catalogue') and p.prokind = 'f' order by 1"
SET="select key || '=' || value::text from pipeline.platform_toolset_settings order by 1"
RS="select id || ' ' || state || ' ' || coalesce(reason, '') || ' ' || md5(coalesce(value::text, '')) from pipeline.field_enrich_items order by id"
snap() { q $DB "$FNS" | sort > "$1.fn"; q $DB "$SET" | sort > "$1.set"; q $DB "$RS" > "$1.items"; for t in pipeline.layer4_review_items catalogue.courses; do q $DB "select md5(string_agg(x::text, '|' order by x::text)) from $t x"; done > "$1.rows"; }
snap "$W/0"
psql -X -q -v ON_ERROR_STOP=1 -d $DB -1 -At -f $M >/dev/null
snap "$W/1"
[ "$(comm -23 "$W/0.fn" "$W/1.fn" | sed 's/ .*//')" = "$SIG" ] && grep -qF "$SIG $AFTER" "$W/1.fn" || { echo "the changed functions are not exactly the gap function at $AFTER"; comm -3 "$W/0.fn" "$W/1.fn"; exit 1; }
[ "$(comm -13 <(sed 's/ .*//' "$W/0.fn" | sort -u) <(sed 's/ .*//' "$W/1.fn" | sort -u) | wc -l)" = 0 ] || { echo "a function was added"; exit 1; }
[ "$(comm -23 "$W/0.set" "$W/1.set" | sed 's/=.*//')" = "enrich.course_description_claim_words" ] || { echo "the settings changed are not exactly the claim words"; comm -3 "$W/0.set" "$W/1.set"; exit 1; }
grep -q '^enrich.course_description_claim_words=.*"students"' "$W/1.set" && { echo "students is still a claim word"; exit 1; }
[ "$(q $DB "select count(*) from pipeline.admin_control_events where target = 'pipeline.enrich.course_description_claim_words'")" = 1 ] || { echo "no control event for the setting"; exit 1; }
CH=$(diff <(cut -d' ' -f1 "$W/0.items") <(cut -d' ' -f1 "$W/1.items") | wc -l); [ "$CH" = 0 ] || { echo "readings were added or removed"; exit 1; }
RL=$(comm -13 <(sort "$W/0.items") <(sort "$W/1.items") | grep -c ' reread: v0.72.0 mapping: held: \(unsupported_sentence\|quote_not_on_page\):' || true)
[ "$RL" = 2 ] && [ "$(comm -13 <(sort "$W/0.items") <(sort "$W/1.items") | wc -l)" = 2 ] || { echo "the relabel did not touch exactly the two v0.72.0 mapping holds"; comm -3 <(sort "$W/0.items") <(sort "$W/1.items"); exit 1; }
diff <(sed 's/ [^ ]*$//; s/^\([0-9]* [a-z]*\) .*/\1/' "$W/0.items") <(sed 's/ [^ ]*$//; s/^\([0-9]* [a-z]*\) .*/\1/' "$W/1.items") >/dev/null || { echo "a reading's state changed"; exit 1; }
cmp -s <(awk '{print $NF}' "$W/0.items") <(awk '{print $NF}' "$W/1.items") || { echo "a reading's value changed"; exit 1; }
cmp -s "$W/0.rows" "$W/1.rows" || { echo "Layer 4 items or courses changed"; exit 1; }
echo "applied: only the gap function (to $AFTER) and the claim words (students removed, one control event) changed; exactly the two v0.72.0 mapping holds were marked reread:; no state, value, Layer 4 item or course changed"
psql -X -q -v ON_ERROR_STOP=1 -d $DB -1 -At -f $M >/dev/null; snap "$W/2"
for f in fn set items rows; do cmp -s "$W/1.$f" "$W/2.$f" || { echo "the second run changed $f"; exit 1; }; done
echo "applied again: no change"
createdb -T "${DB}_old" "${DB}_t"
psql -X -q -d "${DB}_t" -c "create or replace function security.enrich_course_text_gaps_v1(p_fields text[]) returns table(provider_id uuid, course_id uuid, field text, pri int) language sql as \$\$ select null::uuid, null::uuid, null::text, 0 where false \$\$"
if OUT=$(psql -X -d "${DB}_t" -q -At -v ON_ERROR_STOP=1 -1 -f $M 2>&1); then echo "the migration applied over a changed live body"; exit 1; fi
grep -qF 'differs from the definition this change replaces' <<<"$OUT" || { echo "unexpected refusal: $OUT" | tail -3; exit 1; }
[ "$(q ${DB}_t "select count(*) from pipeline.field_enrich_items where reason like 'reread:%'")" = 0 ] && [ "$(q ${DB}_t "select value ? 'students' from pipeline.platform_toolset_settings where key = 'enrich.course_description_claim_words'")" = t ] || { echo "the refused migration left something behind"; exit 1; }
dropdb "${DB}_t"
echo "refused: a changed live body stops the migration and nothing is applied"
createdb -T "$DB" "${DB}_rf"
psql -X -d "${DB}_rf" -q -v ON_ERROR_STOP=1 -f $HELD >/dev/null; psql -X -d "${DB}_rf" -q -v ON_ERROR_STOP=1 -f $HELD >/dev/null
[ "$(q ${DB}_rf "select md5(prosrc) from pg_proc where oid = '$SIG'::regprocedure")" = $BEFORE ] || { echo "the recovery did not restore the body"; exit 1; }
cmp -s <(q ${DB}_rf "$SET" | sort) "$W/0.set" || { echo "the recovery did not restore the settings"; exit 1; }
cmp -s <(q ${DB}_rf "select id || ' ' || state || ' ' || coalesce(reason, '') from pipeline.field_enrich_items order by id") <(sed 's/ [^ ]*$//' "$W/0.items") || { echo "the recovery did not restore the reasons"; exit 1; }
dropdb "${DB}_rf"
echo "forward recovery: the held file restores the body, the claim words and the reasons (twice)"
{ sed -n '5,88p' tests/fixtures/cdesc-machine/scenarios.sql; cat $F/scenarios.sql; } > "$W/s.sql"
for pair in "$DB:new" "${DB}_old:old"; do
  d=${pair%%:*}; mode=${pair##*:}
  dropdb --if-exists "${DB}_s" >/dev/null 2>&1; createdb -T "$d" "${DB}_s"
  OUT=$(psql -X -d "${DB}_s" -v ON_ERROR_STOP=0 -f "$W/s.sql" 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\|WARNING\):  /\1 /p') || true
  if [ "$mode" = new ]; then
    if echo "$OUT" | grep -E 'FAIL|^ERROR'; then echo "scenarios FAILED on the migrated database"; exit 1; fi
    echo "$OUT" | grep -q 'cdrr: all' || { echo "the scenarios did not finish"; echo "$OUT" | tail -5; exit 1; }
    echo "$OUT" | grep -E '\[pass\]' | sed 's/^NOTICE /reread: /'
  else
    FAILS=$(echo "$OUT" | grep -c 'REGRESSION.*\[FAIL\]' || true); EXPECTED=$(grep -c "expect('REGRESSION" $F/scenarios.sql)
    [ "$FAILS" = "$EXPECTED" ] || { echo "only $FAILS of $EXPECTED REGRESSION checks fail before the migration"; echo "$OUT" | grep REGRESSION; exit 1; }
    echo "regression: $FAILS of the $EXPECTED REGRESSION checks fail on the database from before the migration"
  fi
  dropdb --if-exists "${DB}_s" >/dev/null 2>&1
done
echo "cdesc-reread: done"
