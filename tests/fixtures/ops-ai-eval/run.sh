#!/usr/bin/env bash
# CF-247 P0 workstream E (AI evaluation and controlled self-improvement, migration 20261104070000) on isolated fixtures. Needs a scratch
# PostgreSQL (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database: stubs.sql (the live shapes read or
# written beside, read 3 Nov 2026 15:43-15:52 AEDT), workstream A's contract (stub-ops-contract.sql, from branch cf247-ops-a commit d8b11de1,
# checked byte for byte against A's migration when that branch is fetched), seed.sql (trusted and untrusted rows of every source); applies the
# migration once (the guard refuses it without A's contract first), checks it ships the spending and live-changing switches off, applies it
# again (nothing changes), then runs fixtures.sql: datasets, ground-truth refusals, pinned models, offline scoring on recorded answers, the
# rejected-proposal ledger, canary and rollback, the release path, the approval boundaries and the remedy. No AI call is made anywhere.
# Drops the database at the end (AIEVAL_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${AIEVAL_DB:-ops_ai_eval_fixtures}
P="psql -v ON_ERROR_STOP=1 -q -X"
MIG=supabase/migrations/20261104070000_cf247_ai_eval_self_improvement.sql
FX=tests/fixtures/ops-ai-eval
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
q() { $P -d $DB -Atc "$1"; }
if git cat-file -e origin/cf247-ops-a:supabase/migrations/20261104010000_cf247_ops_controller.sql 2>/dev/null; then
  diff <(git show origin/cf247-ops-a:supabase/migrations/20261104010000_cf247_ops_controller.sql | awk '/^-- >>> contract/{f=1} f{print} /^-- <<< contract/{f=0}') \
       <(sed -n '/^-- >>> contract/,$p' $FX/stub-ops-contract.sql) >/dev/null || { echo "stub-ops-contract.sql differs from workstream A's contract section"; exit 1; }
  echo "stub-ops-contract.sql = workstream A's contract section (origin/cf247-ops-a)"
fi
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null 2>&1
[ -n "${AIEVAL_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT
$P -d $DB -f $FX/stubs.sql
# without workstream A's contract the migration refuses to run
if $P -d $DB -1 -f $MIG >/dev/null 2>&1; then echo "the migration ran without workstream A's contract"; exit 1; fi
echo "refused without workstream A's contract"
$P -d $DB -f $FX/stub-ops-contract.sql
$P -d $DB -f $FX/seed.sql
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -8; exit 1; }
echo "$OUT" | show | cut -c1-160
for k in ai_eval.canary_on ai_eval.auto_accept_on ai_eval.offline_runs_on; do [ "$(q "select value #>> '{}' from pipeline.platform_toolset_settings where key = '$k'")" = 0 ] || { echo "$k must ship 0"; exit 1; }; done
[ "$(q "select value #>> '{}' from pipeline.platform_toolset_settings where key = 'ai_eval.refresh_on'")" = 1 ] || { echo "ai_eval.refresh_on ships 1 (records only)"; exit 1; }
echo "ships off: ai_eval.canary_on, ai_eval.auto_accept_on, ai_eval.offline_runs_on; ships on: ai_eval.refresh_on (records only)"
snap() { q "select md5(string_agg(x, '|' order by x)) from (
  select 's:' || s.key || s.value::text x from pipeline.platform_toolset_settings s union all select 'j:' || j.jobname || j.schedule || j.command from cron.job j
  union all select 'c:' || c.jobname || c.description from pipeline.automation_catalogue c union all select 'g:' || g.kind || g.name from pipeline.component_register g
  union all select 'f:' || f::text from pipeline.ai_eval_families f union all select 'm:' || m::text from pipeline.ai_eval_source_map m
  union all select 'b:' || b::text from pipeline.ai_approval_boundaries b union all select 'a:' || a::text from pipeline.ai_auto_tunable_settings a
  union all select 'v:' || v.code || v.version || v.status || v.body_md5 from pipeline.ai_instruction_versions v
  union all select 'p:' || p.code || p.status || p.fingerprint || p.acceptance_criteria::text from pipeline.ai_improvement_proposals p
  union all select 'e:' || count(*) from pipeline.ai_proposal_events union all select 'r:' || r::text from pipeline.ops_root_causes r
  union all select 'o:' || o.code || o.authority from pipeline.ops_remedies o union all select 't:' || t.tgname from pg_trigger t where not t.tgisinternal) z"; }
S1=$(snap)
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -8; exit 1; }
[ "$(snap)" = "$S1" ] || { echo "a second run changed settings, jobs, registers, versions or proposals"; exit 1; }
echo "applied twice: the second run changed nothing"
$P -d $DB -f $FX/fixtures.sql 2>&1 | show | cut -c1-220
echo "all AI evaluation fixtures passed"
