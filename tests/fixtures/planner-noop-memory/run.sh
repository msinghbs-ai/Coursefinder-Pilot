#!/usr/bin/env bash
# Guards: IQ-00355 planner head-of-queue starvation (CF-247 F-OPS): migration 20261110240000 edits only security.enrich_plan_auto_v1 (checked by the md5 of its body, refused with nothing applied when the live body differs) and adds only the setting plans.noop_wait_hours;
# a never-planned or due university whose plan has no step is remembered (enrich_plan_noop) for every candidate and left out of the candidate list for plans.noop_wait_hours, so a plannable university behind it is reached; an early re-plan keeps its fingerprint rule; the forward recovery returns the body byte for byte.
# Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Loads the LIVE body of security.enrich_plan_auto_v1 (live/, md5 checked) over stubs of the tables and of the three helpers that decide what is in a plan (enrich_plan_v1, enrich_plan_inputs_v1,
# enrich_plan_priority_v1: stubs.sql says so; the planner's own selection, order, window and recording are the real text). PNM_KEEP=1 keeps the databases.
set -euo pipefail
cd "$(dirname "$0")/../../.."
export LC_ALL=C # fixed: one byte order whatever the runner's locale
DB=${PNM_DB:-g_planner_noop}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
F=tests/fixtures/planner-noop-memory
M=supabase/migrations/20261110240000_cf247_planner_noop_memory.sql
R=supabase/held/planner_noop_memory_forward_recovery.sql
FN='security.enrich_plan_auto_v1()'; BEFORE=5a3874e777ae649916d61575e2692609; AFTER=f0c95d0bbef3ccac550585185c9784c9
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
q() { psql -X -d "$DB" -Atc "$1"; }
fnmd5() { q "select md5(prosrc) from pg_proc where oid = '$FN'::regprocedure"; }
dropdb --if-exists $DB >/dev/null 2>&1; dropdb --if-exists ${DB}_x >/dev/null 2>&1
[ -n "${PNM_KEEP:-}" ] || trap "dropdb --if-exists $DB >/dev/null 2>&1; dropdb --if-exists ${DB}_x >/dev/null 2>&1" EXIT
createdb $DB
$P -f $F/stubs.sql; $P -f $F/live/security.enrich_plan_auto_v1.sql
[ "$(fnmd5)" = $BEFORE ] || { echo "the loaded planner differs from live ($(fnmd5))"; exit 1; }
echo "loaded: security.enrich_plan_auto_v1 = live (body md5 $BEFORE, read 10 Nov 2026) over stubs (tables as live; enrich_plan_v1, enrich_plan_inputs_v1, enrich_plan_priority_v1 are stubs)"
DEF0=$(q "select pg_get_functiondef('$FN'::regprocedure)")

# the fixture: 6 universities with no step and the most missing values (they fill the 6-place window, plans.auto_per_run 2 x 3), then 2 that can be planned, then an early re-plan with no step
$P <<'SQL'
insert into catalogue.providers(name) select n from unnest(array['Z1','Z2','Z3','Z4','Z5','Z6','P1','P2','R']) n;
insert into security.fx_priority select id, case name when 'Z1' then 100 when 'Z2' then 99 when 'Z3' then 98 when 'Z4' then 97 when 'Z5' then 96 when 'Z6' then 95 when 'P1' then 10 when 'P2' then 9 else 20 end, 'AU', null from catalogue.providers;
insert into security.fx_plan_steps select id, '[{"step":"fields","person":false}]'::jsonb from catalogue.providers where name in ('P1', 'P2');
-- R: planned 3 days ago when it missed 5 values, now misses 20 (an early re-plan on new gaps), and the plan has no step
insert into pipeline.enrich_plan_runs(provider_id, mode, state, steps, estimate, created_at) select id, 'auto', 'done', '[]'::jsonb, '{"missing":5,"fingerprint":"old"}'::jsonb, now() - interval '3 days' from catalogue.providers where name = 'R';
SQL
call() { q "select 'started=' || (r->>'started') || ' considered=' || (r->>'considered') || ' nothing_to_do=' || (r->>'nothing_to_do') || ' replanned=' || (r->>'replanned') from (select security.enrich_plan_auto_v1() r) t"; }
expect() { [ "$2" = "$3" ] || { echo "$1: got '$2', expected '$3'"; exit 1; }; }
pid() { q "select id from catalogue.providers where name = '$1'"; }
runs() { q "select count(*) from pipeline.enrich_plan_runs r join catalogue.providers p on p.id = r.provider_id where p.name = '$1' and r.created_at > now() - interval '1 hour'"; }
noopn() { q "select count(*) from pipeline.enrich_plan_noop n join catalogue.providers p on p.id = n.provider_id where p.name = any (string_to_array('$1', ','))"; }

