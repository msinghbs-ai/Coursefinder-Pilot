// Guards: Parallel Wave 2 (Platform Admin 17 Nov 2026 17:59; decisions 18:10): Layer 1 › + Add source is a six-step induction wizard whose drafts are Pipeline Operator and above and whose activation is the Platform Admin's with a reason, creating the source paused; AI Auto-Map switches on only when the mapper answers; a dry run is recorded by the service role and switches nothing on; per-source retention is recorded and no policy or prune job changes; Platform health has the Country & category completeness report over eight editable categories; the consumer API is not touched. Addenda (Platform Admin 17 Nov 2026 19:09): each Layer 1 source line shows a Hardcoded or AI-built parser badge with Re-infer Parser Spec when a reader flags layout drift (recorded and logged, nothing run), and the wizard takes one of seven target record types and keeps the AI mapper's parser spec with the draft. Decisions (Platform Admin 17 Nov 2026 19:58 and 20:45): one category list published to every lane; per-source retention only in pipeline.source_retention_policies; Curator (rank 3) and above open Layer 1 and draft, Re-infer Parser Spec stays Pipeline Operator (rank 4) and above, activation stays Platform Admin (rank 6).
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
  expect(wizard).toContain("disabled={closed||!mapper||!f.target_record_type||busy!==''}")
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
  await expect(r.locator('[data-ccr-source="s-cricos"]')).toContainText('90 days') // the platform staging period
  await expect(r.locator('[data-ccr-source="s-cricos"]')).toContainText('7 years')
  await expect(r.locator('[data-ccr-l4="course"]')).toContainText('12')
})

