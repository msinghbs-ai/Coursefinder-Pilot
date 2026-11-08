#!/usr/bin/env bash
# Guards: P-DESC lane E (8 Nov 2026): held reads are selected again once a different official copy is stored (migration 20261108140000); the whole-catalogue funnel is read only.
# Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds the production-shaped provider-description database from the existing
# fixtures (p1-provider-descriptions, provider-description-autonomy, both read live 3-6 Nov 2026), checks the edited function is the live one (md5 read 8 Nov 2026), runs the
# scenarios before and after the migration, applies the migration twice and runs the funnel assertions. Drops the database at the end (PDRF_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${PDRF_DB:-g_pdesc_retry}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
FX=tests/fixtures/provider-description-autonomy
MIG=supabase/migrations/20261108140000_cf247_pdesc_retry_on_new_evidence_and_funnel.sql
q() { psql -X -d "$DB" -Atc "$1"; }
[ -n "${PDRF_KEEP:-}" ] || trap 'dropdb --if-exists '$DB' >/dev/null 2>&1' EXIT
dropdb --if-exists "$DB"; createdb "$DB"
psql -q -d "$DB" -c "alter database $DB set jit=off; alter database $DB set work_mem='7168kB'; alter database $DB set max_parallel_workers_per_gather=1;"
sql() { { echo 'set check_function_bodies=off;'; cat "$@"; } | $P; }
sql tests/fixtures/p1-provider-descriptions/stubs.sql
for f in tests/fixtures/p1-provider-descriptions/live-before/*.sql; do sql "$f"; done
sql supabase/migrations/20261102090000_cf247_p1_provider_descriptions.sql
node "$FX/parity.mjs" | $P
for f in identity roles role-flags diagnostics; do $P < "$FX/$f.sql"; done
node "$FX/knowledge-parity.mjs" | $P
node "$FX/registration-parity.mjs" | $P
{ echo 'set check_function_bodies=off;'; for f in "$FX"/live/*.sql; do cat "$f"; echo ';'; done; } | $P
for f in helpers website-sync; do $P < "$FX/$f.sql"; done
node "$FX/zoho-parity.mjs" | $P
for f in lineage manual-column-guard triggers indexes knowledge-triggers zoho-triggers zoho-grants; do $P < "$FX/$f.sql"; done
node "$FX/grants.mjs" | $P
HOTFIX=supabase/migrations/20261104640000_cf247_run_now_outcome_code.sql
[ -f "$HOTFIX" ] || { echo 'Current-main outcome-code correction is required; rebase onto main first' >&2; exit 1; }
{ echo 'set check_function_bodies=off;'; cat "$HOTFIX"; } | $P -1
sql supabase/migrations/20261106200000_cf247_provider_description_autonomy.sql
# the edited function is the live one (md5 of pg_get_functiondef read 8 Nov 2026, project fxcwkweaxjtknorudmwp)
[ "$(q "select md5(pg_get_functiondef('security.provider_description_selection_v1(jsonb)'::regprocedure))")" = 6b43ea62758a2c6fac80affba14b12d5 ] || { echo "the loaded selection function differs from live"; exit 1; }
$P < "$FX/seed.sql"
echo "loaded: selection function = live 6b43ea62758a2c6fac80affba14b12d5"

# scenarios before the migration: a held read waits the full recheck time whatever is stored
BEFORE=$($P -At < tests/fixtures/pdesc-retry-funnel/scenarios.sql | grep .)
for w in 'held_new_copy|retry_wait' 'rejected_source_now_refused|retry_wait' 'held_never_fetched|retry_wait' 'held_same_copy|unchanged_unsuitable_evidence' 'held_past_recheck|eligible'; do
  grep -qxF "$w" <<<"$BEFORE" || { echo "before the change: expected $w"; echo "$BEFORE"; exit 1; }; done
echo "before: a held read with a new stored copy waits (retry_wait), as live"

# the function set and the settings before
FNS="select md5(string_agg(p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)), '|' order by p.oid::regprocedure::text)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('security', 'public', 'api') and p.prokind = 'f' and p.proname not in ('provider_description_selection_v1', 'admin_provider_description_funnel_v1')"
F0=$(q "$FNS"); S0=$(q "select md5(string_agg(key || value::text, '|' order by key)) from pipeline.platform_toolset_settings"); L0=$(q "select count(*) from pipeline.layer4_review_items")
OUT=$($P -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
grep -q 'selection_v1(jsonb): applied$' <<<"$OUT" || { echo "the migration did not apply its guarded edit"; echo "$OUT" | tail -5; exit 1; }
AFTER=$(grep -F -- "--   security.provider_description_selection_v1(jsonb) " $MIG | head -1 | sed 's/.*-> *\([0-9a-f]*\).*/\1/')
[ "$(q "select md5(pg_get_functiondef('security.provider_description_selection_v1(jsonb)'::regprocedure))")" = "$AFTER" ] || { echo "selection after: differs from the recorded $AFTER"; exit 1; }
[ "$(q "$FNS")" = "$F0" ] || { echo "the migration changed a function it does not own"; exit 1; }
[ "$(q "select md5(string_agg(key || value::text, '|' order by key)) from pipeline.platform_toolset_settings")" = "$S0" ] || { echo "the migration changed settings"; exit 1; }
[ "$(q "select count(*) from pipeline.layer4_review_items")" = "$L0" ] || { echo "the migration changed Layer 4"; exit 1; }
OUT=$($P -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
grep -q 'selection_v1(jsonb): already applied$' <<<"$OUT" || { echo "the second run was not a no-op"; exit 1; }
echo "migration: one guarded edit to its recorded after md5 ($AFTER); nothing else changed; applied again: no change"

# scenarios after
AFTERS=$($P -At < tests/fixtures/pdesc-retry-funnel/scenarios.sql | grep .)
EXPECT='held_new_copy|eligible
held_same_copy|unchanged_unsuitable_evidence
held_new_copy_just_now|retry_wait
rejected_source_now_refused|eligible
rejected_source_still_valid|retry_wait
held_never_fetched|eligible
held_new_copy_manual_lock|manual_lock
held_past_recheck|eligible
rejected_no_source_recorded|retry_wait
proposed_open|existing_work'
[ "$AFTERS" = "$EXPECT" ] || { echo "after the change the scenarios differ:"; diff <(echo "$EXPECT") <(echo "$AFTERS"); exit 1; }
echo "after: new stored copy -> eligible; same copy, just now, a person's rejection on a valid source, a lock, open work -> unchanged"

$P < tests/fixtures/pdesc-retry-funnel/funnel.sql 2>&1 | sed -n "s/^.*\(NOTICE\|ERROR\):  /\1 /p; s/^\(pdesc-retry-funnel fixtures: passed\)$/\1/p"
echo "pdesc-retry-funnel: done"
