#!/usr/bin/env bash
# Guards: F-PDESC (Platform Admin data population mandate 9 Nov 2026): a provider whose description is empty is selected again even within pdesc.recheck_days of an admitted read (migration 20261109010000); nothing else in the reader changes.
# Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds the production-shaped provider-description database with the existing pdesc-retry-funnel harness
# (which also applies migration 20261108140000, the live selection function 1fd3fcde...), runs the scenarios before and after this migration, applies it twice and checks nothing else changed.
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${PDSD_DB:-g_pdesc_selfdriving}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
MIG=supabase/migrations/20261109010000_cf247_pdesc_description_lost.sql
q() { psql -X -d "$DB" -Atc "$1"; }
[ -n "${PDSD_KEEP:-}" ] || trap 'dropdb --if-exists '$DB' >/dev/null 2>&1' EXIT
# the base: the retry-funnel harness builds and checks the database as live, applies 20261108140000 and keeps it
BASE=$(PDRF_KEEP=1 PDRF_DB=$DB bash tests/fixtures/pdesc-retry-funnel/run.sh 2>&1) || { echo "$BASE" | tail -15; echo "the base harness failed"; exit 1; }
# the edited function is the live one (md5 of pg_get_functiondef read 8 Nov 2026 ~20:00 UTC, project fxcwkweaxjtknorudmwp)
[ "$(q "select md5(pg_get_functiondef('security.provider_description_selection_v1(jsonb)'::regprocedure))")" = 1fd3fcde2fcafed6fadf4f6337c0482c ] || { echo "the loaded selection function differs from live"; exit 1; }
echo "loaded: selection function = live 1fd3fcde2fcafed6fadf4f6337c0482c"

BEFORE=$($P -At < tests/fixtures/pdesc-self-driving/scenarios.sql | grep .)
for w in 'lost_admitted|description_current' 'lost_verified|description_current' 'lost_past_recheck|eligible' 'lost_manual_lock|manual_lock' 'lost_then_rejected|retry_wait' 'lost_open_work|existing_work' 'described_current|description_current' 'enqueued|lost_past_recheck'; do
  grep -qxF "$w" <<<"$BEFORE" || { echo "before the change: expected $w"; echo "$BEFORE"; exit 1; }; done
echo "before: a cleared description with an admitted read within 180 days is description_current and is not queued, as live"

FNS="select md5(string_agg(p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)), '|' order by p.oid::regprocedure::text)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('security', 'public', 'api') and p.prokind = 'f' and p.proname <> 'provider_description_selection_v1'"
F0=$(q "$FNS"); S0=$(q "select md5(string_agg(key || value::text, '|' order by key)) from pipeline.platform_toolset_settings"); L0=$(q "select count(*) from pipeline.layer4_review_items"); R0=$(q "select count(*) from pipeline.provider_description_reads")
C0=$(q "select count(*) from cron.job" 2>/dev/null || echo none)
OUT=$($P -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
grep -q 'selection_v1(jsonb): applied$' <<<"$OUT" || { echo "the migration did not apply its guarded edit"; echo "$OUT" | tail -5; exit 1; }
AFTER=$(grep -F -- "--   security.provider_description_selection_v1(jsonb) " $MIG | head -1 | sed 's/.*-> *\([0-9a-f]*\).*/\1/')
[ "$(q "select md5(pg_get_functiondef('security.provider_description_selection_v1(jsonb)'::regprocedure))")" = "$AFTER" ] || { echo "selection after: differs from the recorded $AFTER"; exit 1; }
[ "$(q "$FNS")" = "$F0" ] || { echo "the migration changed a function it does not own"; exit 1; }
[ "$(q "select md5(string_agg(key || value::text, '|' order by key)) from pipeline.platform_toolset_settings")" = "$S0" ] || { echo "the migration changed settings"; exit 1; }
[ "$(q "select count(*) from pipeline.layer4_review_items")" = "$L0" ] || { echo "the migration changed Layer 4"; exit 1; }
[ "$(q "select count(*) from pipeline.provider_description_reads")" = "$R0" ] || { echo "the migration changed reads"; exit 1; }
[ "$(q "select count(*) from cron.job" 2>/dev/null || echo none)" = "$C0" ] || { echo "the migration changed jobs"; exit 1; }
OUT=$($P -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
grep -q 'selection_v1(jsonb): already applied$' <<<"$OUT" || { echo "the second run was not a no-op"; exit 1; }
echo "migration: one guarded edit to its recorded after md5 ($AFTER); nothing else changed; applied again: no change"

AFTERS=$($P -At < tests/fixtures/pdesc-self-driving/scenarios.sql | grep .)
EXPECT='lost_admitted|description_lost
lost_verified|description_lost
lost_manual_lock|manual_lock
lost_then_rejected|retry_wait
lost_past_recheck|description_lost
described_current|description_current
lost_identity_finding|identity_identity_unconfirmed
lost_open_work|existing_work
enqueued|lost_admitted,lost_verified,lost_past_recheck'
[ "$AFTERS" = "$EXPECT" ] || { echo "after the change the scenarios differ:"; diff <(echo "$EXPECT") <(echo "$AFTERS"); exit 1; }
echo "after: no description + admitted/verified read -> description_lost and queued; a lock, an open finding, open work, a recent rejection and a held description -> unchanged"
echo "pdesc-self-driving: done"
