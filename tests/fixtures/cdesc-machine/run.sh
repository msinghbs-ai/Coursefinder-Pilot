#!/usr/bin/env bash
# Guards: F-CDESC (Platform Admin decision 10 Nov 2026, course descriptions: narrow source-verified machine admission): migrations 20261110060000 and 20261110060100 add the ledger, the one switch (ships 0), the safe-class
# evaluator, the admission, withdrawal, settlement, the reading hook and the catalogued job; they change no existing function, setting value, Layer 4 item, description or reading; refuse and change nothing when a live function they
# call is missing or applied out of order; apply twice with no change; and behave as scenarios.sql says (wrong page, other course, obsolete page, unsupported claim, retry, rejection memory, lock, empty answer, duplicates, timeout,
# cost cap, consumer lag and mismatch, ambiguous binding, hidden provider, idempotence, withdrawal, forward recovery) against production-shaped constraints and triggers.
# Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds the database with the course-description-backpressure harness (production-parity fixture plus 20261106500000,
# 20261107120000 and 20261108130000), adds the stand-ins in stubs.sql and the live definitions in live/ (each checked against its live body md5, read 10 Nov 2026), then applies the two migrations, each twice.
# Then applies 20261110100000 (Data Delivery stage counts) and 20261110100100 (wrong_page_kind) and runs the earlier scenarios again with both in place, then scenarios_visible.sql. Drops the database at the end (CDM_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
export LC_ALL=C # fixed: one byte order for sort and comm, whatever the runner's locale
DB=${CDM_DB:-g_cdesc_machine}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
M1=supabase/migrations/20261110060000_cf247_cdesc_machine_policy_shadow.sql
M2=supabase/migrations/20261110060100_cf247_cdesc_machine_admission.sql
F=tests/fixtures/cdesc-machine
q() { psql -X -d "$DB" -Atc "$1"; }
BASE=$(CDBP_KEEP=1 CDBP_DB=$DB bash tests/fixtures/course-description-backpressure/run.sh 2>&1) || { echo "$BASE" | tail -15; echo "the base harness failed"; exit 1; }
W=$(mktemp -d)
cleanup() { local code=$?; trap - EXIT; rm -rf "$W"; if [ -z "${CDM_KEEP:-}" ]; then dropdb --if-exists "$DB" >/dev/null 2>&1 || true; dropdb --if-exists "${DB}_refuse" >/dev/null 2>&1 || true; dropdb --if-exists "${DB}_oldchk" >/dev/null 2>&1 || true; fi; exit "$code"; }
trap cleanup EXIT
echo "base: course-description-backpressure harness built the database (production-parity fixture, 20261106500000, 20261107120000, 20261108130000)"
$P -f $F/stubs.sql
$P -f $F/seed.sql
for f in security.pdesc_claim_check_v1 security.pdesc_machine_neutral_supported_v1 security.pdesc_machine_text_check_ctx_v1 security.pdesc_machine_text_check_v1 security.enrich_item_held_v1 security.layer4_pace_v1 security.data_delivery_v1; do $P -c "set check_function_bodies = off" -f $F/live/$f.sql; done
declare -A LIVE=( ['security.pdesc_claim_check_v1(text,text,text)']=5e256534e43073bc32f842bee2e50c98 ['security.pdesc_machine_neutral_supported_v1(text,jsonb)']=8601c0066d7bde714fc753e5ae0ba0db
                  ['security.pdesc_machine_text_check_ctx_v1(uuid,text,text[],jsonb)']=e9a12bc0383e321345fc015f89768042 ['security.pdesc_machine_text_check_v1(uuid,text,text[])']=bafcb58c2ac586829ce4f1b1d2780a44
                  ['security.course_description_check_v1(uuid,jsonb)']=0d3a4cc7811eddaf6bb94307b542cc60 ['security.course_description_check_with_v1(uuid,jsonb,jsonb,jsonb)']=3bb5d62b5e86cd7c76707171e02a3ae5
                  ['security.course_description_trusted_v1(uuid)']=ae8b327f85f0262b3d0b878010a4af3c ['security.coverage_identity_allowed(uuid,text,text)']=dc66799e79f91620169fc2c17d621349
                  ['security.layer4_course_description_apply_v1(uuid,uuid,jsonb,text)']=04059b123d1afb184adfb8ca9d7af906 ['security.enrich_course_text_record_v1(bigint,jsonb)']=c52c1969a80f2d3db1d81a4e46a49cd9
                  ['security.pdesc_has_term_v1(text,text)']=2900b13238674e92caa77f8339f81698 ['security.pdesc_support_v1(text,text)']=2065dfd6987b47852d267f5d33dd9056
                  ['security.pdesc_words_v1(text)']=0ca18e0d985cf01902977d992e364815 ['security.pipeline_num_v1(text,numeric)']=cbde6549dbdab8cad5ad961e8278e86c
                  ['security.enrich_course_text_gaps_v1(text[])']=5352bc7ea7bbf3ef00bd616f2897f2f4 ['security.enrich_item_held_v1(uuid,text)']=78c7102adf2804fb536eb2e263264edc
                  ['security.layer4_pace_v1()']=344a3abad89b63baf9316a5d85f5f8ff ['security.data_delivery_v1()']=916e015e0cce905c97e17786b4c2ada1 ['security.course_description_summary_v1(uuid,boolean)']=8e284898fdc7bda9dcbcc9d85acabace
                  ['security.course_description_capacity_v1()']=ef83be9476da04995081ac04ab517bf0 ['security.course_description_sample_report_v1()']=5854cf436c26cb814033f58a47e4d33e
                  ['security.course_description_trusted_v1(uuid)']=ae8b327f85f0262b3d0b878010a4af3c )
