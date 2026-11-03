#!/usr/bin/env bash
# CF-247 AER missing-university strategy, workstream C (Platform Admin 3 Nov 2026 16:24) on isolated fixtures. Needs a scratch PostgreSQL (never a
# Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds the workstream C coverage fixture database (../ops-coverage-sch-aer/run.sh: live
# definitions checked against their live md5s, migration 20261104040000 applied twice, its cases run), adds the eight universities (data.sql),
# applies 20261104090000 (md5 guards on workstream C's own functions, post-check), applies it again (nothing changes), rehearses the paste file and
# its rollback, then runs fixtures.sql. Drops the database at the end (OPSAM_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")"
DB=${OPSAM_DB:-ops_aer_missing_fixtures}
ROOT=../../..
MIG=$ROOT/supabase/migrations/20261104090000_cf247_ops_c_aer_missing_universities.sql
PASTE=$ROOT/docs/paste/PASTE-20261104-aer-missing-university-sources.sql
ROLL=$ROOT/docs/paste/PASTE-20261104-aer-missing-university-sources-rollback.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
md5of() { $P -d $DB -Atc "select md5(pg_get_functiondef('$1'::regprocedure))"; }
OPSC_KEEP=1 OPSC_DB=$DB ../ops-coverage-sch-aer/run.sh | tail -1
[ -n "${OPSAM_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT
for s in 'security.aer_coverage_v1(uuid[])' 'security.coverage_due_v1(text,integer)'; do
  b=$(grep -F -- "--   $s " $MIG | awk '{print $3}')
  [ "$(md5of "$s")" = "$b" ] || { echo "$s is not the definition of 20261104040000 ($(md5of "$s"), expected $b)"; exit 1; }
done
echo "before: workstream C's aer_coverage_v1 and coverage_due_v1 as 20261104040000 leaves them"
$P -d $DB -f data.sql >/dev/null
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': applied$')" = 2 ] || { echo "the migration did not apply its two guarded edits"; echo "$OUT" | tail -5; exit 1; }
for s in 'security.aer_coverage_v1(uuid[])' 'security.coverage_due_v1(text,integer)'; do
  a=$(grep -F -- "--   $s " $MIG | awk '{print $5}')
  [ "$(md5of "$s")" = "$a" ] || { echo "after md5 of $s: $(md5of "$s")"; exit 1; }; echo "after: $s $a"
done
S1=$($P -d $DB -Atc "select md5(string_agg(x, '|' order by x)) from (select provider_id || role || url_key || outcome x from pipeline.aer_source_inventory union all select code from pipeline.ops_root_causes union all select code || coalesce(verify_fn::text, '') from pipeline.ops_remedies union all select kind || name from pipeline.component_register) s")
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': already applied$')" = 2 ] || { echo "a second run changed a function"; exit 1; }
[ "$($P -d $DB -Atc "select md5(string_agg(x, '|' order by x)) from (select provider_id || role || url_key || outcome x from pipeline.aer_source_inventory union all select code from pipeline.ops_root_causes union all select code || coalesce(verify_fn::text, '') from pipeline.ops_remedies union all select kind || name from pipeline.component_register) s")" = "$S1" ] || { echo "a second run changed the inventory, causes, remedies or register"; exit 1; }
echo "second run: already applied, unchanged"
$P -d $DB -f fixtures.sql 2>&1 | show
$P -d $DB -f $PASTE >/dev/null
[ "$($P -d $DB -Atc "select count(*) from pipeline.entry_matrix_sources where found_via = 'manual' and provider_id in ('6f5cb7f7-7c70-4c06-970f-f368c3a786e2','551383f9-7732-4588-a843-dd2b97c13f6f','fa0e0d13-838a-42ff-b6a3-9cea84bd80b2','fec52f92-a8a3-4de8-a862-06f355e4e2f7')")" = 4 ] || { echo "paste file did not attach 4"; exit 1; }
if $P -d $DB -f $PASTE >/dev/null 2>&1; then echo "the paste file ran twice"; exit 1; fi
echo "paste file: 4 sources attached; a second run is refused"
$P -d $DB -f fixtures-after-paste.sql 2>&1 | show
$P -d $DB -f $ROLL >/dev/null
[ "$($P -d $DB -Atc "select count(*) from pipeline.entry_matrix_sources where provider_id in ('6f5cb7f7-7c70-4c06-970f-f368c3a786e2','551383f9-7732-4588-a843-dd2b97c13f6f','fa0e0d13-838a-42ff-b6a3-9cea84bd80b2','fec52f92-a8a3-4de8-a862-06f355e4e2f7')")" = 0 ] || { echo "rollback did not remove the 4"; exit 1; }
$P -d $DB -f $PASTE >/dev/null
$P -d $DB -c "update pipeline.entry_matrix_sources set status = 'read', read_at = now(), content_hash = 'h' where url = 'https://www.cdu.edu.au/international/how-apply/entry-requirements'" >/dev/null
if $P -d $DB -f $ROLL >/dev/null 2>&1; then echo "rollback removed a read source"; exit 1; fi
echo "rollback: removes the 4 while unread; refused once one has been read"
echo "all AER missing-university fixtures passed"
