#!/usr/bin/env bash
# Guards: Platform Admin directive 10 Nov 2026 (Fill description / Recheck description on demand through the existing Enrich fields engine; bounded; reason; idempotent; never bypasses locks, rejection memory,
# hidden providers, binding/identity checks; verify keeps Website, Zoho and HTTP apart) and G2/G3 for migration 20261110070000 (md5-guarded edit of public.admin_enrich_fields, forward recovery).
# Real isolated PostgreSQL only (production-parity fixture, same capture as ../course-description-parity). Every SQL error fails the run.
set -euo pipefail
cd "$(dirname "$0")"
ROOT=../../..
PAR=../course-description-parity
DB=${CDOD_DB:-g_cdesc_ondemand}
[[ "$DB" =~ ^g_[a-z0-9_]+$ ]] || { echo 'refused: scratch database name must begin g_' >&2; exit 1; }
P="psql -v ON_ERROR_STOP=1 -q -X"
$P -d postgres <<'SQL'
do $g$ begin
  if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then raise exception 'local database only'; end if;
  if exists (select 1 from pg_namespace where nspname = 'supabase_migrations') and exists (select 1 from pg_roles where rolname = 'supabase_admin') then
    raise exception 'refusing a Supabase project database'; end if;
end $g$;
SQL
WORK=$(mktemp -d)
cleanup() { local code=$?; trap - EXIT; [ -n "${CDOD_KEEP:-}" ] || $P -d postgres -c "drop database if exists $DB" -c "drop database if exists ${DB}_refuse" >/dev/null || code=1; rm -rf "$WORK"; exit "$code"; }
trap cleanup EXIT
MIG=$ROOT/supabase/migrations/20261110070000_cf247_cdesc_on_demand.sql
REC=$ROOT/supabase/held/cdesc_on_demand_forward_recovery.sql
node "$ROOT/scripts/prod-parity-capture.mjs" fixture $PAR/manifest-register.json >"$WORK/register.sql"
node "$ROOT/scripts/prod-parity-capture.mjs" fixture $PAR/manifest.json >"$WORK/fixture.sql"
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
$P -d "$DB" -c "create schema if not exists extensions; create or replace function extensions.gen_random_uuid() returns uuid language sql as 'select pg_catalog.gen_random_uuid()'" >/dev/null
$P -d "$DB" -f "$WORK/register.sql" 2>&1 | sed -n 's/^.*\(ERROR\):  /\1 /p'
$P -d "$DB" -f "$WORK/fixture.sql" 2>&1 | sed -n 's/^.*\(ERROR\):  /\1 /p'
$P -d "$DB" -f $PAR/settings.sql
$P -d "$DB" -f $PAR/publication.sql
$P -d "$DB" -f stubs.sql 2>&1 | sed -n 's/^.*\(ERROR\):  /\1 /p'
$P -d "$DB" -f live/captured.sql 2>&1 | sed -n 's/^.*NOTICE:  //p'
$P -d "$DB" -f live/public.admin_enrich_fields.sql
LIVE=c9701d334b732a729a30a5147d9d016b
q() { psql -X -d "$DB" -Atc "$1"; }
body() { q "select md5(prosrc) from pg_proc where oid = 'public.admin_enrich_fields(text,jsonb)'::regprocedure"; }
[ "$(body)" = "$LIVE" ] || { echo "the loaded public.admin_enrich_fields is not the live one ($LIVE)"; exit 1; }
echo "loaded: public.admin_enrich_fields = live (body md5 $LIVE)"
AFTER=$(grep -o -- '-> [0-9a-f]\{32\}' $MIG | head -1 | sed 's/-> //')

# a live function that differs from the recorded one: the migration raises and changes nothing
RF=${DB}_refuse
$P -d postgres -c "drop database if exists $RF" >/dev/null; createdb -T $DB $RF
psql -X -q -d $RF -v ON_ERROR_STOP=1 -c "do \$\$ begin execute regexp_replace(pg_get_functiondef('public.admin_enrich_fields(text,jsonb)'::regprocedure), 'declare v_rank int', 'declare v_hand int; v_rank int'); end \$\$" >/dev/null
OUT=$(psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $MIG 2>&1) && { echo "the migration applied over a changed function"; exit 1; }
grep -qF "differs from the definition this change edits" <<<"$OUT" || { echo "the refusal is not the expected one: $OUT" | tail -3; exit 1; }
[ -z "$(psql -X -d $RF -Atc "select 1 from pg_proc where proname in ('cdesc_state_v1', 'cdesc_on_demand_v1', 'admin_course_description_state_v1')")" ] || { echo "the refused migration left a function behind"; exit 1; }
dropdb --if-exists $RF >/dev/null 2>&1
echo "refused: a hand-changed public.admin_enrich_fields is refused and nothing is applied"

