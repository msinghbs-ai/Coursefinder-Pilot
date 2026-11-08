#!/usr/bin/env bash
# Builds the AER technical-holds fixture database (the E13 / D-R2 / D-R3 chain rebuilt from this repository, the old reader seeded with production shapes,
# the stored-read recovery and the replay actor fix applied, fixtures of that suite run) into the database named by $1. Shared by the lane aer2 fixtures.
set -euo pipefail
cd "$(dirname "$0")/../../.."
P="psql -v ON_ERROR_STOP=1 -q -X"
DB=$1
FX=tests/fixtures/aer-technical-holds
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null 2>&1
$P -d $DB -f tests/fixtures/e13-completeness-gate/stubs.sql >/dev/null
$P -d $DB -f tests/fixtures/aer-dr2-dr3/stubs.sql >/dev/null
node tests/fixtures/e13-completeness-gate/before.mjs | $P -d $DB -o /dev/null
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261102010000_cf247_e13_entry_completeness_gate.sql
node tests/fixtures/aer-dr2-dr3/before.mjs | $P -d $DB -o /dev/null
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261103070000_cf247_aer_dr2_dr3_supersede_and_matrix_gate.sql
$P -d $DB -f $FX/stubs-extra.sql >/dev/null
$P -d $DB -f $FX/seed.sql >/dev/null
$P -d $DB -o /dev/null -f $FX/fixtures.sql 2>&1 | grep -E "ERROR|FAIL" && exit 1 || true
$P -d $DB -At -f supabase/migrations/20261107130000_cf247_aer_stored_read_recovery.sql >/dev/null
$P -d $DB -At -f supabase/migrations/20261107170000_cf247_aer_replay_job_actor.sql >/dev/null
