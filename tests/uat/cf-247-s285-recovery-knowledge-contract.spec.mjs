// Guards: Platform Admin direction 4 Nov 2026 18:08 §2 (a recovery knowledge base on the existing controller, remedy catalogue, fingerprints and work
// continuity: no competing controller), §3 (recurrence reuses only verified, authorised remedies; outcomes and cost recorded; a remedy that yields
// nothing loses automatic eligibility; unfamiliar code defects become owned engineering work), §6 (closed loop through the scheduled controller for
// AER, Course Link and scholarships, and safe refusal) and §7 (baseline and current in the ops_report_v1 self_sustainability section). The behaviour
// runs on isolated fixtures by tests/fixtures/recovery-knowledge/run.sh (scratch PostgreSQL 16; the real controller; the edited definitions loaded as
// live and md5-checked; the migration applied, then applied again unchanged). This spec holds the contract.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261104600000_cf247_recovery_knowledge.sql', 'utf8')
const FX = 'tests/fixtures/recovery-knowledge'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const EDITS = {
  'security.ops_authorise_v1(text)': ['ae58963cd1298edeeacae406dc65b314', '9f4a124db50a835f23ccb475f8d935c8'],
  'security.first_run_verify_tick_v1()': ['9c078d17de8d699de2d932ad1eca8fb8', '9df7a97bd494ff3c5425925e419553a5'],
  'security.self_sustainability_v1(integer)': ['a91e9c8151cca09763cf755ab1da1f56', '1965a71983c841617d9e06d29fa363ec'],
}

test('three md5-guarded edits from live; the controller tick and ops_report_v1 are not edited; no new job or controller', () => {
  for (const [sig, [b, a]] of Object.entries(EDITS)) {
    expect(m).toContain(`select pg_temp.edit_once('${sig}', '${b}', '${a}'`)
    expect(run).toContain(`["${sig}"]=${b}`)
    expect(m).toContain(`('${sig}', '${a}')`)
  }
  expect(m.match(/select pg_temp\.edit_once\(/g)).toHaveLength(3)
  expect(m).toContain("('security.ops_report_v1(integer)', '518b5bf873549931a15d4173fef793d5')")
  expect(m).not.toMatch(/edit_once\('security\.ops_controller_tick_v1/)
  expect(m).not.toMatch(/cron\.(schedule|alter_job|unschedule)/)
})

test('§2: the knowledge base keeps every field the direction lists, beside the remedy catalogue', () => {
  for (const c of ['fingerprint_like text[]', 'root_cause text', 'remedy_code text references pipeline.ops_remedies(code)', 'trigger_conditions jsonb',
    "authority text not null check (authority in ('auto', 'release', 'admin', 'layer4_human'))", "performed_by text not null check (performed_by in ('platform', 'claude_engineering', 'platform_admin', 'layer4_human'))",
    'expected_outcome text not null', 'no_retry_condition text not null', 'reuse_conditions text not null', 'auto_eligible boolean not null default true'])
    expect(m).toContain(c)
  expect(m).toContain('remedy_run_id bigint unique references pipeline.ops_remedy_runs(id)')
  // seeds are real outcomes with who achieved them
  for (const s of ["'sch_classify_duplicate_key', 'scholarship'", "'course_link_approved_rules', 'course_link'", "'aer_corrected_reread_same_copy', 'aer'", "'aer_reread_row_limit', 'aer'"]) expect(m).toContain(s)
  expect(m).toContain("'claude_engineering',\n  'one case per (provider, item key)")
  expect(m).toContain('select security.ops_learning_harvest_v1();')
})

test('§3: recurrence reuses only authorised remedies, stops ineffective ones, lifts on changed evidence, and escalates', () => {
  expect(m).toContain("$n$when not m.active then 'remedy switched off' when security.ops_learning_refusal_v1(m.code) is not null then security.ops_learning_refusal_v1(m.code) when m.action_fn is null$n$")
  expect(m).toContain("continue when m.code is null or coalesce(i.ops_plan->>'proposed', '') <> m.code;")
  expect(m).toContain("update pipeline.integration_issues set remedy_code = m.code, remedy_attempts = v_max")
  expect(m).toContain("if security.ops_learning_signature_v1(i.id) is distinct from b.signature then")
  expect(m).toContain("security.pipeline_num_v1('learn.no_yield_max', 3)")
  expect(m).toContain("security.pipeline_num_v1('learn.min_success_pct', 20)")
  expect(m).toContain("'fingerprint', 'remedy_ineffective:' || x.remedy_code")
  // within authority: nothing written to settings, remedies, root causes, Layer 4 decisions, locks or consumer objects
  expect(m).not.toMatch(/update\s+pipeline\.(platform_toolset_settings|ops_remedies|ops_root_causes|layer4_|manual_locks)/i)
  expect(m).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(m).not.toMatch(/create\s+or\s+replace\s+function\s+(api\.|public\.website_|public\.zoho_)/i)
  expect(m).toContain("'learn.gate_on'")
})

test('§6 and §7: the fixture proves the closed loop per lane and the refusals; the report carries the seven metrics', () => {
  for (const s of ['AER: the controller recognised work_technical_hold and chose the verified remedy itself', 'AER: verified on a later run, the issue closed by the controller',
    'AER: the three items advanced to the next stage', 'AER: a re-read of the same copy with the same reader and settings is refused', 'AER: when the copy changes, reconsideration is allowed',
    'Course Link: the controller reused the verified recheck', 'Course Link: the controller does not repeat the ineffective recheck', 'Course Link: a deployed fix changes the evidence and lifts the block',
    'fees: Authorise refuses it', 'scholarships: the recurring classifier defect becomes owned engineering work', 'section 7: seven metrics with baseline and current'])
    expect(fixtures).toContain(s)
  for (const k of ['automatically_diagnosed', 'automatically_recovered', 'repeated_ineffective_prevented', 'claude_interventions', 'human_only_decisions', 'records_admitted', 'consumer_published'])
    expect(m).toContain(`'${k}'`)
  expect(run).toContain("grep -c ': applied$')\" = 3")
  expect(run).toContain("grep -c ': already applied$')\" = 3")
})