for sig in "${!LIVE[@]}"; do
  [ "$(q "select md5(prosrc) from pg_proc where oid = '$sig'::regprocedure")" = "${LIVE[$sig]}" ] || { echo "the loaded $sig differs from live ${LIVE[$sig]}"; exit 1; }
done
echo "loaded: ${#LIVE[@]} definitions the rule calls = live (body md5, read 10 Nov 2026)"

FNS="select p.oid::regprocedure::text || ' ' || md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public', 'api') and p.prokind = 'f' order by 1"
SET="select key || '=' || value::text from pipeline.platform_toolset_settings order by 1"
snap() { q "$FNS" | sort > "$1.fn"; q "$SET" | sort > "$1.set"; q "select count(*) from pipeline.layer4_review_items" > "$1.l4"; q "select count(*) from pipeline.field_enrich_items" > "$1.rd"; q "select count(*) from catalogue.courses where nullif(btrim(description), '') is not null" > "$1.desc"; q "select md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from (select * from pipeline.layer4_review_items) t" > "$1.l4rows"; }

# out of order and missing live functions: refused, nothing applied
RF=${DB}_refuse
dropdb --if-exists $RF >/dev/null 2>&1; createdb -T $DB $RF
if OUT=$(psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $M2 2>&1); then echo "M2 applied before M1"; exit 1; fi
grep -qF 'apply 20261110060000 first' <<<"$OUT" || { echo "M2 refusal is not the expected one: $OUT" | tail -3; exit 1; }
psql -X -q -d $RF -c "drop function security.pdesc_machine_text_check_ctx_v1(uuid,text,text[],jsonb) cascade" >/dev/null
if OUT=$(psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $M1 2>&1); then echo "M1 applied without the admission policy function"; exit 1; fi
grep -qF 'is missing' <<<"$OUT" || { echo "M1 refusal is not the expected one: $OUT" | tail -3; exit 1; }
[ "$(psql -X -d $RF -Atc "select to_regclass('pipeline.course_description_machine_admissions') is null")" = t ] || { echo "the refused M1 left a table"; exit 1; }
dropdb --if-exists $RF >/dev/null 2>&1
echo "refused: M2 before M1 and M1 without a live function it calls both raise, and change nothing"
# applied before the control class column exists (20261110080000 not yet applied): the switch is still added, the column is not created here
createdb -T $DB $RF
psql -X -q -d $RF -c "alter table pipeline.platform_toolset_settings drop column control_class" >/dev/null
psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $M1 >/dev/null 2>&1 || { echo "M1 failed where the control class column does not exist yet"; exit 1; }
[ "$(psql -X -d $RF -Atc "select (select count(*) from pipeline.platform_toolset_settings where key = 'enrich.course_description_machine_on')::text || (select count(*) from information_schema.columns where table_name = 'platform_toolset_settings' and column_name = 'control_class')::text")" = 10 ] || { echo "M1 without the control class column: the switch is missing or the column was created"; exit 1; }
dropdb --if-exists $RF >/dev/null 2>&1
echo "applied without the control class column: the switch is added, the column is not created by this change"

