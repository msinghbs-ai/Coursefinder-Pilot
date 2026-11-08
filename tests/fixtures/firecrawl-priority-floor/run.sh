#!/usr/bin/env bash
# Guards: Platform Admin 8 Nov 2026 Firecrawl priority order (AER entry pages first), G2, G3, "a passing check never switches anything on", "nothing is dropped or deleted by an applied migration".
# CF-247 Firecrawl priority floor (migration 20261108060000) on an isolated PostgreSQL 16. Scratch server only (PGHOST/PGPORT/PGUSER), never a Supabase project; scratch database names begin g_.
# Builds stubs.sql (live NOT NULL / default constraints), loads the LIVE definitions from live/ (md5s read 8 Nov 2026 on fxcwkweaxjtknorudmwp are checked before anything is applied), also
# loads the live fc_budget_left_v1 under fx_live as the "before" oracle, applies the migration, applies it again (three "already applied", nothing changed), then runs fixtures.sql.
# Every SQL error fails the run. The database is dropped at the end (FCF_KEEP=1 keeps it). No Firecrawl, no AI, no network.
set -euo pipefail
cd "$(dirname "$0")"
ROOT=$(cd ../../.. && pwd)
DB=${FCF_DB:-g_fc_priority_floor}
[[ "$DB" =~ ^g_[a-z0-9_]+$ ]] || { echo 'refused: scratch database name must begin g_' >&2; exit 1; }
P="psql -v ON_ERROR_STOP=1 -q -X"
$P -d postgres <<'SQL'
do $g$ begin
  if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then raise exception 'local database only'; end if;
  if exists (select 1 from pg_namespace where nspname = 'supabase_migrations') and exists (select 1 from pg_roles where rolname = 'supabase_admin') then
    raise exception 'refusing a Supabase project database'; end if;
end $g$;
SQL
cleanup() { local code=$?; trap - EXIT; [ -n "${FCF_KEEP:-}" ] || $P -d postgres -c "drop database if exists $DB" >/dev/null || code=1; exit "$code"; }
trap cleanup EXIT
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
M=$ROOT/supabase/migrations/20261108060000_cf247_firecrawl_priority_floor.sql
notices() { sed -n 's/^.*\(NOTICE\|ERROR\|WARNING\):  /\1 /p'; }
$P -d $DB -f stubs.sql
# live definitions: unedited helpers, the three the migration edits, the monthly rule it copies, and the queue-watch tool state it must keep working. Each file is checked against the
# md5 read from the live project (8 Nov 2026) before it is loaded, and the loaded function against the same md5 afterwards.
LIVE=(
  "security.fc_setting_num_v1|fc_setting_num_v1(text,numeric)|fcbad3b84ed5b9793f5fc94e26b7d90b"
  "security.fc_day_start_v1|fc_day_start_v1()|f5113f936c0c2a473e0d74cca51b5d97"
  "security.fc_billed_today_v1|fc_billed_today_v1()|ba8c0e39d07a1d7aaba8cdea92de620a"
  "security.fc_on_demand_today_v1|fc_on_demand_today_v1()|782b58492f258102047038e12f5512e4"
  "security.fc_purpose_group_v1|fc_purpose_group_v1(text)|348bbb9ec1db966755e532f23e376897"
  "security.fc_month_refusal_v1|fc_month_refusal_v1(numeric)|8c1419332ff503abd69539ccbad1121d"
  "security.fc_budget_left_v1|fc_budget_left_v1(text)|e979d2e3d7319d845a5149e40abe6987"
  "public.svc_fc_spend|svc_fc_spend(numeric,text,uuid,text)|a9217c5af8e0da8ee18b03bcab9eaeef"
  "security.lane_paid_hold_v1|lane_paid_hold_v1(text)|99ec517b8b51b0d1305b739e7f1562fb"
  "security.queue_watch_tool_state_v1|queue_watch_tool_state_v1(text)|b13cb37e2ac871f899679420866d43ab" )
md5of() { $P -d $DB -Atc "select md5(pg_get_functiondef('$1'::regprocedure))"; }
for row in "${LIVE[@]}"; do
  IFS='|' read -r f sig want <<<"$row"
  [ "$(md5sum < live/$f.sql | cut -d' ' -f1)" = "$want" ] || { echo "live/$f.sql is not the live text (md5 $want)"; exit 1; }
  $P -d $DB -f live/$f.sql
  [ "$(md5of "${f%%.*}.$sig")" = "$want" ] || { echo "loaded $f differs from live"; exit 1; }
