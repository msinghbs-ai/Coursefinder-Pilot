// Guards: Staging retention and operations telemetry (Platform Admin 17 Nov 2026 18:02 and 18:25): housekeeping-daily removes only applied staging rows past their keep period (90 days, per source if set), writes each removed row's hash to a 7-year ledger first, never touches editions or evidence, and is a dry run until retention.staging_prune_on is 1; the unreferenced-evidence purge keeps evidence 7 years; the telemetry views are read only and closed to anon and authenticated; migrations are dry-run on the live project by GitHub Actions inside a transaction that is always rolled back
// CF-247 S583. Migration 20261117200000_cf247_staging_retention_and_ops_telemetry, workflow db-migration-dry-run.yml. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations-archive/20261117200000_cf247_staging_retention_and_ops_telemetry.sql', 'utf8')
const code = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const between = (a, b) => code.slice(code.indexOf(a), code.indexOf(b, code.indexOf(a)))
const ret = between('create or replace function security.staging_retention_v1', 'revoke all on function security.staging_retention_v1')
const hk = between('create or replace function security.housekeeping_daily_v1', 'revoke execute on function security.housekeeping_daily_v1')
const W = fs.readFileSync('.github/workflows/db-migration-dry-run.yml', 'utf8')
const S = fs.readFileSync('scripts/ci/dry-run-migration.sh', 'utf8')

test('retention periods, the switch and the row limit are settings; pruning starts as a dry run', () => {
  for (const [k, v] of [['retention.staging_prune_on', 0], ['retention.staging_keep_days', 90], ['retention.boost_staging_keep_days', 90],
    ['retention.raw_hash_keep_years', 7], ['batch.staging_prune_rows', 1000], ['telemetry.window_days', 30], ['telemetry.l4_aged_days', 7]]) {
    expect(code, k).toMatch(new RegExp(`\\('pipeline', '${k.replace(/\./g, '\\.')}',(?:(?!\\('pipeline',)[\\s\\S]){0,700}?'number', to_jsonb\\(${v}\\)`))
  }
  expect(hk).toContain("v_staging := security.staging_retention_v1(security.pipeline_num_v1('retention.staging_prune_on', 0) < 1);")
  // the live housekeeping body is kept as it was and checked before it is replaced
  expect(code).toContain("md5(pg_get_functiondef('security.housekeeping_daily_v1()'::regprocedure)) <> 'd2761ea4beb46baed71ee88591d89c60'")
  expect(hk).toContain("delete from pipeline.pilot_edge_nonces where id in (")
  expect(hk).toContain("delete from cron.job_run_details where runid in (")
  // the class catalogue can stop removal altogether
  expect(ret).toContain("where class_key = 'applied_source_staging'")
  expect(ret).toContain('if not coalesce(v_allowed, false) then p_dry := true; end if;')
})

test('only applied staging rows go, each hash is kept 7 years first, and editions and evidence are never removed', () => {
  expect(ret).toContain("where s.status = 'processed' and s.processed_at is not null")
  expect(ret).toContain("coalesce(p.staging_keep_days, v_keep)")
  expect(ret).toContain("q.status not in ('completed', 'failed', 'no_change', 'cancelled', 'expired')")
  expect(ret).toContain("b.promotion_state in ('shadow', 'proposed', 'refused')") // admitted Boost rows stay
  expect(ret).not.toContain("'admitted') and b.promoted_at")
  expect(ret.indexOf("'source_record_staging', s.id")).toBeLessThan(ret.indexOf('delete from pipeline.source_record_staging'))
  expect(ret.indexOf("'boost_inbound_staging', b.id")).toBeLessThan(ret.indexOf('delete from pipeline.boost_inbound_staging'))
  expect(ret).toContain("p_now + make_interval(years => v_years)")
  for (const t of ['destination.editions', 'pipeline.layer1_dataset_editions', 'pipeline.evidence_artifacts']) expect(code, t).not.toMatch(new RegExp(`delete from ${t.replace('.', '\\.')}`))
  expect(code).toContain("('published_editions', 'destination.editions and pipeline.layer1_dataset_editions', true, false, null")
  expect(code).toContain("comment on table pipeline.staging_hash_ledger is '")
  expect(code).toContain("comment on table pipeline.source_retention_policies is '")
})

test('the unreferenced-evidence purge keeps evidence for the 7-year period', () => {
  const cand = between('create or replace function security.retention_evidence_candidates_v1', 'update pipeline.platform_toolset_settings')
  expect(code).toContain("md5(pg_get_functiondef('security.retention_evidence_candidates_v1()'::regprocedure)) <> '5b3912e24120bef44576688ecc63e914'")
  expect(cand).toContain("now() - make_interval(years => security.pipeline_num_v1('retention.raw_hash_keep_years', 7)::int))")
  expect(cand).toContain("not exists (select 1 from pipeline.evidence_audit_refs r where r.evidence_id = e.id)")
})

test('telemetry views are read only, read their look-back from settings and are closed to anon and authenticated', () => {
  for (const v of ['pipeline.ops_l1_apply_latency_v', 'pipeline.ops_l4_escalation_by_source_v', 'pipeline.ops_boost_vs_pr3_throughput_v']) {
    expect(code, v).toContain(`create or replace view ${v} as`)
    expect(code, v).toContain(`comment on view ${v} is '`)
  }
  expect(code).toContain('revoke all on pipeline.ops_l1_apply_latency_v, pipeline.ops_l4_escalation_by_source_v, pipeline.ops_boost_vs_pr3_throughput_v from public, anon, authenticated;')
  expect(code.match(/security\.pipeline_num_v1\('telemetry\.window_days', 30\)/g).length).toBeGreaterThanOrEqual(4)
  const ops = between('create or replace function public.admin_ops_telemetry', 'create or replace function public.admin_source_retention_set')
  expect(ops).toContain("coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Curator role or above required'")
  const set = between('create or replace function public.admin_source_retention_set', 'create or replace function public.admin_staging_retention_preview')
  expect(set).toContain("coalesce(security.current_role_rank(), 0) < 6")
  expect(set).toContain("if v_reason is null then raise exception 'a reason is required'")
  expect(code).toContain('from public, anon;')
})

test('migrations are dry-run live by GitHub Actions in a transaction that is always rolled back', () => {
  expect(W).toContain("contains(github.event.pull_request.labels.*.name, 'live-dry-run')")
  expect(W).toContain('if [ "$CONFIRM" != "$REF" ]; then echo "::error::Refused: the typed project ref does not match the Pilot"; exit 1; fi')
  expect(W).toContain('REF: ${{ vars.SUPABASE_PROJECT_REF }}')
  expect(S).toContain("printf \"begin;\\nset local statement_timeout = '%s';\\n\"")
  expect(S).toContain("raise exception 'CF-DRYRUN-ROLLED-BACK %%'")
  expect(S).toContain("if grep -q 'CF-DRYRUN-ROLLED-BACK' r.json; then")
  expect(S).toContain('Refused: $FILE ends or opens its own transaction')
  expect(S).not.toContain('schema_migrations') // a dry run never writes a history row
})