snap() { q "select p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public', 'api') and p.prokind = 'f' order by 1" | sort > "$1.fn"
  q "select toolset_key || '.' || key || '=' || value::text from pipeline.platform_toolset_settings order by 1" | sort > "$1.set"; q "select count(*) from catalogue.courses" > "$1.courses"
  q "select string_agg(n.nspname || '.' || c.relname, ',' order by 1) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname in ('pipeline', 'catalogue', 'public', 'search') and c.relkind in ('r', 'v', 'm')" > "$1.rel"; }
snap "$WORK/0"
OUT=$($P -d "$DB" -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -8; exit 1; }
grep -qF "public.admin_enrich_fields(text,jsonb): applied" <<<"$OUT" || { echo "the function was not edited: $OUT"; exit 1; }
[ "$(body)" = "$AFTER" ] || { echo "public.admin_enrich_fields after the change is not the recorded $AFTER"; exit 1; }
OUT=$($P -d "$DB" -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -8; exit 1; }
grep -qF "public.admin_enrich_fields(text,jsonb): already applied" <<<"$OUT" || { echo "a second run is not a no-op: $OUT"; exit 1; }
echo "migration 20261110070000 applied twice without error (second run: already applied); body md5 $LIVE -> $AFTER"
snap "$WORK/1"
changed=$(comm -23 "$WORK/0.fn" "$WORK/1.fn" | sed 's/ [0-9a-f]*$//' | sort -u)
[ "$changed" = "admin_enrich_fields(text,jsonb)" ] || { echo "the migration changed a function other than admin_enrich_fields: $changed"; exit 1; }
added=$(comm -13 "$WORK/0.fn" "$WORK/1.fn" | sed 's/ [0-9a-f]*$//' | sort -u | tr '\n' ' ')
[ "$added" = "admin_course_description_state_v1(uuid[]) admin_enrich_fields(text,jsonb) security.cdesc_block_info_v1(text) security.cdesc_machine_ids_v1(uuid[]) security.cdesc_on_demand_v1(text,jsonb,integer,uuid) security.cdesc_state_v1(uuid[],uuid) " ] || { echo "functions added or edited: $added"; exit 1; }
cmp -s "$WORK/0.courses" "$WORK/1.courses" && cmp -s "$WORK/0.rel" "$WORK/1.rel" || { echo "the migration added a table or changed rows of the catalogue"; exit 1; }
# settings: no setting is added or changed; only used_by of two existing ones (not part of the value snapshot)
cmp -s "$WORK/0.set" "$WORK/1.set" || { echo "the migration added or changed a setting"; diff "$WORK/0.set" "$WORK/1.set"; exit 1; }
[ "$(q "select count(*) from pipeline.platform_toolset_settings where used_by like '%cdesc_on_demand_v1%'")" = 2 ] || { echo "used_by of the two existing settings was not extended"; exit 1; }
echo "applied: only public.admin_enrich_fields changed; five functions added; no setting, table, column or catalogue row added or changed"

$P -d "$DB" -f scenarios.sql >"$WORK/scen.raw" 2>&1 || true
OUT=$(sed -n 's/^.*\(NOTICE\|ERROR\|WARNING\):  /\1 /p' "$WORK/scen.raw" | grep -v '^NOTICE:  schema\|already exists' || true)
echo "$OUT" | grep -v '^NOTICE PASS' || true
echo "$OUT" | grep -q '^ERROR' && { grep -B1 -A4 "ERROR" "$WORK/scen.raw" | head -20; echo "scenarios hit an ERROR"; exit 1; }
echo "$OUT" | grep -q '^NOTICE FAIL' && { echo "scenarios FAILED"; exit 1; }
echo "$OUT" | grep -q 'cdesc on demand: all scenarios ran' || { echo "scenarios did not finish"; exit 1; }
echo "scenarios: $(echo "$OUT" | grep -c '^NOTICE PASS') checks passed"

# forward recovery: the production text, byte for byte, and the migration applies again after it
$P -d "$DB" -1 -f $REC
[ "$(body)" = "$LIVE" ] || { echo "forward recovery did not restore the live body md5 $LIVE (got $(body))"; exit 1; }
$P -d "$DB" -1 -f $REC | grep -q . && true
echo "forward recovery: public.admin_enrich_fields back to body md5 $LIVE; a second run is a no-op"
OUT=$($P -d "$DB" -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
grep -qF "public.admin_enrich_fields(text,jsonb): applied" <<<"$OUT" && [ "$(body)" = "$AFTER" ] || { echo "the migration did not apply again after the recovery"; exit 1; }
echo "re-applied after recovery: body md5 $AFTER"
echo 'course description on demand (Fill / Recheck / verify): all passed'