# the starvation, on the live text before the change
expect "before, cycle 1" "$(call)" "started=0 considered=6 nothing_to_do=0 replanned=0"
expect "before, cycle 2" "$(call)" "started=0 considered=6 nothing_to_do=0 replanned=0"
[ "$(runs P1)" = 0 ] && [ "$(noopn Z1,Z2,Z3,Z4,Z5,Z6)" = 0 ] || { echo "before: the live text planned P1 or remembered a Z"; exit 1; }
echo "before: the same 6 universities with no step are looked at every cycle (considered 6, nothing remembered), and the plannable P1 and P2 behind them are never reached"

snap() { q "select p.oid::regprocedure::text || ' ' || md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security','pipeline','public') order by 1" > "$1.fn"
         q "select key || '=' || value::text from pipeline.platform_toolset_settings order by 1" > "$1.set"; q "select count(*) from pipeline.enrich_plan_runs" > "$1.runs"; q "select count(*) from pipeline.enrich_plan_noop" > "$1.noop"; }
W=$(mktemp -d); trap "rm -rf $W; "'dropdb --if-exists '$DB' >/dev/null 2>&1; dropdb --if-exists '${DB}_x' >/dev/null 2>&1' EXIT
[ -z "${PNM_KEEP:-}" ] || trap "rm -rf $W" EXIT

# a live body that differs: the migration refuses, and nothing is applied (the setting is not added either)
createdb -T $DB ${DB}_x
psql -X -q -d ${DB}_x -v ON_ERROR_STOP=1 -c "do \$\$ begin execute regexp_replace(pg_get_functiondef('$FN'::regprocedure), 'begin', 'begin /* changed by hand */'); end \$\$"
OUT=$(psql -X -d ${DB}_x -q -At -v ON_ERROR_STOP=1 -1 -f $M 2>&1) && { echo "the migration applied over a changed body"; exit 1; }
grep -qF "differs from the definition this change replaces" <<<"$OUT" || { echo "the refusal is not the expected one: $OUT" | tail -3; exit 1; }
[ "$(psql -X -d ${DB}_x -Atc "select count(*) from pipeline.platform_toolset_settings where key = 'plans.noop_wait_hours'")" = 0 ] || { echo "the refused migration left the setting"; exit 1; }
dropdb ${DB}_x
echo "refused: a hand-changed live planner is refused by the migration (transaction rolled back: no setting added, body untouched)"

