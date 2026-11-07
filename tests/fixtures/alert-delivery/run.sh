#!/usr/bin/env bash
# Genuine PostgreSQL run of the alert delivery lifecycle migration. Isolated only: fixture-only schema, no production access.
set -euo pipefail
cd "$(dirname "$0")/../../.."
psql -v ON_ERROR_STOP=1 -q -f tests/fixtures/alert-delivery/schema.sql
psql -v ON_ERROR_STOP=1 -q -f supabase/migrations/20261107030000_cf247_alert_delivery_lifecycle.sql
if ! psql -v ON_ERROR_STOP=1 -f tests/fixtures/alert-delivery/scenarios.sql > /tmp/ad_scen.log 2>&1; then grep -E "PASS|FAIL|ERROR" /tmp/ad_scen.log; exit 1; fi
grep -E "PASS" /tmp/ad_scen.log
bash tests/fixtures/alert-delivery/concurrent.sh
echo "alert delivery lifecycle: all scenarios passed"
