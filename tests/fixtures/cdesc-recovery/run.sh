#!/usr/bin/env bash
# Guards: F-CDESC recovery and throughput (S2-CF directive, Platform Admin 13 Nov 2026 10:25): migration 20261113280000 edits exactly two bodies (the subset plan and the subset recovery, each md5 from live to the stated md5), adds one function and one index,
# changes the job's schedule and its catalogue text, changes no setting and no reading here; applies twice with no change; stops over a changed live body with nothing applied; its held recovery restores both bodies and the schedule (twice) and the migration comes back;
# the machine check's exact-text lookup uses the new index; and behaves as scenarios.sql says, with every REGRESSION check failing on the database from before it. Scratch PostgreSQL only. Builds on cdesc-reread. CRT_KEEP=1 keeps the databases.
set -euo pipefail
cd "$(dirname "$0")/../../.."
export LC_ALL=C # fixed: one byte order for sort and comm
DB=${CRT_DB:-g_cdesc_recovery}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
M=supabase/migrations/20261113280000_cf247_cdesc_recovery_throughput.sql
HELD=supabase/held/cdesc_recovery_throughput_forward_recovery.sql
F=tests/fixtures/cdesc-recovery
SIG='security.cdesc_subset_plan_v1(uuid,uuid,jsonb)'; BEFORE=1350a9c8f46331a5469cabbd60acf660; AFTER=3c263a1984a33a133a331883cc6f8eae
SIG2='security.cdesc_subset_recover_v1()'; BEFORE2=5f73026bc5ed0350107a97a0953f7588; AFTER2=1652bacc1954b2a9d51ef28d6b411f35
OLD_S='4,14,24,34,44,54 * * * *'; NEW_S='0-34/2,44,50-58/2 * * * *'
q() { psql -X -d "$1" -Atc "$2"; }
W=$(mktemp -d)
cleanup() { local code=$?; trap - EXIT; rm -rf "$W"; if [ -z "${CRT_KEEP:-}" ]; then for d in "$DB" "${DB}_old" "${DB}_crr" "${DB}_t" "${DB}_rf" "${DB}_s"; do dropdb --if-exists "$d" >/dev/null 2>&1 || true; done; fi; exit "$code"; }
trap cleanup EXIT
BASE=$(CRR_KEEP=1 CRR_DB=${DB}_crr bash tests/fixtures/cdesc-reread/run.sh 2>&1) || { echo "$BASE" | tail -15; echo "the cdesc-reread harness failed"; exit 1; }
for d in ${DB}_crr_old ${DB}_crr_csg ${DB}_crr_t ${DB}_crr_rf ${DB}_crr_s; do dropdb --if-exists "$d" >/dev/null 2>&1 || true; done
echo "base: the cdesc-reread harness built the database (migrations up to 20261112190000)"
dropdb --if-exists "$DB" >/dev/null 2>&1 || true; createdb -T "${DB}_crr" "$DB"
[ "$(q $DB "select md5(prosrc) from pg_proc where oid = '$SIG'::regprocedure")" = $BEFORE ] && [ "$(q $DB "select md5(prosrc) from pg_proc where oid = '$SIG2'::regprocedure")" = $BEFORE2 ] || { echo "the loaded plan or recovery is not the live body"; exit 1; }
grep -qF -- "security.cdesc_subset_plan_v1  $BEFORE -> $AFTER" $M && grep -qF -- "security.cdesc_subset_recover_v1  $BEFORE2 -> $AFTER2" $M || { echo "the header does not record the edits"; exit 1; }
[ "$(q $DB "select schedule from cron.job where jobname = 'course-description-machine'")" = "$OLD_S" ] || { echo "the loaded job is not on the ten-minute schedule"; exit 1; }
dropdb --if-exists "${DB}_old" >/dev/null 2>&1; createdb -T "$DB" "${DB}_old"
FNS="select p.oid::regprocedure::text || ' ' || md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public', 'api', 'pipeline', 'catalogue') and p.prokind = 'f' order by 1"
SET="select key || '=' || value::text from pipeline.platform_toolset_settings order by 1"
RS="select id || ' ' || state || ' ' || coalesce(reason, '') || ' ' || md5(coalesce(value::text, '')) from pipeline.field_enrich_items order by id"
IDX="select schemaname || '.' || indexname from pg_indexes where schemaname in ('pipeline', 'catalogue', 'search') order by 1"
snap() { q $DB "$FNS" | sort > "$1.fn"; q $DB "$SET" | sort > "$1.set"; q $DB "$RS" > "$1.items"; q $DB "$IDX" > "$1.idx"; q $DB "select jobname || ' ' || schedule || ' ' || command from cron.job order by 1" > "$1.cron"; for t in pipeline.layer4_review_items catalogue.courses; do q $DB "select md5(string_agg(x::text, '|' order by x::text)) from $t x"; done > "$1.rows"; }
snap "$W/0"
psql -X -q -v ON_ERROR_STOP=1 -d $DB -1 -At -f $M >/dev/null 2>&1
snap "$W/1"
[ "$(comm -23 "$W/0.fn" "$W/1.fn" | sed 's/ .*//' | sort | tr '\n' ' ')" = "$(printf '%s\n' "$SIG" "$SIG2" | sort | tr '\n' ' ')" ] && grep -qF "$SIG $AFTER" "$W/1.fn" && grep -qF "$SIG2 $AFTER2" "$W/1.fn" || { echo "the changed functions are not exactly the plan and the recovery at the stated md5"; comm -3 "$W/0.fn" "$W/1.fn"; exit 1; }
[ "$(comm -13 <(sed 's/ .*//' "$W/0.fn" | sort -u) <(sed 's/ .*//' "$W/1.fn" | sort -u) | tr '\n' ' ')" = "security.cdesc_points_back_v1(text) " ] || { echo "unexpected functions added"; exit 1; }
[ "$(comm -13 "$W/0.idx" "$W/1.idx" | tr '\n' ' ')" = "pipeline.layer4_review_items_field_text_md5_idx " ] && [ -z "$(comm -23 "$W/0.idx" "$W/1.idx")" ] || { echo "the indexes changed are not exactly the one added"; exit 1; }
cmp -s "$W/0.set" "$W/1.set" && cmp -s "$W/0.items" "$W/1.items" && cmp -s "$W/0.rows" "$W/1.rows" || { echo "a setting, a reading, a Layer 4 item or a course changed"; exit 1; }
[ "$(diff "$W/0.cron" "$W/1.cron" | grep -c '^[<>]')" = 2 ] && grep -qF "course-description-machine $NEW_S select security.course_description_machine_run_v1()" "$W/1.cron" || { echo "the job changes are not exactly the one schedule"; diff "$W/0.cron" "$W/1.cron"; exit 1; }
q $DB "select description from pipeline.automation_catalogue where jobname = 'course-description-machine'" | grep -q '^Every 2 minutes (not from :35 to :43 or from :45 to :49)' || { echo "the catalogue row does not state the new schedule"; exit 1; }
echo "applied: only the plan and the recovery changed (to the stated md5), one function and one index were added, the job runs every two minutes with its catalogue text; no setting, reading, Layer 4 item or course changed"
psql -X -q -v ON_ERROR_STOP=1 -d $DB -1 -At -f $M >/dev/null 2>&1; snap "$W/2"
for f in fn set items rows idx cron; do cmp -s "$W/1.$f" "$W/2.$f" || { echo "the second run changed $f"; exit 1; }; done
echo "applied again: no change"
# the data marks, on invented readings: an attempt that ended on a rule the change moves is cleared, others stay; a key-limit refusal is marked reread:, another failure stays
createdb -T "${DB}_old" "${DB}_t"
psql -X -q -v ON_ERROR_STOP=1 -d "${DB}_t" <<'SQL'
insert into pipeline.admin_jobs(id) values ('00000000-0000-4000-c000-0000000000f9');
insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state, source, reason, value)
select '00000000-0000-4000-c000-0000000000f9'::uuid, c.provider_id, c.id, 'description', x.st, 'ai_stored', x.r, x.v::jsonb
  from (values (1, 'skipped', 'held: unsupported_claim: x', '{"mark": "a", "subset_attempt": {"result": "depends_on_dropped_sentence", "stamp": "s"}}'),
               (2, 'skipped', 'held: unsupported_sentence: x', '{"mark": "b", "subset_attempt": {"result": "nothing_to_drop", "stamp": "s"}}'),
               (3, 'skipped', 'held: length: x', '{"mark": "c", "subset_attempt": {"result": "over_length_needs_decision", "stamp": "s"}}'),
               (4, 'failed', 'HTTP 403: {"message":"Key limit exceeded (weekly limit). Manage it"}', '{"mark": "d"}'),
               (5, 'failed', 'no answer could be recorded after 3 tries', '{"mark": "e"}')) x(rn, st, r, v)
  join (select id, provider_id, row_number() over (order by id) rn from catalogue.courses k where k.lifecycle_status = 'active' and nullif(btrim(k.description), '') is null) c on c.rn = x.rn;