# a person's Layer 4 decisions and the four measures as they answer today (compared after the migrations)
$P -f $F/measures_before.sql >/dev/null
snap "$W/0"
OUT=$($P -1 -At -f $M1 2>&1) || { echo "$OUT" | tail -8; exit 1; }
OUT=$($P -1 -At -f $M2 2>&1) || { echo "$OUT" | tail -8; exit 1; }
snap "$W/1"
# nothing existing changed: every function that was there has the same body; the only new setting is the switch at 0; no Layer 4 item, reading or description changed
# the five governed in-place edits (a machine decision is not a person's): security.course_description_trusted_v1 and the four existing measures; each from its live md5 to the md5 the migration states
EXPECT_OLD=$(printf '%s\n' 'security.course_description_trusted_v1(uuid) ae8b327f85f0262b3d0b878010a4af3c' 'security.course_description_summary_v1(uuid,boolean) 8e284898fdc7bda9dcbcc9d85acabace' 'security.course_description_capacity_v1() ef83be9476da04995081ac04ab517bf0' 'security.course_description_sample_report_v1() 5854cf436c26cb814033f58a47e4d33e' 'security.layer4_pace_v1() 344a3abad89b63baf9316a5d85f5f8ff' | sort)
EXPECT_NEW=$(printf '%s\n' 'security.course_description_trusted_v1(uuid) 16568089f58b528b9a6647e78eca3ed5' 'security.course_description_summary_v1(uuid,boolean) d5c88f55bcaadee970f7f3b2cc2ac25e' 'security.course_description_capacity_v1() 3ccb9929e42f7360056d7438570da110' 'security.course_description_sample_report_v1() 55b26a23b44a8ce8c5db8502ceabeb62' 'security.layer4_pace_v1() 5a90aa3d1d421902ebe48692bba2322c' | sort)
[ "$(comm -23 "$W/0.fn" "$W/1.fn")" = "$EXPECT_OLD" ] || { echo "the changed functions are not exactly the five edited ones (old bodies):"; comm -23 "$W/0.fn" "$W/1.fn"; exit 1; }
[ "$(comm -13 "$W/0.fn" "$W/1.fn" | grep -Fxf <(echo "$EXPECT_NEW") | sort)" = "$EXPECT_NEW" ] || { echo "an edited function does not have the md5 the migration states"; comm -13 "$W/0.fn" "$W/1.fn" | grep -F -e trusted_v1 -e summary_v1 -e capacity_v1 -e sample_report_v1 -e pace_v1; exit 1; }
[ -z "$(comm -23 "$W/0.set" "$W/1.set")" ] || { echo "a setting value changed:"; comm -23 "$W/0.set" "$W/1.set"; exit 1; }
[ "$(comm -13 "$W/0.set" "$W/1.set")" = 'enrich.course_description_machine_on=0' ] || { echo "the new settings are not exactly the switch at 0:"; comm -13 "$W/0.set" "$W/1.set"; exit 1; }
for f in l4 rd desc l4rows; do cmp -s "$W/0.$f" "$W/1.$f" || { echo "the migrations changed $f"; exit 1; }; done
echo "applied: no existing function ($(wc -l < "$W/0.fn")) changed except the five governed edits, no setting value, Layer 4 item, reading or description changed; one new setting (the switch, 0); $(comm -13 "$W/0.fn" "$W/1.fn" | wc -l) function bodies new or edited"
OUT=$($P -f $F/measures_after.sql 2>&1) || { echo "$OUT" | tail -8; exit 1; }
echo "$OUT" | sed -n 's/^.*NOTICE:  //p'
$P -1 -At -f $M1 >/dev/null; $P -1 -At -f $M2 >/dev/null
snap "$W/2"; for f in fn set l4 rd desc l4rows; do cmp -s "$W/1.$f" "$W/2.$f" || { echo "the second run changed $f"; exit 1; }; done
[ "$(q "select count(*) from cron.job where jobname = 'course-description-machine'")" = 1 ] || { echo "the job is not scheduled exactly once"; exit 1; }
[ "$(q "select count(*) from pipeline.component_register where introduced_in in ('20261110060000','20261110060100')")" = 10 ] || { echo "register rows were added twice or are missing"; exit 1; }
echo "applied again: no change (functions, settings, items, readings, descriptions, one job, register rows once)"
# forward recovery of the five edited functions: the held paste files restore each original body byte for byte; applying the migration again brings the edits back
createdb -T $DB $RF
psql -X -d $RF -q -v ON_ERROR_STOP=1 -f supabase/held/cdesc_trusted_machine_forward_recovery.sql >/dev/null || { echo "the forward recovery of trusted_v1 failed"; exit 1; }
psql -X -d $RF -q -v ON_ERROR_STOP=1 -f supabase/held/cdesc_measures_machine_forward_recovery.sql >/dev/null || { echo "the forward recovery of the measures failed"; exit 1; }
psql -X -d $RF -Atc "select p.oid::regprocedure::text || ' ' || md5(p.prosrc) from pg_proc p where p.oid in ('security.course_description_trusted_v1(uuid)'::regprocedure, 'security.course_description_summary_v1(uuid,boolean)'::regprocedure, 'security.course_description_capacity_v1()'::regprocedure, 'security.course_description_sample_report_v1()'::regprocedure, 'security.layer4_pace_v1()'::regprocedure) order by 1" | sort > "$W/rf.fn"
[ "$(cat "$W/rf.fn")" = "$EXPECT_OLD" ] || { echo "the forward recovery did not restore the live bodies:"; cat "$W/rf.fn"; exit 1; }
psql -X -d $RF -q -v ON_ERROR_STOP=1 -f supabase/held/cdesc_measures_machine_forward_recovery.sql >/dev/null || { echo "the forward recovery of the measures does not run twice"; exit 1; }
psql -X -d $RF -q -v ON_ERROR_STOP=1 -1 -f $M2 >/dev/null 2>&1 || { echo "the migration failed after the forward recovery"; exit 1; }
psql -X -d $RF -Atc "select p.oid::regprocedure::text || ' ' || md5(p.prosrc) from pg_proc p where p.oid in ('security.course_description_trusted_v1(uuid)'::regprocedure, 'security.course_description_summary_v1(uuid,boolean)'::regprocedure, 'security.course_description_capacity_v1()'::regprocedure, 'security.course_description_sample_report_v1()'::regprocedure, 'security.layer4_pace_v1()'::regprocedure) order by 1" | sort > "$W/rf.fn"
[ "$(cat "$W/rf.fn")" = "$EXPECT_NEW" ] || { echo "the migration did not bring the edits back:"; cat "$W/rf.fn"; exit 1; }
dropdb --if-exists $RF >/dev/null 2>&1
echo "forward recovery: the two held files restore the five edited functions byte for byte (live md5s); applying 20261110060100 again brings the edits back"
# applying again with the switch ON (a forward-recovery path after a go-live): neither post-check may refuse, and the switch stays on
createdb -T $DB $RF
psql -X -d $RF -q -c "update pipeline.platform_toolset_settings set value = '1'::jsonb where key = 'enrich.course_description_machine_on'" >/dev/null
psql -X -d $RF -q -v ON_ERROR_STOP=1 -1 -f $M1 >/dev/null 2>&1 || { echo "20261110060000 refused to apply again while the switch is 1"; exit 1; }
psql -X -d $RF -q -v ON_ERROR_STOP=1 -1 -f $M2 >/dev/null 2>&1 || { echo "20261110060100 refused to apply again while the switch is 1"; exit 1; }
[ "$(psql -X -d $RF -Atc "select value::text from pipeline.platform_toolset_settings where key = 'enrich.course_description_machine_on'")" = 1 ] || { echo "applying again changed the switch"; exit 1; }
dropdb --if-exists $RF >/dev/null 2>&1
echo "applied again with the switch at 1: both post-checks pass and the switch stays at 1"

