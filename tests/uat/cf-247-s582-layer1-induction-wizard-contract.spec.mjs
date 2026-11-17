// Guards: Parallel Wave 2 (Platform Admin 17 Nov 2026 17:59; decisions 18:10): Layer 1 › + Add source is a six-step induction wizard whose drafts are Pipeline Operator and above and whose activation is the Platform Admin's with a reason, creating the source paused; AI Auto-Map switches on only when the mapper answers; a dry run is recorded by the service role and switches nothing on; per-source retention is recorded and no policy or prune job changes; Platform health has the Country & category completeness report over eight editable categories; the consumer API is not touched.
// Behaviour is proven on isolated PostgreSQL by tests/fixtures/layer1-induction-wizard/run.sh (workflow layer1-induction-wizard-test); these checks keep the rules in the migration and the screens.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { PAGES } from '../../src/nav-map.js'
import { mockAdmin } from './support/admin-mock.mjs'
import { parseDelimited, parseSample } from '../../src/lib/sample-parse.js'

const read = (p) => fs.readFileSync(p, 'utf8')
const m = read('supabase/migrations/20261117193000_cf247_layer1_induction_wizard.sql')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const wizard = read('src/Layer1InductionWizard.jsx'), report = read('src/CompletenessReport.jsx'), l1 = read('src/layer1-operations-entry.jsx'), main = read('src/mature-main.jsx')

