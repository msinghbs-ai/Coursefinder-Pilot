#!/usr/bin/env bash
# CF-247 F-OPS.03A Data Delivery (migration 20261110000100) on isolated fixtures. Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it.
# Builds a throwaway database: the lane funnel schema and migration it reuses, schema.sql (the live columns this change reads, stubs marked), the migration, again
# (idempotent: same rows), fixtures.sql (behaviour). The md5 guard of the admin_layer23 edit is re-pointed at the fixture stub's body; the live md5 was read from the project.
# Drops the database at the end (DD_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${DD_DB:-g_fops03a_data_delivery}
P="psql -v ON_ERROR_STOP=1 -q -X"
MIG=supabase/migrations/20261110000100_cf247_fops03a_data_delivery.sql
TMP=$(mktemp -d); trap 'rm -rf "$TMP"; [ -n "${DD_KEEP:-}" ] || $P -d postgres -c "drop database if exists '$DB'" >/dev/null 2>&1' EXIT
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
$P -d $DB -f tests/fixtures/lane-funnels/schema.sql >/dev/null
$P -d $DB -f supabase/migrations/20261108170000_cf247_lane_funnels.sql >/dev/null
$P -d $DB -f tests/fixtures/fops03a-data-delivery/schema.sql >/dev/null
live_before=$(grep -o "body b1d08c144078fce71ba2cd3762a00b0f" $MIG | head -1 | awk '{print $2}')
live_after=$(grep -o "pg_temp.edit_one('public.admin_layer23(text,jsonb)', '[0-9a-f]*', '[0-9a-f]*'" $MIG | sed "s/.*', '\([0-9a-f]*\)', '\([0-9a-f]*\)'/\2/")
stub_before=$($P -d $DB -Atc "select md5(prosrc) from pg_proc where oid = 'public.admin_layer23(text,jsonb)'::regprocedure")
stub_after=$($P -d $DB -Atc "select md5(replace(prosrc, \$o\$  if p_action = 'universities_page' then\$o\$, \$n\$  if p_action = 'data_delivery' then
    -- CF-247 F-OPS.03A (Platform Admin 9 Nov 2026): the Data Delivery summary at the top of Layer 2/3 > Operations. One read, same rank as the screen (3 and above, checked above).
    return security.data_delivery_v1();
  end if;
  if p_action = 'universities_page' then\$n\$)) from pg_proc where oid = 'public.admin_layer23(text,jsonb)'::regprocedure")
[ -n "$live_before" ] && [ -n "$live_after" ] || { echo "could not read the live md5 guards from the migration"; exit 1; }
sed -e "s/$live_before/$stub_before/g" -e "s/$live_after/$stub_after/g" $MIG > $TMP/mig.sql
grep -q "$stub_before" $TMP/mig.sql && grep -q "$stub_after" $TMP/mig.sql || { echo "md5 guards not re-pointed"; exit 1; }
$P -d $DB -f $TMP/mig.sql >/dev/null
snap="select (select count(*) from pipeline.data_delivery_streams) || '/' || (select count(*) from pipeline.lane_funnel_stages) || '/' || (select count(*) from pipeline.platform_toolset_settings) || '/' || (select count(*) from cron.job) || '/' || (select count(*) from pipeline.component_register) || '/' || (select md5(prosrc) from pg_proc where oid = 'public.admin_layer23(text,jsonb)'::regprocedure)"
before=$($P -d $DB -Atc "$snap")
$P -d $DB -f $TMP/mig.sql >/dev/null
after=$($P -d $DB -Atc "$snap")
[ "$before" = "$after" ] || { echo "re-run changed rows: $before -> $after"; exit 1; }
echo "migration applied twice: streams/stages/settings/jobs/register/admin_layer23 $after (unchanged on re-run)"
out=$($P -d $DB -f tests/fixtures/fops03a-data-delivery/fixtures.sql 2>&1) || { echo "$out" | grep -E 'FAILED|ERROR'; exit 1; }
echo "$out" | grep 'NOTICE:  ok:' | sed 's/^[^N]*NOTICE:  //'
echo "assertions passed: $(echo "$out" | grep -c 'NOTICE:  ok:')"
# 20261110100000 (course description stages in Data Delivery): applied twice; this database holds no course description ledger, so the count cannot be made and the stream shows it as such (known false with the error)
# while every other stream, and the read itself, are unchanged. The counts themselves are proved on the course description fixture (tests/fixtures/cdesc-machine).
CDV=supabase/migrations/20261110100000_cf247_cdesc_visible_results.sql
$P -d $DB -f $CDV >/dev/null; $P -d $DB -f $CDV >/dev/null
res=$($P -d $DB -Atc "select (select count(*) from jsonb_array_elements(j->'streams')) || '|' || (select count(*) from jsonb_array_elements(j->'streams') s where s->>'stream' <> 'cdesc' and jsonb_typeof(s->'stages') <> 'null')
  || '|' || (select s->'stages'->>'known' || '/' || left(s->'stages'->>'reason', 34) from jsonb_array_elements(j->'streams') s where s->>'stream' = 'cdesc') from (select security.data_delivery_v1() j) z")
[ "$res" = "8|0|false/The stage counts could not be read" ] || { echo "Data Delivery with the stage counts: unexpected result $res"; exit 1; }
echo "stages: Data Delivery still returns its 8 streams; only the course description stream carries stages, and a count that cannot be made shows known false with the error"
# Guards: F-OPS.03A (Platform Admin 9 Nov 2026 21:28) and G4 database-backed tests: the Data Delivery read and its refresh run against the migration on an isolated PostgreSQL (fixtures only, never a Supabase project).
