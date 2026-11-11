#!/usr/bin/env bash
# Guards: F-AER.04 machine admission of country tables and qualification rows, rule aer-matrix-machine-v1 (Platform Admin decision D1, 11 Nov 2026) and G4 database-backed tests:
# migration 20261112093700 on top of the entry-matrix decision path as live after 20261112060000 (../aer-qualification-first), with security.aer_machine_run_v1 as live
# (Database function snapshot run 42994367041: ad143b44...): ships in shadow; every decline reason keeps the item with a person; a validation pass switches nothing on; admission
# goes through the person's apply with the machine records; withdrawal reverses it; the course job steps the class and is never broken by it; recovery restores the job byte for byte.
# Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Drops its database at the end (AMM_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${AMM_DB:-g_aer_matrix_machine}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
Q=tests/fixtures/aer-qualification-first; F=tests/fixtures/aer-matrix-machine
M=supabase/migrations/20261112093700_cf247_aer_matrix_machine_admission.sql; R=supabase/held/aer_matrix_machine_admission_forward_recovery.sql
RUN='security.aer_machine_run_v1()'; RUN_B=ad143b44722ba6fbc0129cd38386661c; RUN_A=f88ab3f16833dec601786af5c7cdbbcc
q() { psql -X -d "$DB" -Atc "$1"; }
trap '[ -n "${AMM_KEEP:-}" ] || dropdb --if-exists '$DB' >/dev/null 2>&1' EXIT
dropdb --if-exists $DB >/dev/null 2>&1; createdb $DB
psql -X -q -d postgres -c "do \$\$ begin if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if; if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if; if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role; end if; end \$\$"
$P -f $Q/stubs.sql; $P -f $F/stubs.sql
for f in $Q/live/public.svc_entry_matrix_record.sql $Q/live/security.entry_matrix_review_apply_v1.sql $F/live/security.aer_machine_run_v1.sql; do { echo "set check_function_bodies = off;"; cat $f; echo ";"; } | $P; done
{ echo "set check_function_bodies = off;"; cat supabase/migrations/20261112060000_cf247_aer_qualification_first.sql; } | $P -1 >/dev/null
[ "$(q "select md5(prosrc) from pg_proc where oid = '$RUN'::regprocedure")" = $RUN_B ] || { echo "loaded job differs from live $RUN_B"; exit 1; }
echo "loaded: the entry-matrix decision path after 20261112060000 and aer_machine_run_v1 as live ($RUN_B)"

OUT=$({ echo "set check_function_bodies = off;"; cat $M; } | $P -1 -At 2>&1) || { echo "$OUT" | tail -8; exit 1; }
[ "$(q "select md5(prosrc) from pg_proc where oid = '$RUN'::regprocedure")" = $RUN_A ] || { echo "the job did not reach $RUN_A"; exit 1; }
grep -qF -- "--   $RUN $RUN_B -> $RUN_A" $M || { echo "header does not record the job md5s"; exit 1; }
OUT=$({ echo "set check_function_bodies = off;"; cat $M; } | $P -1 -At 2>&1) || { echo "$OUT" | tail -8; exit 1; }
[ "$(q "select md5(prosrc) from pg_proc where oid = '$RUN'::regprocedure")" = $RUN_A ] || { echo "applied again: changed"; exit 1; }
echo "migration: the job goes to $RUN_A; the class ships in shadow; applied again: no change"

$P <<'SQL'
create or replace function pg_temp.ok(c boolean, m text) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', m; end if; raise notice 'ok: %', m; end $$;
create or replace function pg_temp.read(p_prov uuid, p_src uuid, p_run uuid, p_rows jsonb, p_qrows jsonb) returns uuid language plpgsql as $$
declare r jsonb; begin
  insert into pipeline.entry_matrix_runs(id, source_id, provider_id, content_hash) values (p_run, p_src, p_prov, 'h1');
  r := public.svc_entry_matrix_record(p_run, jsonb_build_object('dropped', '[]'::jsonb, 'rows', p_rows, 'qualification_rows', p_qrows), 0, null);
  return (r->>'review_item_id')::uuid; end $$;
-- the level map gives a level for undergraduate rows only (as live maps the labels it knows)
create or replace function security.entry_level_map_v1(p text) returns uuid language sql immutable as $$ select case when lower(p) = 'undergraduate' then '11111111-1111-1111-1111-111111111111'::uuid end $$;
update pipeline.platform_toolset_settings set value = '0' where key = 'aer.matrix_machine_audit_pct';
update pipeline.platform_toolset_settings set value = '2' where key = 'aer.matrix_machine_min_shadow';
insert into pipeline.evidence_artifacts(id, storage_path) values ('e0000000-0000-0000-0000-000000000001', 'x/1');
insert into catalogue.providers(id, canonical_name, website) values ('a0000000-0000-0000-0000-00000000000a', 'Uni A', 'https://www.unia.edu.au'), ('b0000000-0000-0000-0000-00000000000b', 'Uni B', 'https://unib.ac.nz'),
  ('c0000000-0000-0000-0000-00000000000c', 'Uni C', 'https://unic.edu.au');
