// Guards: Platform Admin 6 Nov 2026 09:44 §3 (English requirements D1 scope, D2 human approval and binding, D3 search switched off, D5 reparse through policy-add-tests, D6 no VET level), §4 (compatibility gate) and §5 (operator visibility)
// Parser v0.3.0 course groups and their compatibility with v0.2.5, the migration 20261106550000 source contract, the worker mode and the English policies screen hooks.
// The database behaviour (UNSW-shaped table to a bound, applied, published-through-the-same-path row) is tests/fixtures/english-requirements/run.sh (CI: english-requirements-test.yml).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { loadParser } from '../fixtures/english-requirements/baseline.mjs'
import { PAGES } from '../fixtures/english-requirements/compat-pages.mjs'
import { FACULTY_TABLE } from '../fixtures/english-requirements/groups.mjs'

const MIG = fs.readFileSync('supabase/migrations/20261106550000_cf247_english_requirements_complete.sql', 'utf8')
const CODE = MIG.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')
const OLD = JSON.parse(fs.readFileSync('tests/fixtures/english-requirements/parser-v025-outputs.json', 'utf8'))
const WORKER = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const POLICIES = fs.readFileSync('src/ProviderPolicies.jsx', 'utf8')
const GROUPS = fs.readFileSync('src/EnglishGroups.jsx', 'utf8')

test('parser v0.3.0 reads a faculty table with different scores as course groups, never as a university default', async () => {
  const { englishPolicy } = await loadParser()
  const r = englishPolicy(FACULTY_TABLE)
  expect(r.style).toBe('course_groups')
  expect(r.defaults).toEqual({})
  const rows = r.groups.map((g) => `${g.group_name}|${g.level}|${g.reqs.find((q) => q.test_code === 'IELTS').overall_score}`).sort()
  expect(rows).toEqual(['Economics and Law|postgraduate|7', 'Economics and Law|undergraduate|7', 'Science|postgraduate|6.5', 'Science|undergraduate|6',
    'Social Sciences|postgraduate|7', 'Social Sciences|undergraduate|6.5'])
  for (const g of r.groups) expect(g.reqs[0].quote).toContain(g.group_name)  // every group score carries its source words
})

test('compatibility: pages v0.2.5 read as a default, exceptions or nothing are read the same by v0.3.0 (no groups added)', async () => {
  const { englishPolicy } = await loadParser()
  expect(OLD.parser).toBe('provider-policy-v0.2.5')
  for (const [name, md] of Object.entries(PAGES)) {
    const r = englishPolicy(md)
    const { style, defaults, exceptions, named, caveats, signals, conflicts } = r
    expect({ style, defaults, exceptions, named, caveats, signals, conflicts }, name).toEqual(OLD.outputs[name])
    expect(r.groups ?? [], name).toEqual([])
  }
})

test('a group name is never a heading that is not a course group (admission wording, default cue, band label, number or test name)', async () => {
  const { englishPolicy } = await loadParser()
  const md = `## IELTS Academic\n\n| Faculty | Undergraduate | Postgraduate coursework |\n|---|---|---|\n| Foundation program | Overall 6.5 | Overall 7.0 |\n| Band 6.0 | Overall 6.0 | Overall 6.5 |\n| IELTS | Overall 7.5 | Overall 7.5 |\n| 2026 | Overall 6.0 | Overall 6.5 |\n`
  expect(englishPolicy(md).groups ?? []).toEqual([])
})

test('the migration guards every replaced function on its live md5 and the policy-add-tests command', () => {
  const guarded = [...MIG.matchAll(/\('((?:public|security)\.[a-z_0-9]+\([^)]*\))', '([0-9a-f]{32})'\)/g)].map((m) => m[1])
  for (const sig of ['public.svc_provider_policy_record(uuid,jsonb)', 'security.policy_auto_approve_v1()', 'security.central_pages_attach_v1()', 'security.central_ai_enqueue_v1(uuid)', 'security.provider_english_plan_v1(uuid)',
    'security.provider_english_apply_v1(uuid)', 'public.admin_provider_policies_read(text,uuid)', 'public.admin_provider_policy_decide(uuid,text,text)', 'public.svc_provider_facts_search_next(integer)'])
    expect(guarded, sig).toContain(sig)
  expect(MIG).toContain('4827953f23c896d5ae05b14dd4ca722f')  // the live policy-add-tests command
  expect(MIG).toMatch(/-- Replaces:/); expect(MIG).toMatch(/-- Retires: nothing/)
})