# 20261110100000 (Data Delivery stage counts), 20261110100100 (the wrong_page_kind decline) and 20261110130000 (the stage counts read what the Website serves): applied here, before the scenarios, so every earlier scenario also runs with them in place.
# A copy from before them is kept to prove the new regression fails on the old evaluator body.
M3A=supabase/migrations/20261110100000_cf247_cdesc_visible_results.sql
M3B=supabase/migrations/20261110100100_cf247_cdesc_wrong_page_kind.sql
M3C=supabase/migrations/20261110130000_cf247_dd_served_to_website.sql
dropdb --if-exists "${DB}_oldchk" >/dev/null 2>&1; createdb -T "$DB" "${DB}_oldchk"
fnmd5() { psql -X -d "$1" -Atc "select p.oid::regprocedure::text || ' ' || md5(p.prosrc) from pg_proc p where p.oid = '$2'::regprocedure"; }
# (file, held recovery file, function, live md5, edited md5)
for row in "$M3A|supabase/held/cdesc_visible_results_forward_recovery.sql|security.data_delivery_v1()|916e015e0cce905c97e17786b4c2ada1|b67bd181c58546076da48e7b5f00a2a4" \
           "$M3B|supabase/held/cdesc_wrong_page_kind_forward_recovery.sql|security.course_description_machine_check_v1(uuid)|fca43249b1846aae9eae0df7fc83ecb4|3e0fe24d762e7fc4348865ea09499690" \
           "$M3C|supabase/held/dd_served_to_website_forward_recovery.sql|security.data_delivery_cdesc_stages_v1()|eeb3d57c652c66d3f11f38c4de44068b|d2a913a4d294f71fadf949bff6786f94"; do
  IFS='|' read -r MIG HELD FN OLDMD NEWMD <<<"$row"
  snap "$W/p"
  OUT=$($P -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -8; exit 1; }
  snap "$W/q"
  [ "$(comm -23 "$W/p.fn" "$W/q.fn")" = "$FN $OLDMD" ] || { echo "$MIG changed other functions than $FN:"; comm -23 "$W/p.fn" "$W/q.fn"; exit 1; }
  [ "$(comm -13 "$W/p.fn" "$W/q.fn" | grep -Fx "$FN $NEWMD")" = "$FN $NEWMD" ] || { echo "$MIG: $FN does not have the md5 the migration states"; comm -13 "$W/p.fn" "$W/q.fn" | grep -F "$FN"; exit 1; }
  for f in set l4 rd desc l4rows; do cmp -s "$W/p.$f" "$W/q.$f" || { echo "$MIG changed $f"; exit 1; }; done
  $P -1 -At -f $MIG >/dev/null
  snap "$W/r"; for f in fn set l4 rd desc l4rows; do cmp -s "$W/q.$f" "$W/r.$f" || { echo "$MIG applied again changed $f"; exit 1; }; done
  createdb -T "$DB" "$RF"
  psql -X -d "$RF" -q -v ON_ERROR_STOP=1 -f $HELD >/dev/null || { echo "the forward recovery $HELD failed"; exit 1; }
  [ "$(fnmd5 "$RF" "$FN")" = "$FN $OLDMD" ] || { echo "$HELD did not restore the live body of $FN"; exit 1; }
  psql -X -d "$RF" -q -v ON_ERROR_STOP=1 -1 -f $MIG >/dev/null 2>&1 || { echo "$MIG failed after its forward recovery"; exit 1; }
  [ "$(fnmd5 "$RF" "$FN")" = "$FN $NEWMD" ] || { echo "$MIG did not bring its edit back after the forward recovery"; exit 1; }
  dropdb --if-exists "$RF" >/dev/null 2>&1
  echo "$(basename $MIG): only $FN changed ($OLDMD -> $NEWMD); applied again with no change; the held recovery file restores the live body byte for byte and the migration brings the edit back"