test('the migration adds beside what exists: no drop, no consumer API object, no retention policy or job change', () => {
  expect(m).toContain('-- Replaces: the single-form Add a source panel'); expect(m).toContain('-- Retires: nothing.')
  for (const l of m.split('\n')) expect(l).not.toMatch(/^(drop|delete|truncate)\b|^alter table .* drop /i)
  expect(code).not.toMatch(/website_v2_|website_v3_|zoho_v2_|zoho_v3_|website_edge_|zoho_edge_|\bapi\./)
  expect(code).not.toMatch(/(insert into|update|delete from)\s+pipeline\.retention_class_policies/i)
  expect(code).not.toMatch(/cron\.(schedule|unschedule|alter_job)|automation_catalogue/i) // G1: no job
  for (const t of ['ref.enrichment_categories', 'ref.enrichment_category_fields', 'pipeline.layer1_source_inductions']) {
    expect(code).toContain(`create table if not exists ${t} (`); expect(code).toContain(`comment on table ${t} is `)
  }
  expect((code.match(/^ \('[a-z_]+', '[^']+', '[^']*(''[^']*)*', \d+\)[,]?$/gm) || []).length).toBe(8) // eight categories
})

test('G2: sizes and thresholds are settings read with pipeline_num_v1', () => {
  for (const k of ['layer1.induction_dry_run_rows', 'layer1.induction_sample_rows', 'health.layer4_age_warn_days', 'health.layer4_age_old_days']) {
    expect(code).toContain(`('pipeline', '${k}',`); expect(code).toContain(`security.pipeline_num_v1('${k}',`)
  }
  expect(code).toContain("security.pipeline_num_v1('destination.postcode_primary_min_share', 0.9)")
})

test('drafting is Pipeline Operator and above; activation is the Platform Admin with a reason and goes through admin_layer1_add_source', () => {
  expect(code.match(/security\.current_role_rank\(\), 0\) < 4/g).length).toBe(3) // read, save, cancel
  const act = code.slice(code.indexOf('function public.admin_layer1_induction_activate'), code.indexOf('function public.svc_layer1_induction_read'))
  expect(act).toContain("security.current_role_rank(), 0) < 6"); expect(act).toContain("raise exception 'a reason is required'")
  expect(act).toContain('v_added := public.admin_layer1_add_source(jsonb_build_object(')
  expect(act).toContain("values ('layer1', 'induction_activate', v_source::text"); expect(act).toContain("'source_paused', true")
  expect(act).not.toMatch(/paused\s*=\s*false|update pipeline\.layer1_source_operations/i) // activation never resumes a source
})

test('a dry run is recorded by the service role only and switches nothing on', () => {
  const dry = code.slice(code.indexOf('function public.svc_layer1_induction_dry_run_record'), code.indexOf('function public.admin_enrichment_category_field_set'))
  expect(dry).toContain("if coalesce(auth.role(), '') <> 'service_role' then raise exception 'service role required'")
  expect(dry).not.toMatch(/status\s*=\s*'activated'|admin_layer1_add_source|pipeline\.sources/)
  expect(code).toContain('revoke all on function public.svc_layer1_induction_dry_run_record(uuid, jsonb) from public, anon, authenticated;')
})

test('the wizard has six steps, saves a draft at each, and AI Auto-Map is off until the mapper answers', () => {
  expect(wizard).toContain("export const STEPS=[['scheme','Country & scheme'],['source','Source & licence'],['mapping','Field mapping'],['cadence','Cadence & retention'],['dry_run','Dry-run preview'],['activate','Activation']]")
  expect(wizard).toContain("export const MAPPER='layer1-ai-induction-mapper'")
  expect(wizard).toContain("call(MAPPER,{action:'status'})"); expect(wizard).toContain('setMapper(!error&&data?.ok?data:false)')
  expect(wizard).toContain("disabled={closed||!mapper||busy!==''}")
  expect(wizard).toContain("rpc('admin_layer1_induction_save',{p_id:id,p_payload:payload,p_mappings:maps})")
  expect(wizard).toContain("rpc('admin_layer1_induction_activate',{p_id:saved.id,p_reason:why})")
  expect(wizard).toContain("disabled={busy!==''||rank<6||reason.trim().length<4}")
  expect(wizard).toContain('data-l1i-dry-run="waiting_for_reader"')
  expect(l1).toContain('{adding&&<Layer1InductionWizard rank={rank}'); expect(l1).not.toContain('function AddLayer1Source(')
})

test('a sample is read in the browser: delimited text and JSON give column names and the first rows', () => {
  expect(parseDelimited('a,b\n1,"x, y"\n2,z\n', 20)).toEqual({ columns: ['a', 'b'], rows: [['1', 'x, y'], ['2', 'z']], total_rows: 2 })
  expect(parseDelimited('a;b\r\n1;2\r\n3;4\r\n5;6', 2)).toEqual({ columns: ['a', 'b'], rows: [['1', '2'], ['3', '4']], total_rows: 3 })
  expect(parseSample('x.json', '{"data":[{"a":1,"b":{"c":2}},{"a":3}]}', 20)).toEqual({ columns: ['a', 'b'], rows: [['1', '{"c":2}'], ['3', '']], total_rows: 2 })
  expect(parseSample('x.csv', '', 20)).toBeNull()
  expect(wizard).toContain("import{parseSample}from'./lib/sample-parse.js'")
})

test('Platform health has the report as its own tab for Curator and above', () => {
  const tab = PAGES.health.tabs.find((t) => t.key === 'completeness')
  expect(tab).toMatchObject({ label: 'Country & category completeness', min: 3 })
  expect(main).toContain("case'health':return tab==='completeness'?<CompletenessReport rank={rank} onError={onError}/>:")
  for (const k of ['data-ccr-matrix', 'data-ccr-editions', 'data-ccr-layer4', 'data-ccr-move={x.field}']) expect(report).toContain(k)
  expect(report).toContain("rpc('admin_completeness_report',{})")
})

test('mocked browser: the report shows fill by country and category, a figure opens its fields, editions and Layer 4 ageing', async ({ page }) => {
  await mockAdmin(page)
  await page.goto('/#platform-health?tab=completeness')
  const r = page.locator('[data-completeness-report]')
  await expect(r.locator('[data-ccr-category]')).toHaveCount(2)
  await expect(r.locator('[data-ccr-cell="AU:course_basics"]')).toContainText('70.0%')
  await expect(r.locator('[data-ccr-category="fees"]')).toContainText('Not measured') // NZ has no fees figure
  await r.locator('[data-ccr-cell="AU:course_basics"]').click()
  await expect(r.locator('[data-ccr-detail]')).toContainText('140 of 200 values held')
  await expect(r.locator('[data-ccr-detail]')).toContainText('Duration')
  await expect(r.locator('[data-ccr-source="s-cricos"]')).toContainText('Permanent')
  await expect(r.locator('[data-ccr-l4="course"]')).toContainText('12')
})
