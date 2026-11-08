#!/usr/bin/env bash
# CF-247 OPS/UI lane funnels (migration 20261108170000) on isolated fixtures. Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it.
# Builds a throwaway database: schema.sql (the live columns the change reads, stubs marked), the migration, again (idempotent: same rows), fixtures.sql (behaviour). Drops it at the end (LF_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${LF_DB:-g_ops_ui_lane_funnels}
P="psql -v ON_ERROR_STOP=1 -q -X"
MIG=supabase/migrations/20261108170000_cf247_lane_funnels.sql
[ -n "${LF_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists '$DB'" >/dev/null 2>&1' EXIT
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
$P -d $DB -f tests/fixtures/lane-funnels/schema.sql >/dev/null
$P -d $DB -f $MIG >/dev/null
before=$($P -d $DB -Atc "select (select count(*) from pipeline.lane_funnel_lanes) || '/' || (select count(*) from pipeline.lane_funnel_stages) || '/' || (select count(*) from pipeline.platform_toolset_settings) || '/' || (select count(*) from cron.job) || '/' || (select count(*) from pipeline.component_register)")
$P -d $DB -f $MIG >/dev/null
after=$($P -d $DB -Atc "select (select count(*) from pipeline.lane_funnel_lanes) || '/' || (select count(*) from pipeline.lane_funnel_stages) || '/' || (select count(*) from pipeline.platform_toolset_settings) || '/' || (select count(*) from cron.job) || '/' || (select count(*) from pipeline.component_register)")
[ "$before" = "$after" ] || { echo "re-run changed rows: $before -> $after"; exit 1; }
echo "migration applied twice: lanes/stages/settings/jobs/register $after (unchanged on re-run)"
out=$($P -d $DB -f tests/fixtures/lane-funnels/fixtures.sql 2>&1) || { echo "$out" | grep -E 'FAILED|ERROR'; exit 1; }
echo "$out" | grep 'NOTICE:  ok:' | sed 's/^[^N]*NOTICE:  //'
echo "assertions passed: $(echo "$out" | grep -c 'NOTICE:  ok:')"