test('D1/D3/D5 settings ship with today\'s behaviour: every provider type, search switched off, a bounded reparse', () => {
  expect(MIG).toContain(`'list', '["*"]'::jsonb, null, null, 'provider types', 1010, 'English policies'`)
  expect(MIG).toContain(`'number', to_jsonb(0), 0, 1, 'on/off', 1012, 'English policies'`)
  expect(MIG).toContain(`'number', to_jsonb(20), 0, 200, 'documents', 1011, 'English policies'`)
  expect(MIG).toContain(`'number', to_jsonb(10), 1, 100, 'providers', 1013, 'English policies'`)
  expect(MIG).toContain("security.pipeline_num_v1('batch.policy_reparse', 20)")
  expect(MIG.match(/cron\.alter_job/g).length).toBe(1)          // the existing policy-add-tests job only
  expect(MIG).not.toMatch(/cron\.schedule/)                      // no new scheduler (D5)
})

test('D2: no setting, no function and no path approves a course-group reading automatically; a Platform Admin approves and binds', () => {
  expect(MIG).not.toMatch(/auto_approve_group|central\.auto_approve_groups/)
  expect(MIG).toMatch(/jsonb_array_length\(case when jsonb_typeof\(x\.proposal->'groups'\)[\s\S]{0,120}= 0/)   // policy_auto_approve_v1 takes proposals without groups only
  expect(MIG).toMatch(/security\.current_role_rank\(\) < 6 then raise exception 'Platform Admin role required'/)
  expect(MIG).toContain("'english_groups_bound'")
  expect(MIG).toContain("revoke all on function public.admin_provider_english_groups_set_v1(uuid, jsonb, text) from public, anon;")
})

test('G3 consumer API frozen and no VET level: the migration names no consumer object, drops nothing and adds no study level', () => {
  expect(MIG).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|\bapi\.[a-z_]+\(/i)
  expect(MIG).not.toMatch(/^\s*(drop|truncate)\s/im)
  expect(MIG).not.toMatch(/delete\s+from\s+(?!pipeline\.provider_fact_search\b)/i)
  expect(CODE).not.toMatch(/\bvet\b/i)
})

test('D5: the worker reads stored pages again inside the existing mode, with no fetch and no model', () => {
  const i = WORKER.indexOf('// CF-247 English requirements (6 Nov 2026, D5)')
  const j = WORKER.indexOf('if (mode === "provider_facts_inspect"', i)
  const block = WORKER.slice(i, j)
  expect(block).toContain('svc_provider_policy_reparse_next')
  expect(block).toContain('svc_provider_policy_record')
  expect(block).not.toMatch(/firecrawl|openrouter|fetch\(|useFcWhy|ai:/i)
  expect(WORKER).toContain('const WORKER = "coverage-sweep-worker-v0.59.9"')
})

test('operator visibility: the English policies screen shows group binding, group counts and No rule yet from the existing reads and the existing job control', () => {
  expect(POLICIES).toContain("import{GroupBinding,EnglishStatus}from'./EnglishGroups'")
  expect(POLICIES).toContain('data-group-count')
  expect(POLICIES).not.toContain('parsed without AI')
  expect(GROUPS).toContain("'admin_provider_english_groups_set_v1'")
  expect(GROUPS).toContain("'admin_provider_english_status_read'")
  expect(GROUPS).toMatch(/admin_automation_control[\s\S]{0,80}policy-add-tests|p_job:'policy-add-tests'/)
  for (const stage of ['approved', 'group_proposed', 'rule_proposed', 'rejected', 'page_read_no_rule', 'page_not_stored', 'weak_candidates_only', 'mapped_no_page', 'not_mapped'])
    expect(MIG, stage).toContain(`'${stage}'`)
})