done
[ "$(psql -X -d "$DB" -Atc "select count(*) from pg_proc where proname = 'data_delivery_cdesc_stages_v1'")" = 1 ] || { echo "the stage counts function is not there exactly once"; exit 1; }

if [ -n "${CDM_KEEP:-}" ]; then dropdb --if-exists "${DB}_pre" >/dev/null 2>&1; createdb -T "$DB" "${DB}_pre"; fi # a copy from before the scenarios, so they can be run again by hand
OUT=$(psql -X -d "$DB" -v ON_ERROR_STOP=1 -f $F/scenarios.sql 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\|WARNING\):  /\1 /p') || true
if echo "$OUT" | grep -E 'FAIL|ERROR'; then echo "cdesc machine scenarios FAILED"; exit 1; fi
echo "$OUT" | grep -q 'cdm: all' || { echo "the scenarios did not finish"; echo "$OUT" | tail -5; exit 1; }
echo "$OUT" | sed 's/^NOTICE //'
# visible results: the page kind decline and the stage counts, on the migrated database; the same checks on the database from before 20261110100000 and 20261110100100 must FAIL the page kind and stage checks (a regression that fails on the old body)
{ sed -n '5,88p' $F/scenarios.sql; cat $F/scenarios_visible.sql; } > "$W/visible.sql"
OUT=$(psql -X -d "$DB" -v ON_ERROR_STOP=1 -f "$W/visible.sql" 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\|WARNING\):  /\1 /p') || true
if echo "$OUT" | grep -E 'FAIL|ERROR'; then echo "cdesc visible results scenarios FAILED"; exit 1; fi
echo "$OUT" | grep -q 'cdv: all' || { echo "the visible results scenarios did not finish"; echo "$OUT" | tail -5; exit 1; }
echo "$OUT" | grep -E '^NOTICE .*\[pass\]' | sed 's/^NOTICE //'
OLD=$(psql -X -d "${DB}_oldchk" -f "$W/visible.sql" 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\|WARNING\):  /\1 /p') || true
echo "$OLD" | grep -q 'page kind' && echo "$OLD" | grep -E '\[FAIL\]' | grep -q 'page kind' || { echo "the page kind regression did not fail on the old evaluator body"; echo "$OLD" | tail -8; exit 1; }
echo "regression: on the evaluator from before 20261110100100 the page kind checks FAIL ($(echo "$OLD" | grep -c '\[FAIL\]') checks), on the edited body they pass"
dropdb --if-exists "${DB}_oldchk" >/dev/null 2>&1
echo "cdesc-machine: done"
