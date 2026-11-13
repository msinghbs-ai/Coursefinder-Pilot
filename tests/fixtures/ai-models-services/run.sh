#!/usr/bin/env bash
# CF-247 AI models and services (migration 20261113380000) on isolated fixtures. Needs a scratch PostgreSQL 16 (never a Supabase project):
# PGHOST/PGPORT/PGUSER point at it. Builds two throwaway databases from stubs.sql (the live shapes, cut down), live/ (the definitions the change
# edits or calls, as pg_get_functiondef gave them on 13 Nov 2026, each checked against its live md5) and data.sql (the same rows in both):
#   <db>_before  stays as live: the three readers are called there to record the keys the deployed worker reads
#   <db>         gets the migration
# Then: a drifted live body is refused and leaves nothing; the migration applies its four guarded edits to their after md5s and changes no other
# function; a second run changes nothing; the worker-facing keys of the three readers keep their names and types (new keys only beside them);
# fixtures.sql (route resolution, cascade order, a not_allowed model skipped, caps and the daily ceiling, the writes and their refusals, the
# ledger, the page read). Drops the databases at the end (AIMS_KEEP=1 keeps them).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${AIMS_DB:-ai_models_services_fixtures}
P="psql -v ON_ERROR_STOP=1 -q -X"
MIG=supabase/migrations/20261113380000_cf247_ai_models_services.sql
FX=tests/fixtures/ai-models-services
q() { $P -d "$1" -Atc "$2"; }
md5of() { q "$1" "select md5(pg_get_functiondef('$2'::regprocedure))"; }
hdr() { grep -F -- "--   $1 " $MIG | head -1 | sed 's/.*  \([0-9a-f]\{32\}\) -> \([0-9a-f]\{32\}\).*/\1 \2/'; }
DBS="$DB ${DB}_before ${DB}_drift"
for d in $DBS; do $P -d postgres -c "drop database if exists $d" -c "create database $d" >/dev/null 2>&1; done
[ -n "${AIMS_KEEP:-}" ] || trap 'for d in $DBS; do $P -d postgres -c "drop database if exists $d" >/dev/null 2>&1; done' EXIT