done
echo 'before: the live definitions are loaded (md5s = live, 8 Nov 2026)'
# the oracle: the live fc_budget_left_v1 text under another schema name
$P -d $DB -c "create schema fx_live"
sed 's/security\.fc_budget_left_v1/fx_live.fc_budget_left_v1/' live/security.fc_budget_left_v1.sql | $P -d $DB -q
$P -d $DB -f setup.sql
# the migration: applied once (inside one transaction), then again
OUT=$($P -d $DB -1 -At -f "$M" 2>&1) || { echo "$OUT" | tail -8; echo 'migration failed'; exit 1; }
echo "$OUT" | grep -c ': applied' | grep -qx 3 || { echo "the first run did not apply the three edits: $OUT"; exit 1; }
SNAP="select (select count(*) from pipeline.platform_toolset_settings) || '/' || (select count(*) from pipeline.admin_control_events) || '/' || md5(pg_get_functiondef('security.fc_budget_left_v1(text)'::regprocedure)) || md5(pg_get_functiondef('public.svc_fc_spend(numeric,text,uuid,text)'::regprocedure)) || md5(pg_get_functiondef('security.lane_paid_hold_v1(text)'::regprocedure)) || md5(pg_get_functiondef('security.fc_vendor_estimate_v1()'::regprocedure)) || md5(pg_get_functiondef('security.fc_priority_room_v1()'::regprocedure))"
S1=$($P -d $DB -Atc "$SNAP")
AGAIN=$($P -d $DB -1 -At -f "$M" 2>&1) || { echo "$AGAIN" | tail -5; echo 'second run failed'; exit 1; }
echo "$AGAIN" | grep -c 'already applied' | grep -qx 3 || { echo "the second run did not report already applied three times: $AGAIN"; exit 1; }
[ "$($P -d $DB -Atc "$SNAP")" = "$S1" ] || { echo 'a second run changed something'; exit 1; }
echo 'migration 20261108060000 applied twice; the second run reported already applied three times and changed nothing'
# the md5s the migration records are the ones the scratch copy of the live definitions gives
for want in "security.fc_budget_left_v1(text)" "public.svc_fc_spend(numeric,text,uuid,text)" "security.lane_paid_hold_v1(text)"; do
  m=$(md5of "$want"); grep -q "$m" "$M" || { echo "the migration does not record the applied md5 $m of $want"; exit 1; }
done
OUT=$($P -d $DB -f fixtures.sql 2>&1) || { echo "$OUT" | grep -E 'FAIL|ERROR' | head -5; echo 'fixtures failed'; exit 1; }
echo "$OUT" | notices | sed 's/^NOTICE //'
[ "$(echo "$OUT" | grep -c 'NOTICE:  PASS')" -ge 50 ] || { echo 'fewer fixture checks passed than expected'; exit 1; }
echo "$OUT" | grep -q 'FAIL' && { echo 'a fixture check failed'; exit 1; }
echo "fixtures: $(echo "$OUT" | grep -c 'NOTICE:  PASS') checks passed"

# the controller's addition: migration 20261108061000 (plan record and daily shares re-sized to the 100,000-credit plan), guarded, idempotent, audited
M2=$ROOT/supabase/migrations/20261108061000_cf247_firecrawl_plan_100k_shares.sql
chk() { local o; o=$($P -d $DB -f "$1" 2>&1) || { echo "$o" | grep -E 'FAIL|ERROR' | head -5; echo "$1 failed"; exit 1; }; echo "$o" | notices | sed 's/^NOTICE //' | grep PASS; }
$P -d $DB -f plan100k-a.sql
RUN1=$($P -d $DB -1 -f "$M2" 2>&1) || { echo "$RUN1" | tail -5; echo 'plan migration failed'; exit 1; }
[ "$(echo "$RUN1" | grep -c ': applied')" = 7 ] || { echo "the first run did not apply all seven changes: $RUN1"; exit 1; }
chk plan100k-b.sql
RUN2=$($P -d $DB -1 -f "$M2" 2>&1) || { echo "$RUN2" | tail -5; exit 1; }
[ "$(echo "$RUN2" | grep -c 'already applied')" = 7 ] || { echo "the second run did not report already applied seven times: $RUN2"; exit 1; }
echo 'migration 20261108061000 applied twice; the second run reported already applied seven times'
chk plan100k-c.sql
RUN3=$($P -d $DB -1 -f "$M2" 2>&1) || { echo "$RUN3" | tail -5; exit 1; }
echo "$RUN3" | grep -q 'daily_share_reads: the current value is 4321 (not 5000); nothing changed' || { echo "no notice for the changed value: $RUN3"; exit 1; }
echo "$RUN3" | grep -q 'plan record: the current values are not (500000, growth_500k)' || { echo "no notice for the changed plan record: $RUN3"; exit 1; }
[ "$(echo "$RUN3" | grep -c ': applied')" = 5 ] || { echo "the mixed run did not apply exactly five: $RUN3"; exit 1; }
chk plan100k-d.sql
chk plan100k-e.sql
echo 'plan100k: guarded apply, changed-value skip, second-run no-op and fc_budget_left_v1 on the new shares: passed'
