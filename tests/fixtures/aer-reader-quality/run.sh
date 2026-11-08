#!/usr/bin/env bash
# CF-247 AER reader quality (migration 20261108020000): settings only. Needs a scratch PostgreSQL (never a Supabase project): PGHOST/PGPORT/PGUSER point at it.
# The schema is the live shape (columns, defaults, NOT NULL, kind check, primary key, the live svc_worker_settings_v1). Applies the migration, checks it,
# applies it a second time (no change), and shows the guards refuse a database where the worker could not read the keys.
set -euo pipefail
cd "$(dirname "$0")/../../.."
P="psql -v ON_ERROR_STOP=1 -q -X"
FX=tests/fixtures/aer-reader-quality
MIG=supabase/migrations/20261108020000_cf247_aer_reader_quality.sql
DB=${AERRQ_DB:-aer_reader_quality}
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null 2>&1
trap '$P -d postgres -c "drop database if exists '$DB'" >/dev/null 2>&1' EXIT
$P -d $DB -f $FX/schema.sql >/dev/null
$P -d $DB -o /dev/null -f $MIG
$P -d $DB -f $FX/checks.sql 2>&1 | sed 's/psql:[^ ]* NOTICE:  //' | grep -E "PASS|FAIL|ERROR"
BEFORE=$($P -d $DB -Atc "select md5(string_agg(t::text, '|' order by key)) from pipeline.platform_toolset_settings t")
$P -d $DB -o /dev/null -f $MIG
AFTER=$($P -d $DB -Atc "select md5(string_agg(t::text, '|' order by key)) from pipeline.platform_toolset_settings t")
[ "$BEFORE" = "$AFTER" ] || { echo "FAIL a second run changed the settings"; exit 1; }
echo "PASS migration applied twice: no change"
# a recorded change survives a re-run (on conflict do nothing)
$P -d $DB -c "update pipeline.platform_toolset_settings set value = '1' where key = 'reading.entry_value_null_on'" >/dev/null
$P -d $DB -o /dev/null -f $MIG
[ "$($P -d $DB -Atc "select value from pipeline.platform_toolset_settings where key = 'reading.entry_value_null_on'")" = "1" ] || { echo "FAIL a re-run reset a recorded setting"; exit 1; }
echo "PASS a re-run does not reset a recorded setting change"
DB2=${DB}_bad
$P -d postgres -c "drop database if exists $DB2" -c "create database $DB2" >/dev/null 2>&1
$P -d $DB2 -f $FX/schema.sql >/dev/null
# the post-check refuses a seeded number outside its range
$P -d $DB2 -c "insert into pipeline.platform_toolset_settings(toolset_key,key,label,kind,value,min_value,max_value,unit,section,used_by) values ('pipeline','reading.entry_value_null_on','x','number','5',0,1,'on/off','Entry requirements','x')" >/dev/null
if $P -d $DB2 -o /dev/null -f $MIG 2>/dev/null; then echo "FAIL post-check accepted a number outside its range"; exit 1; fi
echo "PASS post-check refuses a number outside its range"
# the guard refuses when the worker could not read the keys
$P -d $DB2 -c "delete from pipeline.platform_toolset_settings where key = 'reading.entry_value_null_on'" >/dev/null
$P -d $DB2 -c "create or replace function public.svc_worker_settings_v1() returns jsonb language sql as \$\$ select '{}'::jsonb \$\$" >/dev/null
if $P -d $DB2 -o /dev/null -f $MIG 2>/dev/null; then echo "FAIL guard accepted a worker-settings function without reading.*"; exit 1; fi
echo "PASS guard refuses when svc_worker_settings_v1 would not return the keys"
$P -d postgres -c "drop database if exists $DB2" >/dev/null 2>&1
echo "aer-reader-quality: passed"
