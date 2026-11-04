#!/usr/bin/env bash
# Guards: complete governed scan in small RPCs; no production target.
set -euo pipefail
cd "$(dirname "$0")/../../.."
bash tests/fixtures/intake-preview-timeout/run.sh
psql -X -1 -q -v ON_ERROR_STOP=1 -d intake_ui_fixtures -f supabase/migrations/20261105020000_intake_preview_paging.sql
psql -X -1 -q -v ON_ERROR_STOP=1 -d intake_ui_fixtures -f supabase/migrations/20261105020000_intake_preview_paging.sql
psql -X -q -v ON_ERROR_STOP=1 -d intake_ui_fixtures -f tests/fixtures/intake-complete-scan/check.sql
node tests/fixtures/intake-complete-scan/benchmark.mjs
