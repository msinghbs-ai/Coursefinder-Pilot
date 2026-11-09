#!/usr/bin/env bash
# Guards: Platform Admin operating model v1.5 (10 Nov 2026) and the AI instruction registry rule (mandate section 6, 20261104070000): a prompt edited in code is registered as a new version; migration 20261110125000 registers the provider-description prompt of worker v0.60.0 as provider-description-v2.1 (the earlier row becomes previous and is never rewritten), guarded by the registered md5, idempotent, with a pinned model, and the forward recovery in supabase/held puts the earlier row back as current.
# Needs a scratch PostgreSQL (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds the database with the ops-ai-eval harness (AIEVAL_KEEP=1), then applies the migration twice, checks the registry, the refusals and the recovery. Drops the database at the end (PDPB_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${PDPB_DB:-g_pdesc_promptbase}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
MIG=supabase/migrations/20261110125000_cf247_pdesc_prompt_baseline_v2_1.sql
REC=supabase/held/pdesc_prompt_baseline_forward_recovery.sql
q() { psql -X -d "$DB" -Atc "$1"; }
[ -n "${PDPB_KEEP:-}" ] || trap "dropdb --if-exists $DB >/dev/null 2>&1; dropdb --if-exists ${DB}_x >/dev/null 2>&1" EXIT
BASE=$(AIEVAL_KEEP=1 AIEVAL_DB=$DB bash tests/fixtures/ops-ai-eval/run.sh 2>&1) || { echo "$BASE" | tail -10; echo "the base harness failed"; exit 1; }
echo "base: ops-ai-eval harness built the database (20261104070000 applied; the registry holds provider-description-v2, f539da5e...)"
rows() { q "select version || '|' || status || '|' || body_md5 || '|' || model_identifier || '|' || coalesce(parent_id::text, '-') from pipeline.ai_instruction_versions where code = 'provider-description' order by id"; }
[ "$(rows | head -1)" = 'provider-description-v2|current|f539da5e1d69e8fde6a113459ceede75|openai/gpt-4.1-mini|-' ] || { echo "the loaded registry differs from live"; rows; exit 1; }
OTHER="select md5(string_agg(v.code || v.version || v.status || v.body_md5 || coalesce(v.parent_id::text, ''), '|' order by v.id)) from pipeline.ai_instruction_versions v where v.code <> 'provider-description'"
O0=$(q "$OTHER"); N0=$(q "select count(*) from pipeline.ai_instruction_versions"); F0=$(q "select md5(string_agg(p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)), '|' order by p.oid::regprocedure::text)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security','public') and p.prokind = 'f'")
S0=$(q "select md5(string_agg(key || value::text, '|' order by key)) from pipeline.platform_toolset_settings")
# a baseline that is not the one the migration registers over is refused, and nothing changes
dropdb --if-exists ${DB}_x >/dev/null 2>&1; createdb -T $DB ${DB}_x
psql -X -q -d ${DB}_x -c "set cf247.release = '20261104070000'; update pipeline.ai_instruction_versions set status = 'previous' where code = 'provider-description'; insert into pipeline.ai_instruction_versions(family, code, kind, version, home, body_md5, model_identifier, status) values ('course_description', 'provider-description', 'prompt', 'provider-description-other', 'x', '00000000000000000000000000000000', 'openai/gpt-4.1-mini', 'current')" >/dev/null
OUT=$(psql -X -d ${DB}_x -v ON_ERROR_STOP=1 -q -At -1 -f $MIG 2>&1) && { echo "the migration applied over another baseline"; exit 1; }
grep -qF "the current provider-description baseline is not the one this change registers over" <<<"$OUT" || { echo "unexpected refusal: $OUT" | tail -3; exit 1; }
[ "$(psql -X -d ${DB}_x -Atc "select count(*) from pipeline.ai_instruction_versions where version = 'provider-description-v2.1'")" = 0 ] || { echo "the refused migration registered a row"; exit 1; }
dropdb --if-exists ${DB}_x >/dev/null 2>&1
echo "refused: a registry whose current provider-description row is not the earlier baseline stops the migration (nothing registered)"
$P -1 -At -f $MIG >/dev/null || { echo "the migration failed"; exit 1; }
EXPECT=$'provider-description-v2|previous|f539da5e1d69e8fde6a113459ceede75|openai/gpt-4.1-mini|-\nprovider-description-v2.1|current|ff2dd332522a1cc257d0895e8342ac84|openai/gpt-4.1-mini|'
PARENT=$(q "select id from pipeline.ai_instruction_versions where version = 'provider-description-v2'")
[ "$(rows)" = "${EXPECT}${PARENT}" ] || { echo "the registry after the migration differs from the expected:"; rows; exit 1; }
[ "$(q "$OTHER")" = "$O0" ] && [ "$(q "select count(*) from pipeline.ai_instruction_versions")" = "$((N0 + 1))" ] || { echo "the migration changed another registry row"; exit 1; }
[ "$(q "select md5(string_agg(p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)), '|' order by p.oid::regprocedure::text)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security','public') and p.prokind = 'f'")" = "$F0" ] || { echo "the migration changed a function"; exit 1; }
[ "$(q "select md5(string_agg(key || value::text, '|' order by key)) from pipeline.platform_toolset_settings")" = "$S0" ] || { echo "the migration changed a setting"; exit 1; }
[ "$(q "select count(*) from pipeline.ai_instruction_versions where code = 'provider-description' and status = 'current'")" = 1 ] || { echo "not exactly one current row"; exit 1; }
$P -1 -At -f $MIG >/dev/null || { echo "the second run failed"; exit 1; }
[ "$(rows)" = "${EXPECT}${PARENT}" ] || { echo "the second run changed the registry"; exit 1; }
echo "migration: provider-description-v2 becomes previous (kept), provider-description-v2.1 is current with body_md5 ff2dd332522a1cc257d0895e8342ac84, the same pinned model and the earlier row as parent; no other row, function or setting changed; applied again: no change"
# the earlier row cannot be rewritten (the registry refuses), so the recovery changes statuses only
$P -1 -At -f $REC >/dev/null || { echo "the forward recovery failed"; exit 1; }
[ "$(rows | cut -d'|' -f1-3 | tr '\n' ' ')" = 'provider-description-v2|current|f539da5e1d69e8fde6a113459ceede75 provider-description-v2.1|rolled_back|ff2dd332522a1cc257d0895e8342ac84 ' ] || { echo "the recovery did not put the earlier row back"; rows; exit 1; }
$P -1 -At -f $REC >/dev/null || { echo "the second recovery run failed"; exit 1; }
$P -1 -At -f $MIG >/dev/null || { echo "the migration failed after the recovery"; exit 1; }
[ "$(rows | cut -d'|' -f1-2 | tr '\n' ' ')" = 'provider-description-v2|current provider-description-v2.1|rolled_back ' ] || { echo "the migration changed the rolled-back state"; exit 1; }
echo "recovery: the earlier row is current again, v2.1 is rolled_back (no row deleted or rewritten); running it again changes nothing"
echo "pdesc-prompt-baseline: done"