# the migration
snap "$W/0"
OUT=$($P -1 -At -f $M 2>&1) || { echo "$OUT" | tail -8; exit 1; }
[ "$(fnmd5)" = $AFTER ] || { echo "the migration did not leave the recorded md5 ($(fnmd5))"; exit 1; }
grep -qF -- "--   $FN   $BEFORE -> $AFTER" $M || { echo "the migration header does not record the md5s"; exit 1; }
snap "$W/1"
[ "$(comm -23 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//')" = "$FN" ] && [ "$(comm -13 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//')" = "$FN" ] || { echo "functions other than the planner changed"; exit 1; }
[ "$(diff "$W/0.set" "$W/1.set" | grep -c '^[<>]')" = 1 ] && grep -q '^> plans.noop_wait_hours=24$' <(diff "$W/0.set" "$W/1.set") || { echo "the migration changed settings other than adding plans.noop_wait_hours=24"; exit 1; }
cmp -s "$W/0.runs" "$W/1.runs" && cmp -s "$W/0.noop" "$W/1.noop" || { echo "the migration changed plans or memory rows"; exit 1; }
expect "setting" "$(q "select toolset_key||'|'||kind||'|'||min_value||'|'||max_value||'|'||unit||'|'||control_class||'|'||(label <> '')||'|'||(used_by <> '')||'|'||(reason <> '') from pipeline.platform_toolset_settings where key = 'plans.noop_wait_hours'")" "pipeline|number|1|168|hours|human|true|true|true"
OUT=$($P -1 -At -f $M 2>&1); grep -qF "already applied" <<<"$OUT" || { echo "the second run was not a no-op"; exit 1; }
snap "$W/2"; for f in fn set runs noop; do cmp -s "$W/1.$f" "$W/2.$f" || { echo "the second run changed $f"; exit 1; }; done
echo "migration: planner $BEFORE -> $AFTER; no other function, plan or memory row changed; one setting added (pipeline, number, 1 to 168, hours, human, label, used_by, reason); applied again: no change"

# the scenarios (plans.noop_wait_hours 24 as shipped)
expect "cycle 1" "$(call)" "started=0 considered=6 nothing_to_do=6 replanned=0"
expect "cycle 1 memory" "$(noopn Z1,Z2,Z3,Z4,Z5,Z6)" 6
echo "cycle 1: the 6 never-planned universities with no step are remembered (nothing_to_do 6)"
expect "cycle 2" "$(call)" "started=2 considered=2 nothing_to_do=0 replanned=0"
[ "$(runs P1)" = 1 ] && [ "$(runs P2)" = 1 ] || { echo "cycle 2: P1 and P2 were not planned"; exit 1; }
echo "cycle 2 (within the wait): the plannable P1 and P2, beyond the 6-place window before, are reached and planned (started 2, considered 2)"
expect "cycle 3" "$(call)" "started=0 considered=1 nothing_to_do=1 replanned=0"
expect "cycle 3 memory" "$(q "select n.fingerprint = md5(jsonb_build_object('missing', 20, 'evidence_at', null, 'central_at', null, 'retry', '[]'::jsonb)::text) from pipeline.enrich_plan_noop n where n.provider_id = '$(pid R)'")" t
expect "cycle 4" "$(call)" "started=0 considered=0 nothing_to_do=0 replanned=0"
q "update pipeline.enrich_plan_noop set at = now() - interval '48 hours' where provider_id = '$(pid R)'" >/dev/null
expect "cycle 4b" "$(call)" "started=0 considered=0 nothing_to_do=0 replanned=0"
echo "re-plan: R (planned 3 days ago, gaps grew, no step) is remembered with its inputs fingerprint and is not looked at again, even 48 hours later, until its inputs change (unchanged meaning)"
# after the wait, the memory ends: Z1 is 25 hours old, Z2 23 hours
Z1=$(pid Z1); Z2=$(pid Z2)
q "update pipeline.enrich_plan_noop set at = now() - interval '25 hours' where provider_id = '$Z1'; update pipeline.enrich_plan_noop set at = now() - interval '23 hours' where provider_id = '$Z2'" >/dev/null
expect "cycle 5" "$(call)" "started=0 considered=1 nothing_to_do=1 replanned=0"
[ "$(q "select at > now() - interval '1 hour' from pipeline.enrich_plan_noop where provider_id = '$Z1'")" = t ] && [ "$(q "select at < now() - interval '22 hours' from pipeline.enrich_plan_noop where provider_id = '$Z2'")" = t ] || { echo "cycle 5: Z1 was not refreshed or Z2 was touched"; exit 1; }
echo "cycle 5: after 25 hours Z1 is looked at again (and remembered again); Z2 at 23 hours is still left out"
q "update pipeline.platform_toolset_settings set value = '1'::jsonb where toolset_key = 'pipeline' and key = 'plans.noop_wait_hours'" >/dev/null
expect "cycle 6 (setting 1 hour)" "$(call)" "started=0 considered=1 nothing_to_do=1 replanned=0"
echo "cycle 6: with plans.noop_wait_hours set to 1 the wait follows the setting (Z2, 23 hours old, is looked at again; the others, minutes old, are not)"
# new evidence after the wait: Z3 now has a step
q "update pipeline.enrich_plan_noop set at = now() - interval '2 hours' where provider_id = '$(pid Z3)'; insert into security.fx_plan_steps values ('$(pid Z3)', '[{\"step\":\"pages\",\"person\":false}]')" >/dev/null
expect "cycle 7" "$(call)" "started=1 considered=1 nothing_to_do=0 replanned=0"
[ "$(runs Z3)" = 1 ] || { echo "cycle 7: Z3 was not planned"; exit 1; }
echo "cycle 7: a remembered university that gained a step is planned once the wait has passed (started 1)"
# a plan with only steps a person must do is remembered too
q "update pipeline.enrich_plan_noop set at = now() - interval '2 hours' where provider_id = '$(pid Z4)'; insert into security.fx_plan_steps values ('$(pid Z4)', '[{\"step\":\"x\",\"person\":true}]')" >/dev/null
expect "cycle 8" "$(call)" "started=0 considered=1 nothing_to_do=1 replanned=0"
expect "cycle 8 memory" "$(q "select at > now() - interval '1 hour' from pipeline.enrich_plan_noop where provider_id = '$(pid Z4)'")" t
echo "cycle 8: a plan whose only steps are for a person is remembered like an empty plan"
[ "$(q "select count(*) from pipeline.enrich_plan_runs where mode = 'auto' and state not in ('done', 'queued')")" = 0 ] || { echo "an unexpected run state"; exit 1; }

