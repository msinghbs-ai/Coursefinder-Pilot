#!/usr/bin/env bash
# Guards: CF-247 Operations load speed (Platform Admin P1, 10 Nov 2026): migration 20261110020000 edits only five functions (lane_funnel_v1, lane_funnel_refresh_v1, intake_progress_repeats_v1, process_results_recovery_v1, admin_layer23; each md5-guarded), adds one table, one writer, one index and two settings, and the same questions give the same answers.
# Needs a scratch PostgreSQL 16 or 17 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds the lane-funnels fixture database (live lane_funnel_v1 and lane_funnel_refresh_v1: md5 = production), loads the live text of the other
# edited functions (live-functions.sql), seeds scheduler history and intake events, captures the answers, applies the migration (and refuses it over a hand-changed function), compares, runs the scenarios (after.sql), applies it again (no change),
# runs the held forward recovery (md5 back to the production text) and applies the migration once more. Drops the database at the end (OLS_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${OLS_DB:-g_ops_load_speed}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X"
F=tests/fixtures/operations-load-speed
MIG=supabase/migrations/20261110020000_cf247_operations_load_speed.sql
REC=supabase/held/operations_load_speed_forward_recovery.sql
q() { psql -X -d "$1" -Atc "$2"; }
cleanup() { for d in "$DB" "${DB}_refuse" "${DB}_idx"; do $P -d postgres -c "drop database if exists $d" >/dev/null 2>&1 || true; done; }
[ -n "${OLS_KEEP:-}" ] || trap cleanup EXIT
cleanup
$P -d postgres -c "create database $DB" >/dev/null
$P -d $DB -f tests/fixtures/lane-funnels/schema.sql >/dev/null
$P -d $DB -f supabase/migrations/20261108170000_cf247_lane_funnels.sql >/dev/null 2>&1
PGOPTIONS='-c check_function_bodies=off' $P -d $DB -f $F/schema-extra.sql >/dev/null
PGOPTIONS='-c check_function_bodies=off' $P -d $DB -f $F/live-functions.sql >/dev/null

# the edited functions are the live ones (md5 of the function body, pg_proc.prosrc, read 10 Nov 2026 AEDT, from production)
declare -A LIVE=( ['security.lane_funnel_v1(text)']=cd8ecc118783da99f50c6fbd035cd3c1 ['security.lane_funnel_refresh_v1(boolean)']=e3e4280b536fe985822608139714434e
  ['security.intake_progress_repeats_v1()']=3f4a208ca8e0252eb17a1e21e73f80ca ['security.process_results_recovery_v1()']=0bb7a5bd32ba384bf341214c9a5a9c3c ['public.admin_layer23(text,jsonb)']=4c99a80f6899cda0d836dcc4196534de )
for sig in "${!LIVE[@]}"; do
  [ "$(q $DB "select md5(prosrc) from pg_proc where oid = '$sig'::regprocedure")" = "${LIVE[$sig]}" ] || { echo "the loaded $sig differs from live ${LIVE[$sig]}"; exit 1; }
done
echo "loaded: the five edited functions = live (body md5 recorded in the migration header)"

$P -d $DB -f $F/seed.sql >/dev/null
$P -d $DB -f $F/before.sql >/dev/null
echo "before: lane funnels (all lanes and one), repeat check and recovery measurement captured from the live text on the seeded history"

FNS="select p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public', 'api') and p.prokind = 'f' order by 1"
SET="select toolset_key || '.' || key || '=' || value::text from pipeline.platform_toolset_settings order by 1"
snap() { q "$DB" "$FNS" | sort > "$1.fn"; q "$DB" "$SET" | sort > "$1.set"; q "$DB" "select string_agg(schemaname || '.' || tablename, ',' order by 1) from pg_tables where schemaname in ('pipeline','cron','catalogue')" > "$1.tabs"
  q "$DB" "select string_agg(indexname, ',' order by indexname) from pg_indexes where schemaname in ('pipeline','cron','catalogue')" > "$1.ix"; q "$DB" "select count(*) || '/' || (select count(*) from cron.job) || '/' || (select count(*) from cron.job_run_details) || '/' || (select count(*) from pipeline.lane_funnel_lanes) || '/' || (select count(*) from pipeline.lane_funnel_stages) from pipeline.automation_catalogue" > "$1.cnt"; }
W=$(mktemp -d); trap 'rm -rf "$W"; [ -n "${OLS_KEEP:-}" ] || cleanup' EXIT