SQL
[ "$(q "${DB}_t" "select count(*) from pipeline.field_enrich_items where value ? 'mark'")" = 5 ] || { echo "the mark readings were not all made"; exit 1; }
psql -X -q -v ON_ERROR_STOP=1 -d "${DB}_t" -1 -At -f $M >/dev/null 2>&1
[ "$(q "${DB}_t" "select string_agg((value->>'mark') || ':' || state || ':' || (value ? 'subset_attempt')::text || ':' || (reason like 'reread: the AI service refused%')::text, ' ' order by value->>'mark') from pipeline.field_enrich_items where value ? 'mark'")" = "a:skipped:false:false b:skipped:false:false c:skipped:true:false d:skipped:false:true e:failed:false:false" ] \
  || { echo "the data marks are not exactly: attempts a and b cleared, c kept; refusal d marked reread:, failure e kept"; q "${DB}_t" "select value->>'mark', state, reason, value from pipeline.field_enrich_items where value ? 'mark' order by 1"; exit 1; }
echo "marks: the two attempts the change moves are cleared and the size-only attempt kept; the key-limit refusal is marked reread: and another failure is left failed"
dropdb "${DB}_t"; createdb -T "${DB}_old" "${DB}_t"
psql -X -q -d "${DB}_t" -c "comment on function security.cdesc_subset_plan_v1(uuid,uuid,jsonb) is 'x'" -c "do \$\$ declare d text := pg_get_functiondef('security.cdesc_subset_recover_v1()'::regprocedure); begin execute replace(d, 'time_box_reached', 'time_box_reached_x'); end \$\$"
q "${DB}_t" "$FNS" | sort > "$W/t0.fn"
if psql -X -q -v ON_ERROR_STOP=1 -d "${DB}_t" -1 -f $M >/dev/null 2>"$W/t.err"; then echo "the migration applied over a changed live body"; exit 1; fi
grep -q 'differs from the definition this change replaces' "$W/t.err" || { echo "the refusal does not name the changed body"; cat "$W/t.err"; exit 1; }
q "${DB}_t" "$FNS" | sort > "$W/t1.fn"; cmp -s "$W/t0.fn" "$W/t1.fn" && [ "$(q "${DB}_t" "select schedule from cron.job where jobname = 'course-description-machine'")" = "$OLD_S" ] && [ -z "$(q "${DB}_t" "select to_regclass('pipeline.layer4_review_items_field_text_md5_idx')")" ] || { echo "a refused run left something behind"; exit 1; }
dropdb "${DB}_t"
echo "refused: over a changed recovery body the migration stops and leaves nothing (no function, no index, no schedule change)"
createdb -T "$DB" "${DB}_rf"
for i in 1 2; do psql -X -q -v ON_ERROR_STOP=1 -d "${DB}_rf" -1 -f $HELD >/dev/null 2>&1 || { echo "the held recovery failed (run $i)"; exit 1; }; done
[ "$(q "${DB}_rf" "select md5(prosrc) from pg_proc where oid = '$SIG'::regprocedure")" = $BEFORE ] && [ "$(q "${DB}_rf" "select md5(prosrc) from pg_proc where oid = '$SIG2'::regprocedure")" = $BEFORE2 ] && [ "$(q "${DB}_rf" "select schedule from cron.job where jobname = 'course-description-machine'")" = "$OLD_S" ] || { echo "the held recovery did not restore the bodies and the schedule"; exit 1; }
psql -X -q -v ON_ERROR_STOP=1 -d "${DB}_rf" -1 -f $M >/dev/null 2>&1 && [ "$(q "${DB}_rf" "select md5(prosrc) from pg_proc where oid = '$SIG'::regprocedure")" = $AFTER ] && [ "$(q "${DB}_rf" "select schedule from cron.job where jobname = 'course-description-machine'")" = "$NEW_S" ] || { echo "the migration did not come back after the recovery"; exit 1; }
dropdb "${DB}_rf"
echo "forward recovery: the held file restores both bodies and the ten-minute schedule (twice); the migration then applies again"
# the exact-text lookup of the machine check uses the index (the predicate exactly as the check writes it)
PLAN=$(psql -X -d $DB -Atc "set enable_seqscan = off; explain select 1 from pipeline.layer4_review_items o where o.field_code = 'course_description_first_read' and o.status not in ('pending', 'approved', 'edited_approved') and md5(security.cdesc_norm_v1(o.proposed_value->>'description')) = md5('x')")
echo "$PLAN" | grep -q 'layer4_review_items_field_text_md5_idx' || { echo "the exact-text lookup does not use the index"; echo "$PLAN"; exit 1; }
echo "index: the machine check's exact-text lookup can use layer4_review_items_field_text_md5_idx"
pre() { sed -n '5,88p' tests/fixtures/cdesc-machine/scenarios.sql; sed -n '5,75p' tests/fixtures/cdesc-subset/scenarios.sql; }
for pair in "$DB:new" "${DB}_old:old"; do
  d=${pair%%:*}; mode=${pair##*:}
  dropdb --if-exists "${DB}_s" >/dev/null 2>&1; createdb -T "$d" "${DB}_s"
  { pre; cat $F/scenarios.sql; } > "$W/$mode.sql"
  OUT=$(psql -X -d "${DB}_s" -v ON_ERROR_STOP=1 -f "$W/$mode.sql" 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\|WARNING\):  /\1 /p') || true
  if [ "$mode" = new ]; then
    if echo "$OUT" | grep -E 'FAIL|ERROR'; then echo "scenarios FAILED on the migrated database"; exit 1; fi
    echo "$OUT" | grep -q 'crt: all' || { echo "the scenarios did not finish"; echo "$OUT" | tail -5; exit 1; }
    echo "$OUT" | grep -E '\[pass\]' | sed 's/^NOTICE /recovery: /'
  else
    FAILS=$(echo "$OUT" | grep -c 'REGRESSION.*\[FAIL\]' || true); EXPECTED=$(grep -c "expect('REGRESSION" $F/scenarios.sql)
    [ "$FAILS" = "$EXPECTED" ] || { echo "only $FAILS of the $EXPECTED REGRESSION checks fail on the database from before the migration"; echo "$OUT" | grep -E 'REGRESSION|ERROR'; exit 1; }
    echo "regression: $FAILS of the $EXPECTED REGRESSION checks fail on the database from before the migration"
  fi
  dropdb --if-exists "${DB}_s" >/dev/null 2>&1
done
echo "cdesc-recovery: done"
