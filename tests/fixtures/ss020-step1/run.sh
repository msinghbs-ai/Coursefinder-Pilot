#!/usr/bin/env bash
# SS-020 step 1 migration on a throwaway local database (never a Supabase project): stubs (live shapes), the migration twice, then checks.
set -euo pipefail
cd "$(dirname "$0")"
DB=${SS020_DB:-ss020_step1_fixtures}
MIG=../../../supabase/migrations/20261104182000_cf247_ss020_step1_retire_dead_sections.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
trap '$P -d postgres -c "drop database if exists $DB" >/dev/null' EXIT
$P -d $DB -f stubs.sql
$P -d $DB -1 -f $MIG
snap() { $P -d $DB -Atc "select md5(string_agg(jobname||area, ',' order by jobname)) from pipeline.automation_catalogue" ; $P -d $DB -Atc "select md5(string_agg(kind||name||status||coalesce(note,'')||coalesce(retire_after::text,''), ',' order by kind, name)) from pipeline.component_register"; }
A=$(snap)
$P -d $DB -1 -f $MIG
[ "$A" = "$(snap)" ] || { echo "a second run changed something"; exit 1; }
chk() { [ "$($P -d $DB -Atc "$1")" = "$2" ] || { echo "FAIL: $1 (expected $2, got $($P -d $DB -Atc "$1"))"; exit 1; }; echo "ok $3"; }
chk "select string_agg(jobname||'='||area, ',' order by jobname) from pipeline.automation_catalogue" "course-page-read=Course pages,coverage-ai-match=Course pages,coverage-ai-match-prepare=Course pages,fee-period-settle=Admission" "Layer 3 AI area re-areaed, other rows untouched"
chk "select count(*) from pipeline.component_register where status='retiring'" "20" "20 retiring rows"
chk "select status from pipeline.component_register where name='pipeline.search_pass_links'" "active" "search_pass_links stays active (Firecrawl writes it)"
chk "select count(*) from pipeline.component_register where status='retiring' and (replaced_by is null or retire_after is null)" "0" "every retiring row has replaced_by and retire_after"
chk "select retire_after - current_date from pipeline.component_register where name='toolset-runner'" "14" "retire after hygiene.retire_after_days"
echo "second run: unchanged"
