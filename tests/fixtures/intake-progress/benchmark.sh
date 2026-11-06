#!/usr/bin/env bash
# Guards: Platform Admin decision 5 Nov 2026 19:14 §8 (bounded performance) for the Automation Progress reads, on a copy of the fixture database.
set -euo pipefail
cd "$(dirname "$0")/../../.."
case "${PGHOST:-127.0.0.1}" in 127.0.0.1|localhost|/tmp|/var/run/postgresql) ;; *) echo 'Refusing a remote database: use isolated local PostgreSQL' >&2; exit 1;; esac
DB=${INTAKE_PROGRESS_DB:-d_intake_progress}; BENCH=${DB}_bench
psql -X -q -d postgres -c "drop database if exists $BENCH" -c "create database $BENCH template $DB" > /dev/null
trap 'psql -X -q -d postgres -c "drop database if exists $BENCH" > /dev/null' EXIT
OUT=$(psql -X -q -At -v ON_ERROR_STOP=1 -d "$BENCH" -f tests/fixtures/intake-progress/benchmark.sql)
echo "$OUT" | tee "${UAT_ARTIFACTS:-/tmp}/intake-progress-benchmark.txt"
echo "$OUT" | grep -q '^PASS benchmark' || exit 1