EDITED=("public.svc_enrich_ai_next(integer)" "public.svc_entry_matrix_next(integer)" "public.svc_ops_diagnosis_next(integer)" "security.ai_spend_capture_v1()")
declare -A LIVE=(
  ["public.svc_enrich_ai_next(integer)"]=e4bdf62857d011458e3293006a7e7426
  ["public.svc_entry_matrix_next(integer)"]=3eb6ca3bb909cda113e2c1ee79704a42
  ["public.svc_ops_diagnosis_next(integer)"]=adc209ebf9196c613e3dd82fa76fed61
  ["security.ai_spend_capture_v1()"]=5b78fa074a9480d4f127ecc4fe93dcf3
  ["security.ai_spend_today_v1()"]=0a8e30c2d38c37071474fdd23fa31cfc
  ["security.ai_use_refusal_v1(text)"]=60c782e5aec7eb218c1149a3ad85dde2
  ["security.pipeline_num_v1(text,numeric)"]=09f9b1551daf42b4a0c9795e6f30c6d4
  ["security.toolset_setting(text,text)"]=678dbbc416c5188ab99b3526e68b0c4d
)
# 1 the databases as live
for d in $DBS; do
  $P -d $d -f $FX/stubs.sql
  for f in $FX/live/*.sql; do $P -d $d -c "set check_function_bodies = off" -f "$f"; done
  for s in "${!LIVE[@]}"; do [ "$(md5of $d "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of $d "$s")"; exit 1; }; done
  $P -d $d -c "grant execute on function public.svc_enrich_ai_next(integer), public.svc_entry_matrix_next(integer), public.svc_ops_diagnosis_next(integer) to service_role"
  $P -d $d -f $FX/data.sql
done
echo "definitions this change edits or calls (loaded = live): ${#LIVE[@]}"
for s in "${EDITED[@]}"; do [ "$(hdr "$s" | cut -d' ' -f1)" = "${LIVE[$s]}" ] || { echo "header before md5 of $s is not the live md5"; exit 1; }; done

# 2 a drifted live body is refused, and nothing is left behind
$P -d ${DB}_drift -c "$(q ${DB}_drift "select replace(pg_get_functiondef('public.svc_entry_matrix_next(integer)'::regprocedure), 'limit greatest(1, least(coalesce(p_limit, 4), 20))', 'limit greatest(1, least(coalesce(p_limit, 5), 20))')")"
if OUT=$($P -d ${DB}_drift -1 -At -f $MIG 2>&1); then echo "the migration applied over a drifted definition"; exit 1; fi
grep -q "live public.svc_entry_matrix_next(integer) differs from the definition this change replaces" <<<"$OUT" || { echo "$OUT" | tail -3; exit 1; }
[ "$(q ${DB}_drift "select (to_regclass('pipeline.ai_model_catalogue') is null) and (to_regclass('pipeline.ai_service_routes') is null) and not exists (select 1 from pg_proc where proname = 'ai_route_v1')")" = t ] || { echo "a refused run left objects"; exit 1; }
echo "drifted live body: refused, nothing left"

# 3 the migration, then again
OTHERS="select md5(string_agg(p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)), '|' order by p.oid::regprocedure::text)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('security', 'public', 'auth') and p.prokind = 'f' and p.oid::regprocedure::text not in ('svc_enrich_ai_next(integer)', 'svc_entry_matrix_next(integer)', 'svc_ops_diagnosis_next(integer)', 'security.ai_spend_capture_v1()')
    and p.proname !~ '^(ai_(route|ledger|service|enrich|central|model|on_demand)_|admin_ai_(overview|model_set|route_set)_v1)'"
F0=$(q $DB "$OTHERS")
ACL0=$(q $DB "select string_agg(p.oid::regprocedure::text || coalesce(p.proacl::text, ''), '|' order by p.oid::regprocedure::text) from pg_proc p where p.proname in ('svc_enrich_ai_next', 'svc_entry_matrix_next', 'svc_ops_diagnosis_next', 'ai_spend_capture_v1')")
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(grep -c ': applied$' <<<"$OUT")" = 4 ] || { echo "the migration did not apply its four guarded edits"; echo "$OUT" | tail -5; exit 1; }
[ "$(q $DB "$OTHERS")" = "$F0" ] || { echo "the migration changed a function it does not declare"; exit 1; }
[ "$(q $DB "select string_agg(p.oid::regprocedure::text || coalesce(p.proacl::text, ''), '|' order by p.oid::regprocedure::text) from pg_proc p where p.proname in ('svc_enrich_ai_next', 'svc_entry_matrix_next', 'svc_ops_diagnosis_next', 'ai_spend_capture_v1')")" = "$ACL0" ] || { echo "the grants of an edited function changed"; exit 1; }
for s in "${EDITED[@]}"; do
  A=$(hdr "$s" | cut -d' ' -f2); [ -n "$A" ] && [ "$(md5of $DB "$s")" = "$A" ] || { echo "after md5 of $s: $(md5of $DB "$s") (header: $A)"; exit 1; }; echo "after: $s $A"
done
SNAP="select md5(string_agg(x, '|' order by x)) from (select 'm:' || m.code || m.status || m.family || m.model_identifier x from pipeline.ai_model_catalogue m
  union all select 'r:' || r.service_code || r.cascade::text || coalesce(r.daily_usd_cap::text, '') || coalesce(r.daily_calls_cap::text, '') || r.enabled || r.resolver from pipeline.ai_service_routes r
  union all select 's:' || s.toolset_key || s.key || s.value::text || coalesce(s.home, '') || coalesce(s.home_group, '') || coalesce(s.used_by, '') from pipeline.platform_toolset_settings s
  union all select 'l:' || l.id || coalesce(l.service_code, '') || coalesce(l.model, '') from pipeline.ai_spend_ledger l
  union all select 'e:' || e.id from pipeline.admin_control_events e union all select 'g:' || g.kind || g.name || coalesce(g.note, '') from pipeline.component_register g
  union all select 'c:' || c.model_identifier from pipeline.central_ai_settings c union all select 'h:' || h.chain::text from pipeline.scholarship_ai_extract_settings h
  union all select 't:' || t.tgname || t.tgrelid::regclass from pg_trigger t where not t.tgisinternal
  union all select 'f:' || p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public') and p.prokind = 'f') z"
S0=$(q $DB "$SNAP")
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(grep -c ': unchanged$' <<<"$OUT")" = 4 ] || { echo "the second run did not find its four edits in place"; exit 1; }
[ "$(q $DB "$SNAP")" = "$S0" ] || { echo "the second run changed something"; exit 1; }
echo "applied: only the four guarded edits changed existing functions; a second run changes nothing"

# 4 the keys the deployed worker reads keep their names and types (same rows, before and after; new keys only beside them)
shape() { $P -d "$1" -At -c "begin" -c "select set_config('fx.role', 'service_role', false)" -c "select s from public.fx_shape($2) s order by 1" -c "rollback" | grep '^\.\|^\[' || true; }
cmp_reader() {  # name, call, the new keys allowed (regex)
  local B A; B=$(shape ${DB}_before "$2"); A=$(shape $DB "$2")
  [ -n "$B" ] || { echo "$1 handed out nothing in the database as live"; exit 1; }
  [ "$(grep -Ev "$3" <<<"$A")" = "$B" ] || { echo "$1: a key the worker reads changed"; diff <(echo "$B") <(grep -Ev "$3" <<<"$A") || true; exit 1; }
  echo "$1: $(wc -l <<<"$B") keys unchanged in name and type; new beside them: $(grep -E "$3" <<<"$A" | grep -Ec '^(\[\])?\.[a-z_]+:|^\.entry\.models:|^\.items\[\]\.models:')"
}
cmp_reader "svc_enrich_ai_next" "public.svc_enrich_ai_next(10)" '^\.(models|routes|held)(:|\.|\[)|^\.entry\.models(:|\[)'
cmp_reader "svc_entry_matrix_next" "public.svc_entry_matrix_next(4)" '^\[\]\.models(:|\[)'
cmp_reader "svc_ops_diagnosis_next" "public.svc_ops_diagnosis_next(1)" '^\.items\[\]\.models(:|\[)'
[ "$(q ${DB}_before "begin; select public.svc_enrich_ai_next(10)#>>'{entry,model}'; rollback" | head -1)" = "openai/gpt-4.1-mini" ] || { echo "the database as live does not hand out GPT-4.1 mini for entry requirements"; exit 1; }
for c in "public.svc_enrich_ai_next(10)" "public.svc_entry_matrix_next(4)" "public.svc_ops_diagnosis_next(1)"; do
  if $P -d $DB -At -c "begin" -c "select ($c)::text" -c "rollback" | grep -q 'openai/\|anthropic/'; then echo "$c still hands out an OpenAI or Anthropic model"; exit 1; fi
done
echo "after: no reader hands out an OpenAI or Anthropic model (as live: entry requirements on openai/gpt-4.1-mini)"

# 5 behaviour
OUT=$($P -d $DB -f $FX/fixtures.sql 2>&1) || { echo "$OUT" | tail -6; exit 1; }
sed -n "s/^.*NOTICE:  //p" <<<"$OUT"
[ "$(grep -c "NOTICE:  ok " <<<"$OUT")" = 7 ] || { echo "not every fixture block passed"; exit 1; }
echo "fixtures: 7 of 7"
