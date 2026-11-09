#!/usr/bin/env bash
# Guards: F-CDESC (Platform Admin decision 10 Nov 2026, course descriptions: narrow source-verified machine admission): migrations 20261110060000 and 20261110060100 add the ledger, the one switch (ships 0), the safe-class
# evaluator, the admission, withdrawal, settlement, the reading hook and the catalogued job; they change no existing function, setting value, Layer 4 item, description or reading; refuse and change nothing when a live function they
# call is missing or applied out of order; apply twice with no change; and behave as scenarios.sql says (wrong page, other course, obsolete page, unsupported claim, retry, rejection memory, lock, empty answer, duplicates, timeout,
# cost cap, consumer lag and mismatch, ambiguous binding, hidden provider, idempotence, withdrawal, forward recovery) against production-shaped constraints and triggers.
# Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds the database with the course-description-backpressure harness (production-parity fixture plus 20261106500000,
# 20261107120000 and 20261108130000), adds the stand-ins in stubs.sql and the live definitions in live/ (each checked against its live body md5, read 10 Nov 2026), then applies the two migrations, each twice.
# Drops the database at the end (CDM_KEEP=1 keeps it).
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
cleanup() { local code=$?; trap - EXIT; rm -rf "$W"; if [ -z "${CDM_KEEP:-}" ]; then dropdb --if-exists "$DB" >/dev/null 2>&1 || true; dropdb --if-exists "${DB}_refuse" >/dev/null 2>&1 || true; fi; exit "$code"; }
trap cleanup EXIT
echo "base: course-description-backpressure harness built the database (production-parity fixture, 20261106500000, 20261107120000, 20261108130000)"
$P -f $F/stubs.sql
$P -f $F/seed.sql
for f in security.pdesc_claim_check_v1 security.pdesc_machine_neutral_supported_v1 security.pdesc_machine_text_check_ctx_v1 security.pdesc_machine_text_check_v1 security.enrich_item_held_v1; do $P -c "set check_function_bodies = off" -f $F/live/$f.sql; done
declare -A LIVE=( ['security.pdesc_claim_check_v1(text,text,text)']=5e256534e43073bc32f842bee2e50c98 ['security.pdesc_machine_neutral_supported_v1(text,jsonb)']=8601c0066d7bde714fc753e5ae0ba0db
                  ['security.pdesc_machine_text_check_ctx_v1(uuid,text,text[],jsonb)']=e9a12bc0383e321345fc015f89768042 ['security.pdesc_machine_text_check_v1(uuid,text,text[])']=bafcb58c2ac586829ce4f1b1d2780a44
                  ['security.course_description_check_v1(uuid,jsonb)']=0d3a4cc7811eddaf6bb94307b542cc60 ['security.course_description_check_with_v1(uuid,jsonb,jsonb,jsonb)']=3bb5d62b5e86cd7c76707171e02a3ae5
                  ['security.course_description_trusted_v1(uuid)']=ae8b327f85f0262b3d0b878010a4af3c ['security.coverage_identity_allowed(uuid,text,text)']=dc66799e79f91620169fc2c17d621349
                  ['security.layer4_course_description_apply_v1(uuid,uuid,jsonb,text)']=04059b123d1afb184adfb8ca9d7af906 ['security.enrich_course_text_record_v1(bigint,jsonb)']=c52c1969a80f2d3db1d81a4e46a49cd9
                  ['security.pdesc_has_term_v1(text,text)']=2900b13238674e92caa77f8339f81698 ['security.pdesc_support_v1(text,text)']=2065dfd6987b47852d267f5d33dd9056
                  ['security.pdesc_words_v1(text)']=0ca18e0d985cf01902977d992e364815 ['security.pipeline_num_v1(text,numeric)']=cbde6549dbdab8cad5ad961e8278e86c
                  ['security.enrich_course_text_gaps_v1(text[])']=5352bc7ea7bbf3ef00bd616f2897f2f4 ['security.enrich_item_held_v1(uuid,text)']=78c7102adf2804fb536eb2e263264edc
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

snap "$W/0"
OUT=$($P -1 -At -f $M1 2>&1) || { echo "$OUT" | tail -8; exit 1; }
OUT=$($P -1 -At -f $M2 2>&1) || { echo "$OUT" | tail -8; exit 1; }
snap "$W/1"
# nothing existing changed: every function that was there has the same body; the only new setting is the switch at 0; no Layer 4 item, reading or description changed
# the one governed in-place edit: security.course_description_trusted_v1 (a machine decision is not person-trust), from its live md5 to the md5 the migration states
[ "$(comm -23 "$W/0.fn" "$W/1.fn")" = 'security.course_description_trusted_v1(uuid) ae8b327f85f0262b3d0b878010a4af3c' ] || { echo "the changed functions are not exactly security.course_description_trusted_v1:"; comm -23 "$W/0.fn" "$W/1.fn"; exit 1; }
[ "$(comm -13 "$W/0.fn" "$W/1.fn" | grep -c '^security.course_description_trusted_v1(uuid) 16568089f58b528b9a6647e78eca3ed5$')" = 1 ] || { echo "trusted_v1 does not have the md5 the migration states"; exit 1; }
[ -z "$(comm -23 "$W/0.set" "$W/1.set")" ] || { echo "a setting value changed:"; comm -23 "$W/0.set" "$W/1.set"; exit 1; }
[ "$(comm -13 "$W/0.set" "$W/1.set")" = 'enrich.course_description_machine_on=0' ] || { echo "the new settings are not exactly the switch at 0:"; comm -13 "$W/0.set" "$W/1.set"; exit 1; }
for f in l4 rd desc l4rows; do cmp -s "$W/0.$f" "$W/1.$f" || { echo "the migrations changed $f"; exit 1; }; done
echo "applied: no existing function ($(wc -l < "$W/0.fn")), setting value, Layer 4 item, reading or description changed; one new setting (the switch, 0); $(comm -13 "$W/0.fn" "$W/1.fn" | wc -l) functions added"
$P -1 -At -f $M1 >/dev/null; $P -1 -At -f $M2 >/dev/null
snap "$W/2"; for f in fn set l4 rd desc l4rows; do cmp -s "$W/1.$f" "$W/2.$f" || { echo "the second run changed $f"; exit 1; }; done
[ "$(q "select count(*) from cron.job where jobname = 'course-description-machine'")" = 1 ] || { echo "the job is not scheduled exactly once"; exit 1; }
[ "$(q "select count(*) from pipeline.component_register where introduced_in in ('20261110060000','20261110060100')")" = 10 ] || { echo "register rows were added twice or are missing"; exit 1; }
echo "applied again: no change (functions, settings, items, readings, descriptions, one job, register rows once)"
# forward recovery of the one edited function: the held paste file restores the original body byte for byte; applying the migration again brings the edit back
createdb -T $DB $RF
psql -X -d $RF -q -v ON_ERROR_STOP=1 -f supabase/held/cdesc_trusted_machine_forward_recovery.sql >/dev/null || { echo "the forward recovery failed"; exit 1; }
[ "$(psql -X -d $RF -Atc "select md5(prosrc) from pg_proc where oid = 'security.course_description_trusted_v1(uuid)'::regprocedure")" = ae8b327f85f0262b3d0b878010a4af3c ] || { echo "the forward recovery did not restore the live body"; exit 1; }
psql -X -d $RF -q -v ON_ERROR_STOP=1 -1 -f $M2 >/dev/null 2>&1 || { echo "the migration failed after the forward recovery"; exit 1; }
[ "$(psql -X -d $RF -Atc "select md5(prosrc) from pg_proc where oid = 'security.course_description_trusted_v1(uuid)'::regprocedure")" = 16568089f58b528b9a6647e78eca3ed5 ] || { echo "the migration did not bring the edit back"; exit 1; }
dropdb --if-exists $RF >/dev/null 2>&1
echo "forward recovery: the held file restores security.course_description_trusted_v1 byte for byte (live md5); applying 20261110060100 again brings the edit back"

if [ -n "${CDM_KEEP:-}" ]; then dropdb --if-exists "${DB}_pre" >/dev/null 2>&1; createdb -T "$DB" "${DB}_pre"; fi # a copy from before the scenarios, so they can be run again by hand
OUT=$(psql -X -d "$DB" -v ON_ERROR_STOP=1 -f $F/scenarios.sql 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\|WARNING\):  /\1 /p') || true
if echo "$OUT" | grep -E 'FAIL|ERROR'; then echo "cdesc machine scenarios FAILED"; exit 1; fi
echo "$OUT" | grep -q 'cdm: all' || { echo "the scenarios did not finish"; echo "$OUT" | tail -5; exit 1; }
echo "$OUT" | sed 's/^NOTICE //'
echo "cdesc-machine: done"
