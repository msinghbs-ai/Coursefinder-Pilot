// Guards: Platform Admin direction 4 Nov 2026 10:00 §6 (layer4-interventions and layer4-readiness report measurable output; a zero verifies only when
// justified; the classifier's duplicate_cases and report_errors are kept), §7 (no state means failed indefinitely without a recovery condition or
// authority blocker), §10 (governed severity change: original and new severity, evidence-based reason, authority, history; never close or recreate)
// and §11 (verified progress by pipeline: eligible, processed, technically recovered, review-ready, human-decided, admitted, published, blocked).
// The behaviour runs on isolated fixtures by tests/fixtures/verification-measures/run.sh (scratch PostgreSQL 16; the six edited definitions loaded as
// live and md5-checked; the migration applied, then applied again unchanged). This spec holds the contract.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261104520000_cf247_verification_measures.sql', 'utf8')
const FX = 'tests/fixtures/verification-measures'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')

const EDITS = {
  'security.integration_issue_upsert_v1(jsonb,text)': ['b0a1a64982680ae5d588c2d73b779e4e', 'f9d7bf1a6dbe94ba97c34f10817f56c1'],
  'security.scholarship_coverage_classify_v1(uuid[])': ['c072494c5e0082e2a8b58a06dfd94a00', '7cd322359de3c7f823df240452afc2a8'],
  'security.progress_measure_v1(text,timestamp with time zone)': ['36447d3fd694efceaab38339fcd5ff12', '40c0c972abc353be8f6eee35c79750e9'],
  'security.progress_zero_reason_v1(text,jsonb)': ['9554405ed2ef504b3dfceb29acec165d', '746d7baedb0a79dc0a6fbfead82f67c2'],
  'security.release_first_run_register_v1(text,jsonb,jsonb,timestamp with time zone,text)': ['22788bb62eb9fcccad30c414da3923c0', '1f0b3cf6d1d1eea550e83ff5b4e5e5fe'],
  'security.self_sustainability_v1(integer)': ['77c269232cdea05bafe2e46b51d5ac8f', 'a91e9c8151cca09763cf755ab1da1f56'],
}

test('six md5-guarded edits from the live definitions; ops_report_v1 and the readiness and intervention jobs are not edited', () => {
  for (const [sig, [b, a]] of Object.entries(EDITS)) {
    expect(m).toContain(`select pg_temp.edit_once('${sig}', '${b}', '${a}'`)
    expect(run).toContain(`["${sig}"]=${b}`)
    expect(m).toContain(`('${sig}', '${a}')`)
  }
  expect(m.match(/select pg_temp\.edit_once\(/g)).toHaveLength(6)
  expect(m).toContain("('security.ops_report_v1(integer)', '518b5bf873549931a15d4173fef793d5')")
  expect(m).not.toMatch(/edit_once\('security\.(layer4_readiness_tick_v1|layer4_interventions_tick_v1|layer4_intervention_)/)
  expect(run).toContain('the migration changed a function it does not declare')
})

test('§6: output contracts for the two jobs (and first-run-verify), judged by the existing first-run verification with justified zeros only', () => {
  expect(m).toContain("('layer4-interventions', 'l4_interventions', '{created,reused,resolved,returned_to_recovery,awaiting_human_input}', '{har.generate_aer_on,har.generate_sch_on}',")
  expect(m).toContain("('layer4-readiness', 'l4_readiness', '{checked,newly_classified,technical_blocked,judgement_ready,superseded}', '{layer4.readiness_on}',")
  expect(m).toContain("  when 'l4_interventions' then")
  expect(m).toContain("  when 'l4_readiness' then")
  expect(m).toContain("(select c.measure_key from pipeline.job_output_contracts c where c.jobname = j.name)")
  expect(m).toContain("select c.measure_key, array[c.jobname], c.switch_keys into t.key, t.producer_jobs, t.switch_keys from pipeline.job_output_contracts c where c.measure_key = p_key;")
  // the classifier's answer is kept by the function itself, isolated
  expect(m).toContain('insert into pipeline.scholarship_coverage_classify_runs(manual, providers, cases, work_reports, recoveries_succeeded, recoveries_failed, duplicate_cases, report_errors,')
  expect(m).toContain('  exception when others then null;\n  end;\n  return jsonb_build_object(\'ran\', true, \'providers\', v_n, \'cases\', v_items,')
})

test('§10: governed severity keeps the row, fingerprint and history, and a repeat observation does not undo it', () => {
  expect(m).toContain('create or replace function security.integration_issue_severity_v1(p_issue bigint, p_severity text, p_reason text, p_authority text, p_evidence jsonb)')
  expect(m).toContain("security.pipeline_num_v1('recovery.severity_reason_min_chars', 30)")
  expect(m).toContain("if r.status = 'closed' then raise exception")
  expect(m).toContain("$n$severity = case when v_sev < i.severity and i.severity_decided_at is null then v_sev else i.severity end,$n$]")
  const fn = m.slice(m.indexOf('create or replace function security.integration_issue_severity_v1'), m.indexOf("comment on function security.integration_issue_severity_v1"))
  expect(fn).not.toMatch(/insert into pipeline\.integration_issues\b|integration_issue_close_v1|status = 'closed',/)
})

test('§7 and §11: gaps with no recovery condition, and the table by pipeline with the eight columns and the scholarship scope', () => {
  for (const k of ['work_items_no_condition', 'work_items_blocked_no_next_no_escalation', 'issues_no_next_action', 'release_jobs_unowned', 'field_reads_failed_no_work_item'])
    expect(m).toContain(`'${k}', jsonb_build_object(`)
  for (const c of ['eligible', 'processed', 'technically_recovered', 'review_ready', 'human_decided', 'admitted', 'published', 'blocked'])
    expect(m.match(new RegExp(`\\n      '${c}', jsonb_build_object\\('value'`, 'g'))).toHaveLength(2)
  expect(m).toContain("where l.domain = 'scholarship' and l.disposition not in ('not_applicable', 'out_of_scope')")
  expect(m).toContain("providers_with_candidates (755 on 4 Nov) counts providers with at least one candidate page ever found")
  // records and reads only
  expect(m).not.toMatch(/update\s+pipeline\.platform_toolset_settings|cron\.(schedule|alter_job|unschedule)|^\s*(drop|delete|truncate)\b/im)
  expect(m).not.toMatch(/create\s+or\s+replace\s+function\s+(api\.|public\.website_|public\.zoho_)/i)
})

test('the fixture asserts every case', () => {
  for (const s of ['case 2: readiness with no pending item: a justified zero, verified', 'case 3: readiness verified on its output', 'case 4: interventions produced nothing with generation switched off',
    'case 5: interventions verified', 'case 6: the next check settles it', "case 7: the scheduled run''s answer is kept", 'case 7: a failed ledger write never fails the run',
    'case 8: lowered P1 -> P2', "case 8: the detector''s next P1 observation does not undo the governed decision", 'case 8: a closed issue is not changed',
    'case 9: a failed work item with no next time', 'case 10: scholarships and AER, each with the eight §11 columns', 'case 10: the scope is the coverage ledger']) expect(fixtures).toContain(s)
  expect(run).toContain("grep -c ': applied$')\" = 6")
  expect(run).toContain("grep -c ': already applied$')\" = 6")
})
