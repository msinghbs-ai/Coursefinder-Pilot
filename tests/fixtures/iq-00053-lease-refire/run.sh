#!/usr/bin/env bash
# CF-247 IQ-00053 (an expired lease is asked again; the task shows how its worker calls went; AI calls at once 20 -> 8) on isolated fixtures. Needs a
# scratch PostgreSQL (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Rebuilds today's live enrich_fields_slice_v1 the way the repository
# does (the course-enrichment fixtures' pre-Release-B live text, then migration 20261103210000 with its own md5 guards), checks it is the live md5
# c385d9c3a9fd33614f189773e45683f3 (read 8 Nov 2026 18:50 AEDT), applies 20261108190000 (its own md5 guards and post-check run), applies it again (no change),
# then runs fixtures.sql. Drops the throwaway database at the end (IQ53_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")"
CE=../course-enrichment
DB=${IQ53_DB:-iq53_fixtures}
RELB=../../../supabase/migrations/20261103210000_cf247_release_b_course_enrichment.sql
MIG=../../../supabase/migrations/20261108190000_cf247_iq53_expired_lease_refire.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
[ -n "${IQ53_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null' EXIT
md5of() { $P -d $DB -Atc "select md5(pg_get_functiondef('$1'::regprocedure))"; }
SLICE='security.enrich_fields_slice_v1(uuid,integer)'
$P -d $DB -f $CE/stubs.sql
for f in $CE/live/*.sql; do $P -d $DB -c "set check_function_bodies = off" -f "$f"; done
[ "$(md5of "$SLICE")" = 4babdac64e58459fe38d79def27842ea ] || { echo "loaded slice differs from the 3 Nov live text: $(md5of "$SLICE")"; exit 1; }
$P -d $DB -c "create trigger field_enrich_items_gate before insert on pipeline.field_enrich_items for each row execute function security.field_enrich_items_gate_v1()" \
          -c "create trigger field_enrich_items_flag after update of state on pipeline.field_enrich_items for each row execute function security.field_enrich_items_flag_v1()"
$P -d $DB -f $CE/seed.sql
$P -d $DB -f $CE/fixtures-before.sql 2>&1 | show
$P -d $DB -1 -At -f $RELB >/dev/null
[ "$(md5of "$SLICE")" = c385d9c3a9fd33614f189773e45683f3 ] || { echo "rebuilt slice is not today's live definition: $(md5of "$SLICE")"; exit 1; }
echo "before (rebuilt = live): c385d9c3a9fd33614f189773e45683f3"
$P -d $DB -f setup-before.sql
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT"; exit 1; }
[ "$(grep -c ': applied' <<<"$OUT")" = 1 ] || { echo "the migration did not apply its guarded edit"; echo "$OUT"; exit 1; }
AFTER=$(md5of "$SLICE"); [ "$AFTER" = d68665cb163bb99f7cca088d39cf595b ] || { echo "after md5 $AFTER"; exit 1; }
echo "after: $AFTER"
SNAP="select md5(string_agg(x, '|' order by x)) from (select toolset_key || key || value::text || coalesce(reason, '') x from pipeline.platform_toolset_settings union all select target || detail::text from pipeline.admin_control_events) z"
S1=$($P -d $DB -Atc "$SNAP")
OUT2=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT2"; exit 1; }
[ "$(grep -c 'already applied' <<<"$OUT2")" = 1 ] || { echo "a second run changed the guarded function"; echo "$OUT2"; exit 1; }
[ "$(md5of "$SLICE")" = "$AFTER" ] || { echo "second run changed the slice"; exit 1; }
[ "$($P -d $DB -Atc "$SNAP")" = "$S1" ] || { echo "a second run changed a setting or wrote a second audit event"; exit 1; }
echo "second run: already applied, nothing changed"
$P -d $DB -f fixtures.sql 2>&1 | show
echo "fixtures: all passed"