# a live function that differs from the recorded one: the migration raises, and nothing at all is applied
RF=${DB}_refuse
for target in 'security.lane_funnel_v1(text)|lane funnel read' 'security.process_results_recovery_v1()|recovery measurement' 'public.admin_layer23(text,jsonb)|Layer 2/3 operations'; do
  IFS='|' read -r sig what <<<"$target"
  $P -d postgres -c "drop database if exists $RF" >/dev/null 2>&1; $P -d postgres -c "create database $RF template $DB" >/dev/null
  cat > "$W/hand.sql" <<HAND
do \$\$ declare d text := pg_get_functiondef('$sig'::regprocedure); n text;
begin
  n := regexp_replace(d, '\\\$function\\\$\\s*\$', '/* changed by hand */ \$function\$' || chr(10));
  if n = d then raise exception 'no change by hand'; end if;
  execute n;
end \$\$;
HAND
  psql -X -q -d $RF -v ON_ERROR_STOP=1 -f "$W/hand.sql" >/dev/null 2>"$W/err" || { cat "$W/err"; echo "could not change $what by hand"; exit 1; }
  rb=$( (q $RF "$FNS" | sort | md5sum; q $RF "$SET" | sort | md5sum; q $RF "select count(*) from pg_class where relname = 'lane_funnel_job_runs'") )
  OUT=$(psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $MIG 2>&1) && { echo "the migration applied over a changed $what"; exit 1; }
  grep -qF "differs from the definition this change edits" <<<"$OUT" || { echo "the refusal is not the expected one: $OUT" | tail -3; exit 1; }
  ra=$( (q $RF "$FNS" | sort | md5sum; q $RF "$SET" | sort | md5sum; q $RF "select count(*) from pg_class where relname = 'lane_funnel_job_runs'") )
  [ "$rb" = "$ra" ] || { echo "the refused migration changed something ($what)"; exit 1; }
done
$P -d postgres -c "drop database if exists $RF" >/dev/null
echo "refused: a hand-changed lane funnel read, recovery measurement and Layer 2/3 operations are each refused and nothing is applied (no function, setting or table)"

# apply: five functions go from the recorded live md5 to the recorded after md5; one writer, one table, one index and two settings are added
snap "$W/0"
OUT=$($P -d $DB -At -1 -f $MIG 2>&1) || { echo "$OUT" | tail -8; exit 1; }
for sig in "${!LIVE[@]}"; do
  grep -qF "$sig: applied" <<<"$OUT" || { echo "$sig was not edited"; echo "$OUT" | tail -8; exit 1; }
  after=$(grep -F -- "--   $sig " $MIG | head -1 | sed 's/.*-> *\([0-9a-f]*\).*/\1/')
  [ "$(q $DB "select md5(prosrc) from pg_proc where oid = '$sig'::regprocedure")" = "$after" ] || { echo "$sig after the change differs from the recorded $after"; exit 1; }
