#!/usr/bin/env bash
# P1 provider descriptions on isolated fixtures (CF-247 missing-field enrichment, Platform Admin 2 Nov 2026 10:28). Needs a scratch
# PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database (createdb), loads the seven live
# definitions the migration edits (live-before/, read from the live project on 2 Nov 2026 10:45-10:57 and 14:56-14:57 AEDT) and checks their md5s against
# the live ones, applies the migration unchanged (its own md5 guards and after-md5 checks run), applies it again (no change), then runs
# fixtures.sql. Drops the throwaway database at the end.
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${P1DESC_DB:-p1desc_fixtures}
FX=tests/fixtures/p1-provider-descriptions
P="psql -v ON_ERROR_STOP=1 -q -X"
MIG=supabase/migrations/20261102090000_cf247_p1_provider_descriptions.sql
SIGS="array['security.layer4_review_decide_impl(uuid,text,text,jsonb)', 'security.ai_spend_today_v1()', 'security.layer4_inbox_kinds_v1()', 'security.layer4_inbox_items_v1()', 'public.admin_layer4_inbox(text,jsonb)', 'l4_api.layer4_review_bulk_decide(text,text,text,text,text,text,integer)', 'security.layer4_batch_decide_v1_impl(uuid[],text,text,text,text)']"
dropdb --if-exists "$DB" >/dev/null 2>&1 || true
createdb "$DB"
[ -n "${P1DESC_KEEP:-}" ] || trap 'dropdb --if-exists "$DB" >/dev/null 2>&1 || true' EXIT
PGOPTIONS='-c check_function_bodies=off' $P -d "$DB" -f $FX/stubs.sql
for f in $FX/live-before/*.sql; do PGOPTIONS='-c check_function_bodies=off' $P -d "$DB" -f "$f"; done
md5s() { $P -d "$DB" -Atc "select string_agg(md5(pg_get_functiondef(f::regprocedure)), ' ' order by o) from unnest($SIGS) with ordinality t(f, o)"; }
BEFORE=$(md5s); [ "$BEFORE" = "67966cebe3184b9acad1a3451fd0021b 0b79a7f732669ee4c59a260e26188d5a 629fcbda204cd79fdba97a096a6dc26b c1a133c3260c3c160397151bd0664957 417f181d12155f79f68c1e70c27a1892 512226a0d25891c137195bde221d40b4 d3135163affa549deca5d2454133b188" ] || { echo "loaded definitions differ from live: $BEFORE"; exit 1; }
# the shared AI rule this reader goes through, as live since v2.15.404 (not edited here)
[ "$($P -d "$DB" -Atc "select string_agg(md5(pg_get_functiondef(f::regprocedure)), ' ' order by f) from unnest(array['security.ai_use_allowed_v1(text)', 'security.ai_use_refusal_v1(text)', 'security.ai_spend_capture_v1()']) f")" = "5b78fa074a9480d4f127ecc4fe93dcf3 07b6387d6a30be8a0f86b90b602b6d08 60c782e5aec7eb218c1149a3ad85dde2" ] || { echo "the shared AI rule differs from live"; exit 1; }
echo "before (loaded = live): $BEFORE"
PGOPTIONS='-c check_function_bodies=off' $P -d "$DB" -1 -o /dev/null -f $MIG
AFTER=$(md5s); echo "after: $AFTER"
PGOPTIONS='-c check_function_bodies=off' $P -d "$DB" -1 -At -f $MIG | grep -c 'already applied' | grep -qx 7 || { echo "a second run changed something"; exit 1; }
[ "$(md5s)" = "$AFTER" ] || { echo "a second run changed a definition"; exit 1; }
echo "second run: already applied, unchanged"
$P -d "$DB" -f $FX/fixtures.sql 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'