test('addenda: the parser table and functions add beside what exists; the four induction functions are replaced only from their known definitions', () => {
  const n = read('supabase/migrations/20261117203000_cf247_layer1_parser_line_items.sql')
  const c = n.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
  expect(n).toContain('-- Replaces: nothing (four induction functions extended in place).'); expect(n).toContain('-- Retires: nothing.')
  for (const l of n.split('\n')) expect(l).not.toMatch(/^(drop|delete|truncate)\b|^alter table .* drop /i)
  expect(c).not.toMatch(/website_v2_|website_v3_|zoho_v2_|zoho_v3_|website_edge_|zoho_edge_|\bapi\./)
  expect(c).not.toMatch(/cron\.(schedule|unschedule|alter_job)|automation_catalogue/i)
  expect(c).toContain('create table if not exists pipeline.layer1_source_parsers ('); expect(c).toContain('comment on table pipeline.layer1_source_parsers is ')
  for (const h of ['8dcb609809443e60ceb192b796579c61', '55adb79297f228419c0d02aeb5c16f92', '0a8fac994a5a553968dc40df55d1a5a3', '1f3ba519ed00322440d9347261cd7ec8']) expect(c).toContain(`'${h}'`)
  expect(c).toContain("is distinct from 'cf247_wave2_parser'")
  expect((c.match(/jsonb_build_object\('key', '[a-z_]+', 'label', /g) || []).length).toBe(7) // seven target record types
  const re = c.slice(c.indexOf('function public.admin_layer1_parser_reinfer_request'), c.indexOf('function public.svc_layer1_parser_record'))
  expect(re).toContain("raise exception 'a reason is required'"); expect(re).toContain("raise exception 'no layout drift is flagged for this source'")
  expect(re).toContain("values ('layer1', 'parser_reinfer_request', p_source_id::text")
  expect(re).not.toMatch(/layer1_source_operations|paused|admin_layer1_command|net\.http/) // the request runs nothing
  for (const f of ['svc_layer1_parser_record(uuid, jsonb)', 'svc_layer1_parser_drift_record(uuid, boolean, text)']) expect(c).toContain(`revoke all on function public.${f} from public, anon, authenticated;`)
})

test('addenda: the Layer 1 line shows the parser badge and Re-infer Parser Spec; the wizard has the target record type and the spec preview', () => {
  expect(l1).toContain("export const PARSER_LABEL={hardcoded:'Hardcoded parser',ai_built:'AI-built parser',none:'No parser yet'}")
  expect(l1).toContain("{key:'parser',label:'Parser',"); expect(l1).toContain("supabase.rpc('admin_layer1_parser_status')")
  expect(l1).toContain("{parser.drift_flagged_at&&!parser.reinfer_requested_at&&rank>=4&&<button onClick={reinfer} disabled={!!busy} data-l1-reinfer>")
  expect(l1).toContain("supabase.rpc('admin_layer1_parser_reinfer_request',{p_source_id:source.source_id,p_reason:why.trim()})")
  for (const k of ['data-l1i-record-type', 'data-l1i-parser-spec={f.parser_spec?\'present\':\'none\'}', 'data-l1i-routing', 'data-l1i-spec-discard']) expect(wizard).toContain(k)
  expect(wizard).toContain("{action:'map',induction_id:saved.id,target_record_type:f.target_record_type,")
})

test('decisions: one category list is published, retention lives in the retention table, and the role gates are 3 to open and draft, 4 to re-infer, 6 to activate', () => {
  const u = read('supabase/migrations/20261117213000_cf247_wave2_unify_categories_retention_roles.sql')
  const c = u.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
  expect(u).toContain('-- Retires: nothing.'); expect(u).toMatch(/^-- Replaces: the wizard's own per-source retention values/m)
  for (const l of u.split('\n')) expect(l).not.toMatch(/^(drop|delete|truncate)\b|^alter table .* drop /i)
  expect(c).not.toMatch(/website_v2_|website_v3_|zoho_v2_|zoho_v3_|website_edge_|zoho_edge_|\bapi\./)
  expect(c).not.toMatch(/cron\.(schedule|unschedule|alter_job)|automation_catalogue|create table/i)
  // categories: published from the one table, to the service role
  expect(c).toContain('create or replace function public.svc_enrichment_categories() returns jsonb')
  expect(c).toContain('revoke all on function public.svc_enrichment_categories() from public, anon, authenticated;')
  expect(c).not.toMatch(/country_category_boost'\s*(,|\))\s*.*(update|insert)/i) // the Boost setting is not written here
  // retention: no values of the wizard's own; activation goes through S1-Build's function; periods come from settings
  expect(c).not.toMatch(/'staging_retention_days'|'raw_retention_days'/)
  expect(c).toContain("perform public.admin_source_retention_set(v_source, (v_row.payload->>'staging_keep_days')::int, 'Induction wizard: ' || v_reason);")
  expect(c).toContain('left join pipeline.source_retention_policies rp on rp.source_id = s.id')
  for (const k of ['retention.staging_keep_days', 'retention.raw_hash_keep_years', 'retention.staging_prune_on']) expect(c).toContain(`security.pipeline_num_v1('${k}',`)
  // roles: the Layer 1 list read and the draft functions open at 3 by an exact, md5-guarded text change; activation is not lowered
  expect(c).toContain("select pg_temp.swap_once('security.admin_layer1_operations_read(jsonb)', '0e93afeba4d14c2ad2ce2d492ffd14d4', '3af9dff07f35f774e935fc590552ce13',")
  expect(c).toContain("if v_md5 <> p_before then raise exception '% is not the definition this change was written against', p_fn; end if;")
  const act = c.slice(c.indexOf('function public.admin_layer1_induction_activate'), c.indexOf('function public.admin_completeness_report'))
  expect(act).toContain('security.current_role_rank(), 0) < 6'); expect(act).not.toMatch(/current_role_rank\(\), 0\) < [345]/)
  expect(c).not.toContain('admin_layer1_parser_reinfer_request(uuid,text)\', \'') // the re-infer gate is not swapped
  expect(PAGES.layer1.min).toBe(3)
  expect(l1).toContain('rank>=3&&<button className="primary" onClick={()=>setAdding(x=>!x)} data-l1-add>')
  expect(l1).toContain('parser.drift_flagged_at&&!parser.reinfer_requested_at&&rank>=4&&<button onClick={reinfer}')
  expect(wizard).toContain("if(rank<3)return <EmptyInline text=\"Adding a source opens for Curator and above.\"/>")
  expect(wizard).toContain("disabled={busy!==''||rank<6||reason.trim().length<4}")
  expect(wizard).not.toMatch(/raw_retention_days|staging_retention_days/); expect(report).not.toMatch(/raw_retention_days|staging_retention_days/)
})

test('mocked browser: a Curator opens Layer 1 and the wizard; Re-infer Parser Spec is not offered to a Curator', async ({ page }) => {
  await mockAdmin(page, { rank: 3 })
  await page.goto('/#layer-1-register')
  const l = page.locator('[data-l1-sources]')
  await expect(l.locator('[data-l1-parser="ai_built"]')).toContainText('AI-built parser')
  await l.getByRole('button', { name: 'Open Centennial College Program Catalogue API' }).click()
  await expect(l.locator('[data-l1-drift]')).toBeVisible()
  await expect(l.locator('[data-l1-reinfer]')).toHaveCount(0)
  await l.getByRole('button', { name: 'Add source' }).click()
  const a = page.locator('[data-l1-induction-wizard]')
  await expect(a.locator('[data-l1i-country]')).toBeVisible()
  await a.locator('[data-l1i-tab="activate"]').click()
  await expect(a.locator('[data-l1i-activate]')).toBeDisabled()
})