done
snap "$W/1"
want=$(for sig in "${!LIVE[@]}"; do echo "${sig#public.}"; done | sort)
changed=$(comm -23 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//' | sort)
[ "$changed" = "$want" ] || { echo "the changed functions differ from the edited ones"; diff <(echo "$want") <(echo "$changed"); exit 1; }
added=$(comm -13 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//' | sort | comm -23 - <(echo "$want"))
[ "$added" = "security.lane_funnel_job_runs_refresh_v1(boolean)" ] || { echo "the migration added functions other than the writer: $added"; exit 1; }
[ "$(comm -13 "$W/0.set" "$W/1.set" | sed 's/=.*//' | sort | tr '\n' ' ')" = "pipeline.lane_funnel.job_runs_refresh_seconds pipeline.lane_funnel.job_runs_stale_minutes " ] || { echo "the settings added are not exactly the two"; exit 1; }
[ "$(comm -23 "$W/0.set" "$W/1.set" | wc -l)" = 0 ] || { echo "the migration changed or removed a setting value"; exit 1; }
[ "$(comm -13 <(tr ',' '\n' < "$W/0.tabs" | sort) <(tr ',' '\n' < "$W/1.tabs" | sort))" = "pipeline.lane_funnel_job_runs" ] || { echo "the only new table should be pipeline.lane_funnel_job_runs"; exit 1; }
[ "$(comm -13 <(tr ',' '\n' < "$W/0.ix" | sort) <(tr ',' '\n' < "$W/1.ix" | sort) | tr '\n' ' ')" = "evidence_artifacts_link_queue_idx lane_funnel_job_runs_pkey " ] || { echo "the new indexes should be the table key and evidence_artifacts_link_queue_idx"; exit 1; }
[ "$(cut -d/ -f2- "$W/0.cnt")" = "$(cut -d/ -f2- "$W/1.cnt")" ] || { echo "the migration changed job, run, lane or stage rows: $(cat $W/0.cnt) -> $(cat $W/1.cnt)"; exit 1; }
echo "migration: 5 edits from the recorded live md5 to the recorded after md5; 1 writer, 1 table, 1 index, 2 settings added; no other function, setting value, job, run, lane or stage changed"

# the answers after the change, and the scenarios
OUT=$(psql -X -v ON_ERROR_STOP=1 -d $DB -f $F/after.sql 2>&1) || { echo "$OUT" | grep -E 'FAILED|ERROR' ; exit 1; }
echo "$OUT" | grep 'NOTICE:  ok:' | sed 's/^[^N]*NOTICE:  //'
echo "assertions passed: $(echo "$OUT" | grep -c 'NOTICE:  ok:')"

# the partial index is kept only for its benefit: the migration's own statement, on a scratch table of the live size (208 thousand evidence rows)
sed -n '/^create index if not exists evidence_artifacts_link_queue_idx/,/;$/p' $MIG > "$W/idx.sql"
[ "$(grep -c '^create index' "$W/idx.sql")" = 1 ] || { echo "could not read the index statement from the migration"; exit 1; }
IX=${DB}_idx
$P -d postgres -c "drop database if exists $IX" >/dev/null 2>&1; $P -d postgres -c "create database $IX" >/dev/null
OUT=$(psql -X -d $IX -v ON_ERROR_STOP=1 -v idxfile="$W/idx.sql" -f $F/index-benefit.sql 2>&1) || { echo "$OUT" | tail -12; exit 1; }
echo "$OUT" | grep -E 'NOTICE: +(link queue|ok:)' | sed 's/^[^N]*NOTICE:  //'
$P -d postgres -c "drop database if exists $IX" >/dev/null

# applied again: no change (the migration is idempotent; the summary is made again, which changes only its own row)
snap "$W/2"
OUT=$($P -d $DB -At -1 -f $MIG 2>&1) || { echo "$OUT" | tail -8; exit 1; }
for sig in "${!LIVE[@]}"; do grep -qF "$sig: already applied" <<<"$OUT" || { echo "the second run was not a no-op for $sig"; exit 1; }; done
snap "$W/3"; for f in fn set tabs ix cnt; do cmp -s "$W/2.$f" "$W/3.$f" || { echo "the second run changed $f"; exit 1; }; done
echo "applied again: no change"

# forward recovery: byte for byte back to the production text (the md5 recorded before the migration); what the migration added stays
OUT=$($P -d $DB -At -1 -f $REC 2>&1) || { echo "$OUT" | tail -8; exit 1; }
for sig in "${!LIVE[@]}"; do
  [ "$(q $DB "select md5(prosrc) from pg_proc where oid = '$sig'::regprocedure")" = "${LIVE[$sig]}" ] || { echo "recovery: $sig is not back to ${LIVE[$sig]}"; exit 1; }
done
[ "$(q $DB "select count(*) from pg_class where relname = 'lane_funnel_job_runs'")" = 1 ] || { echo "the recovery removed the table"; exit 1; }
OUT=$($P -d $DB -At -1 -f $REC 2>&1) || { echo "$OUT" | tail -8; exit 1; }
for sig in "${!LIVE[@]}"; do grep -qF "$sig: already applied" <<<"$OUT" || { echo "the second recovery was not a no-op for $sig"; exit 1; }; done
ol=$(q $DB "select (security.lane_funnel_v1(null) ? 'lanes') and not (security.lane_funnel_v1(null) ? 'job_history')")
[ "$ol" = t ] || { echo "after the recovery the lane funnel read does not answer in its old shape"; exit 1; }
echo "recovery: the five functions are back to the production md5 (lane funnel read, its job, repeat check, recovery measurement, Layer 2/3 operations); the old lane funnel read answers in its old shape; applied twice: no change"
$P -d $DB -At -1 -f $MIG >/dev/null 2>&1 || { echo "the migration did not apply again after the recovery"; exit 1; }
for sig in "${!LIVE[@]}"; do [ "$(q $DB "select md5(prosrc) from pg_proc where oid = '$sig'::regprocedure")" != "${LIVE[$sig]}" ] || { echo "$sig is still the old text after re-applying"; exit 1; }; done
echo "migration applied again after the recovery: all five edited"
echo "operations-load-speed: done"
