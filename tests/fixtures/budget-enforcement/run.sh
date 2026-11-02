#!/usr/bin/env bash
# Decision 5 E-7/E-8/E-9 budget enforcement and watchdog on isolated fixtures (Platform Admin 2 Nov 2026 10:56). Needs a scratch PostgreSQL
# (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database; loads the seven functions the migration edits or
# relies on from their live text (live-defs.json) and checks each md5 against the live md5 read on 2 Nov 2026; loads the admin_adapter_builder
# skeleton (builder-skeleton.sql, see builder-edit.mjs); reproduces each defect on the live definitions (fixtures-before.sql); applies the
# 20261102070000 migration (its own md5 guards and after-md5 checks run; admin_adapter_builder's md5s are the skeleton's, and its applied md5
# must equal the md5 the check query predicts), applies it again (no change), then runs fixtures.sql. Drops the throwaway database at the end.
set -euo pipefail
cd "$(dirname "$0")"
DB=${BUDGET_DB:-budget_enforcement_fixtures}
P="psql -v ON_ERROR_STOP=1 -q -X"
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
trap '$P -d postgres -c "drop database if exists $DB" >/dev/null' EXIT
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
$P -d $DB -f stubs.sql
node load-live.mjs | $P -d $DB
$P -d $DB -f builder-skeleton.sql
SIGS="security.ai_use_allowed_v1(text) security.ai_spend_today_v1() public.svc_coverage_ai_match_next(integer) public.svc_coverage_ai_match_record(bigint,text,jsonb,text,numeric,text) security.fc_budget_left_v1(text) security.layer2_provider_budget_status(uuid,numeric) public.svc_fc_spend(numeric,text,uuid,text)"
md5s() { for s in $SIGS; do $P -d $DB -Atc "select md5(pg_get_functiondef('$s'::regprocedure))"; done | paste -sd' '; }
BEFORE=$(md5s)
[ "$BEFORE" = "201f93054b167c78462086372d64c369 f18af72fe3d406341931a5daaa93f987 e40e9847068ccf4b7e6e1244a31c2cee b468dcaaaf6cb9494eb1e5e906464c94 187ad8c1c8b085f61ce3fba7cd0fe247 30267f08ebf396738f2a83d72b853c78 7a9b0cee72676c18c01d4692a8a56939" ] || { echo "loaded definitions differ from live: $BEFORE"; exit 1; }
echo "before (loaded = live): $BEFORE"
$P -d $DB -f fixtures-before.sql 2>&1 | show
# admin_adapter_builder: the edits apply once and twice to the skeleton, as they do to the live text; the applied md5 is the predicted one
read SB T1 T2 SA < <(node builder-edit.mjs check 'public.admin_adapter_builder(text,jsonb)' | $P -d $DB -At -F' ')
[ "$T1 $T2" = "1 2" ] || { echo "admin_adapter_builder edits apply $T1 and $T2 times"; exit 1; }
VARIANT=$(mktemp); node builder-edit.mjs variant "$SB" "$SA" > "$VARIANT"
$P -d $DB -1 -At -f "$VARIANT" | grep -c ': applied' | grep -qx 6 || { echo "the migration did not apply all six edits"; exit 1; }
AFTER=$(md5s); echo "after: $AFTER"
[ "$AFTER" = "07b6387d6a30be8a0f86b90b602b6d08 0b79a7f732669ee4c59a260e26188d5a 5a8176270c18994ef3564a5f59a9ff60 b468dcaaaf6cb9494eb1e5e906464c94 e979d2e3d7319d845a5149e40abe6987 30267f08ebf396738f2a83d72b853c78 d418c451d681ffd95134f5f4dcf7c504" ] || { echo "after md5s differ"; exit 1; }
[ "$($P -d $DB -Atc "select md5(pg_get_functiondef('public.admin_adapter_builder(text,jsonb)'::regprocedure))")" = "$SA" ] || { echo "admin_adapter_builder: applied md5 is not the predicted one"; exit 1; }
echo "admin_adapter_builder skeleton: applied md5 = predicted ($SA)"
$P -d $DB -1 -At -f "$VARIANT" | grep -c 'already applied' | grep -qx 6 || { echo "a second run changed something"; exit 1; }
[ "$(md5s)" = "$AFTER" ] || { echo "a second run changed a definition"; exit 1; }
echo "second run: already applied, unchanged"
rm -f "$VARIANT"
$P -d $DB -c "grant usage on schema fx to supabase_read_only_user"
$P -d $DB -f fixtures.sql 2>&1 | show