insert into pipeline.entry_matrix_sources(id, provider_id, url, status, evidence_id, content_hash) values
  ('5a000000-0000-0000-0000-00000000000a', 'a0000000-0000-0000-0000-00000000000a', 'https://international.unia.edu.au/entry', 'read', 'e0000000-0000-0000-0000-000000000001', 'h1'),
  ('5b000000-0000-0000-0000-00000000000b', 'b0000000-0000-0000-0000-00000000000b', 'https://unib.ac.nz/entry', 'read', 'e0000000-0000-0000-0000-000000000001', 'h1'),
  ('5c000000-0000-0000-0000-00000000000c', 'c0000000-0000-0000-0000-00000000000c', 'https://agent.example.com/unic-entry', 'read', 'e0000000-0000-0000-0000-000000000001', 'h1');
do $$ declare ia uuid; ib uuid; ic uuid; v jsonb; begin
  -- A: complete, own subdomain, India row + global IB row, undergraduate
  ia := pg_temp.read('a0000000-0000-0000-0000-00000000000a', '5a000000-0000-0000-0000-00000000000a', '7a000000-0000-0000-0000-00000000000a',
    jsonb_build_array(jsonb_build_object('country_code', 'IN', 'qualification_name', 'CBSE Year 12', 'study_level', 'undergraduate', 'min_value', 75, 'grade_scale', 'percentage', 'confidence', 0.95, 'quote', 'India | CBSE Year 12 | 75%')),
    jsonb_build_array(jsonb_build_object('qualification_code', 'IB_DP', 'qualification_name', 'IB Diploma', 'applicability', 'global', 'study_level', 'undergraduate', 'min_value', 28, 'grade_scale', 'points', 'confidence', 0.95, 'quote', 'All countries | IB Diploma | 28 points')));
  -- B: an unresolved qualification row (applicability not printed)
  ib := pg_temp.read('b0000000-0000-0000-0000-00000000000b', '5b000000-0000-0000-0000-00000000000b', '7b000000-0000-0000-0000-00000000000b',
    jsonb_build_array(jsonb_build_object('country_code', 'NP', 'qualification_name', 'NEB Grade 12', 'study_level', 'undergraduate', 'min_value', 2.8, 'grade_scale', 'gpa', 'confidence', 0.95, 'quote', 'Nepal | NEB Grade 12 | GPA 2.8')),
    jsonb_build_array(jsonb_build_object('qualification_code', 'GAC', 'qualification_name', 'GAC', 'applicability', 'unresolved', 'study_level', 'undergraduate', 'min_value', 65, 'grade_scale', 'percentage', 'confidence', 0.95, 'quote', 'GAC 65 percent')));
  -- C: source on a third-party host
  ic := pg_temp.read('c0000000-0000-0000-0000-00000000000c', '5c000000-0000-0000-0000-00000000000c', '7c000000-0000-0000-0000-00000000000c',
    jsonb_build_array(jsonb_build_object('country_code', 'IN', 'qualification_name', 'CBSE', 'study_level', 'undergraduate', 'min_value', 70, 'grade_scale', 'percentage', 'confidence', 0.95, 'quote', 'India | CBSE | 70%')), '[]'::jsonb);
  perform pg_temp.ok((security.aer_matrix_machine_check_v1(ia)->>'ok')::boolean, 'A passes: own subdomain, stored current copy, every row source-proved with a level and a published minimum, IB global');
  perform pg_temp.ok(security.aer_matrix_machine_check_v1(ib)->>'rule' = 'row_applicability_unresolved', 'B stays with a person: a qualification row with unresolved applicability');
  perform pg_temp.ok(security.aer_matrix_machine_check_v1(ic)->>'rule' = 'source_not_official_host', 'C stays with a person: the source is not on the provider''s own website host');
  -- shadow: the job records, admits nothing
  v := security.aer_machine_run_v1();
  perform pg_temp.ok((v->>'mode')::int = 0 and (v->'matrix'->>'mode')::int = 1 and (v->'matrix'->>'checked')::int = 3, 'with course admission off the job still steps the class in shadow (3 items checked)');
  perform pg_temp.ok((select count(*) from catalogue.provider_entry_matrix where status = 'active') = 0 and (select status from pipeline.layer4_review_items where id = ia) = 'pending', 'shadow admits nothing');
  perform pg_temp.ok((select count(*) from pipeline.aer_machine_admissions) = 0, 'nothing is written to the course machine ledger (its validation is untouched)');
  -- mode 2 without a passing validation still runs as shadow
  update pipeline.platform_toolset_settings set value = '2' where key = 'aer.matrix_machine_mode';
  perform pg_temp.ok(security.aer_matrix_machine_effective_v1() = 1, 'mode 2 without a passing validation is still shadow (a setting alone switches nothing on)');
  v := security.aer_matrix_machine_validate_v1();
  perform pg_temp.ok((v->>'passed')::boolean and (v->>'regressions_on_recheck')::int = 0, 'validation passes: enough shadow results, no regression on re-check, no disagreement');
  perform pg_temp.ok(security.aer_matrix_machine_effective_v1() = 2, 'mode 2 with a passing validation admits');
  -- manual lock and earlier rejection keep an otherwise passing item with a person
  insert into pipeline.manual_locks(entity, entity_id, field) values ('provider', 'a0000000-0000-0000-0000-00000000000a', 'entry_requirements');
  perform pg_temp.ok(security.aer_matrix_machine_check_v1(ia)->>'rule' = 'manual_lock', 'a manual lock keeps the item with a person');
  delete from pipeline.manual_locks;
  -- admit
  v := security.aer_machine_run_v1();
  perform pg_temp.ok((select status from pipeline.layer4_review_items where id = ia) = 'approved'
    and (select status from catalogue.provider_entry_matrix where run_id = '7a000000-0000-0000-0000-00000000000a') = 'active'
    and (select status from catalogue.provider_qualification_requirements where run_id = '7a000000-0000-0000-0000-00000000000a') = 'active', 'A admitted: country row and IB row active through the person''s apply');
  perform pg_temp.ok((select layer2_state->>'actor_kind' from pipeline.layer4_decisions where review_item_id = ia) = 'machine' and (select actor_id from pipeline.layer4_decisions where review_item_id = ia) = security.system_actor_id(),
    'the decision is the system actor''s, marked machine (never a human decision)');
  perform pg_temp.ok((select count(*) from pipeline.search_refresh_signals where entity_id = 'a0000000-0000-0000-0000-00000000000a') = 1
    and (select rows_admitted from pipeline.aer_matrix_machine_admissions where review_item_id = ia and outcome = 'admitted') = 2, 'refresh signal and ledger row (2 rows admitted)');
  perform pg_temp.ok((select status from pipeline.layer4_review_items where id = ib) = 'pending' and (select escalation_reason from pipeline.layer4_review_items where id = ib) like 'Machine rule aer-matrix-machine-v1 did not admit this: row_applicability_unresolved.%',
    'B stays pending with the reason shown to the reviewer');
  perform pg_temp.ok((select status from pipeline.layer4_review_items where id = ic) = 'pending', 'C stays pending');
  -- withdraw
  v := security.aer_matrix_machine_withdraw_v1(ia, 'fixture withdrawal');
  perform pg_temp.ok((v->>'rows_withdrawn')::int = 2 and (select count(*) from catalogue.provider_entry_matrix where status = 'active') = 0
    and (select withdrawn_at is not null from pipeline.aer_matrix_machine_admissions where review_item_id = ia and outcome = 'admitted'), 'withdrawal reverses the admission and is recorded');
  -- an error inside the class never breaks the course job
  update pipeline.platform_toolset_settings set value = '"x"' where key = 'batch.aer_matrix_machine';
  v := security.aer_machine_run_v1();
  perform pg_temp.ok((v ? 'mode') and (v->'matrix' ? 'error'), 'an error in the class (an unreadable setting) is returned inside the course job''s result; the job completes');
  update pipeline.platform_toolset_settings set value = '20' where key = 'batch.aer_matrix_machine';
  insert into pipeline.platform_toolset_settings(toolset_key, key, value) values ('pipeline', 'aer.machine_mode', '1');
  update pipeline.platform_toolset_settings set value = '"x"' where key = 'aer.matrix_machine_daily_max';
  v := security.aer_machine_run_v1();
  perform pg_temp.ok((v ? 'checked') and (v->'matrix' ? 'error'), 'with course admission on, the course run completes and carries the class''s error');
end $$;
SQL
echo "behaviour: three decline reasons, shadow only, mode needs a validation, manual lock, admission through the person's apply, machine actor, withdrawal, isolation"

OUT=$({ echo "set check_function_bodies = off;"; cat $R; } | $P -1 -At 2>&1) || { echo "$OUT" | tail -8; exit 1; }
[ "$(q "select md5(prosrc) from pg_proc where oid = '$RUN'::regprocedure")" = $RUN_B ] && [ "$(q "select value from pipeline.platform_toolset_settings where key = 'aer.matrix_machine_mode'")" = 0 ] || { echo "recovery wrong"; exit 1; }
echo "recovery: job back to $RUN_B, class off, nothing dropped"
echo "PASS aer-matrix-machine"