# the forward recovery
OUT=$(psql -X -d $DB -q -At -v ON_ERROR_STOP=1 -1 -f $R 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(fnmd5)" = $BEFORE ] && [ "$(q "select pg_get_functiondef('$FN'::regprocedure)")" = "$DEF0" ] || { echo "the recovery did not restore the planner byte for byte"; exit 1; }
[ "$(q "select count(*) from pipeline.platform_toolset_settings where key = 'plans.noop_wait_hours'")" = 1 ] || { echo "the recovery removed the setting"; exit 1; }
OUT=$(psql -X -d $DB -q -At -v ON_ERROR_STOP=1 -1 -f $R 2>&1); grep -qF "already the original" <<<"$OUT" || { echo "the second recovery was not a no-op"; exit 1; }
$P -1 -At -f $M >/dev/null; [ "$(fnmd5)" = $AFTER ] || { echo "the migration did not apply again after the recovery"; exit 1; }
createdb -T $DB ${DB}_x
psql -X -q -d ${DB}_x -v ON_ERROR_STOP=1 -c "do \$\$ begin execute regexp_replace(pg_get_functiondef('$FN'::regprocedure), 'begin', 'begin /* changed by hand */'); end \$\$"
OUT=$(psql -X -d ${DB}_x -q -At -v ON_ERROR_STOP=1 -1 -f $R 2>&1) && { echo "the recovery ran over a changed body"; exit 1; }
grep -qF "differs from both texts this recovery knows" <<<"$OUT" || { echo "the recovery refusal is not the expected one"; exit 1; }
echo "recovery: the forward recovery returns the planner to the live text byte for byte (pg_get_functiondef identical), keeps the setting, is repeatable, refuses a changed body, and the migration applies again after it"
echo "planner-noop-memory: done"
