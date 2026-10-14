// CF-247 v2.15.276 (14 Oct 2026), Decision 258: institution type from the registers.
// Platform Admin choices (multiple choice, 14 Oct): types mirror the registers; Australian universities from the TEQSA National
// Register (data.gov.au); a CRICOS Government provider offering VET is TAFE; NZ from NZQA; Canada empty; training.gov.au later.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261014060746_cf247_institution_type.sql', 'utf8')
const putFix = fs.readFileSync('supabase/migrations/20261014063911_cf247_register_facts_put_set_based.sql', 'utf8')
const worker = fs.readFileSync('supabase/functions/layer1-provider-facts/index.ts', 'utf8')
const control = fs.readFileSync('supabase/functions/layer1-operations-control/index.ts', 'utf8')
const scheduled = fs.readFileSync('supabase/functions/layer1-operations-scheduled/index.ts', 'utf8')
const deploy = fs.readFileSync('.github/workflows/deploy-edge-functions.yml', 'utf8')

test('migration: register types, facts, ordered rules, nothing dropped or deleted by data', () => {
  for (const c of ['university_college', 'higher_education_institute', 'tafe_polytechnic', 'private_vet', 'school', 'wananga']) expect(sql).toContain(`('${c}', `)
  expect(sql).toContain("set status = 'retired'") // tafe and college kept, not dropped
  expect(sql).toContain('create table if not exists catalogue.provider_register_facts (')
  expect(sql).toContain('create table if not exists pipeline.provider_type_rules (')
  // the rule order the Platform Admin chose: TEQSA university first, then CRICOS Government with VET is TAFE
  expect(sql.indexOf("(10, 'AU', '^Australian University$'")).toBeLessThan(sql.indexOf("(20, 'AU', null, null, '^Government$', null, 'vet', 'tafe_polytechnic'"))
  expect(sql.indexOf("(20, 'AU'")).toBeLessThan(sql.indexOf("(40, 'AU', '^Institute of Higher Education$'"))
  expect(sql).not.toMatch(/\(\d+, 'CA'/) // Canada stays empty
  expect(sql).not.toMatch(/^\s*(drop|truncate)\b/im)
  expect(sql).not.toMatch(/^\s*delete\s+from\s+(catalogue|ref)\./im)
})

test('migration: a hand-set type wins; no rule means no type, with the reason kept', () => {
  expect(sql).toContain("and not exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = pr.id and l.field = 'provider_type_id')")
  expect(sql).toContain("set provider_type_id = null, provider_type_basis = c.reason")
  expect(sql).toContain("'No rule matched: '")
  expect(sql).toContain("coalesce(security.current_role_rank(), 0) < 5 then raise exception 'PIM Admin role or above required'")
  expect(sql).toContain("perform set_config('cf.manual_edit', 'on', true);")
})

test('migration: every replaced function is md5-guarded and each anchor is checked', () => {
  for (const md5 of ['081d6a57499f286217d663628784bb64', '4d07ec592074c421890c82c0552c52f2', 'c9fcc242bd5b5d411a51443f95e1d779', '19b602f54ae10b932f1515c55c45d14f', '2d4d19097c34cde01897d44e7a27e8f1', '0204f4336ec28dff7e6bd6af6a5fd701']) expect(sql).toContain(`if md5(v) <> '${md5}' then raise exception`)
  expect(sql).toContain("'institution_type', api.website_v2_institution_type(d.provider_id)")
  expect(sql).toContain("'institution_type', api.website_v2_institution_type(o.provider_id)")
  expect(sql).toContain("'has_tuition','changed_since','institution_types'];")
  expect(sql).toContain("'institution_types', (select jsonb_agg(")
})

test('the facts writer matches every code in one statement (the API role stops a statement after 8 seconds)', () => {
  expect(putFix).toContain("if md5(pg_get_functiondef('public.svc_provider_register_facts_put(uuid,uuid,text,jsonb)'::regprocedure)) <> 'd1b4e3b2b1689f13a211703475f2b7a2'")
  expect(putFix).toContain('select distinct on (upper(pr.registration_code)) upper(pr.registration_code) code, pr.provider_id')
  expect(putFix).not.toMatch(/\bloop\b/i)
  expect(putFix).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

test('G1/G2: the daily job is catalogued and its command holds no number; the sources start paused', () => {
  expect(sql).toContain("select cron.schedule('provider-type-classify', '47 3 * * *', 'select public.svc_provider_type_classify()');")
  expect(sql).toContain("insert into pipeline.automation_catalogue (jobname, area, sort, label, description, control_rank, batch_editable)")
  expect(sql).toMatch(/array\['data\.gov\.au'\], 'CSV resource on data\.gov\.au, found through its CKAN package', 'providers', true, true, 7, 7, false,/)
  expect(sql).toContain("select 'layer1-provider-facts', 'Decision 258")
})

test('worker: service key or one-time nonce, approved host only, evidence kept, then the rules run', () => {
  expect(worker).toContain('const VERSION = "layer1-provider-facts-v1.1.0";')
  expect(worker).toContain('clean(meta.format) === "nzqa_type_listing"')
  expect(worker).toContain('svc_pilot_consume_nonce')
  expect(worker).toContain('internal service key or one-time nonce required')
  expect(worker).toContain('source authority mismatch')
  expect(worker).toContain('svc_layer1_evidence_by_hash')
  expect(worker).toContain('"svc_provider_register_facts_put"')
  expect(worker).toContain('"svc_provider_type_classify"')
  expect(worker).toMatch(/const FETCH_MS = \d+; \/\/ fixed: API time-out/)
  expect(control).toContain('const VERSION="layer1-operations-control-v1.9.0";')
  expect(control).toContain('if(system==="PROVIDER_FACTS"){const body=await invokeStatWorker(url,serviceKey,"layer1-provider-facts",{source_id:sourceId,mode:"dry_run"})')
  expect(control).toContain('system==="PROVIDER_FACTS"?{source_id:q.source_id,mode:apply?"apply":"dry_run"}')
  expect(scheduled).toContain('const VERSION="layer1-operations-scheduled-v1.5.0";')
  expect(scheduled).toContain('if(system==="PROVIDER_FACTS"){const body=await invokeStatWorker(url,serviceKey,"layer1-provider-facts",{source_id:ctx.source_id,mode:"dry_run"})')
  expect(deploy).toContain('[layer1-provider-facts]=false')
})

test.describe('mocked browser', () => {
  const types = [{ code: 'university', name: 'University' }, { code: 'tafe_polytechnic', name: 'TAFE / Polytechnic' }, { code: 'private_vet', name: 'Private VET college' }]
  const rules = [
    { id: 'r10', position: 10, country_code: 'AU', teqsa_category: '^Australian University$', teqsa_status: '^Active$', result_type: 'university', enabled: true, label: 'TEQSA register: Australian University' },
    { id: 'r20', position: 20, country_code: 'AU', register_type: '^Government$', course_profile: 'vet', result_type: 'tafe_polytechnic', enabled: true, label: 'CRICOS Government provider offering VET' }]
  const providers = { total: 2, items: [
    { id: 'p-a', canonical_name: 'Alpha University', country_code: 'AU', course_count: 20, lifecycle_status: 'active', publication_status: 'published', provider_type_code: 'university', provider_type_name: 'University', provider_type_basis: 'TEQSA register: Australian University', provider_type_locked: false },
    { id: 'p-b', canonical_name: 'Beta Institute', country_code: 'AU', course_count: 5, lifecycle_status: 'active', publication_status: 'published', provider_type_code: null, provider_type_name: null, provider_type_basis: 'No rule matched: TEQSA none, CRICOS none, VET', provider_type_locked: false }] }
  async function setup(page, rank) {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    await mockAdmin(page, { rank })
    const calls = []
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', async route => {
      const b = route.request().postDataJSON() || {}
      if (b.p_operation === 'providers_page') return route.fulfill({ json: providers })
      return route.fallback()
    })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_adapter_autobuild', r => r.fulfill({ json: {} }))
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_provider_type_rules', async route => {
      const b = route.request().postDataJSON() || {}; calls.push({ rules: b })
      if (b.p_action === 'save') return route.fulfill({ json: { saved: true, classify: { classified: 10, no_rule: 2 } } })
      if (b.p_action === 'run') return route.fulfill({ json: { classified: 10, no_rule: 2, changed: 1 } })
      return route.fulfill({ json: { rules, types, counts: { university: 45, none: 12 }, can_edit: rank >= 6 } })
    })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_provider_set_type', async route => {
      const b = route.request().postDataJSON(); calls.push({ setType: b })
      await route.fulfill({ json: { provider_id: b.p_provider_id, provider_type_code: 'private_vet', provider_type_name: 'Private VET college', provider_type_basis: 'Set by a person', provider_type_locked: true } })
    })
    return calls
  }

  test('Providers: the Type column shows the type, Needs type with its reason, and PIM Admin sets it with no reason prompt', async ({ page }) => {
    let prompted = false
    page.on('dialog', d => { prompted = true; d.dismiss() })
    const calls = await setup(page, 5)
    await page.goto('/#providers')
    const alpha = page.locator('tr', { hasText: 'Alpha University' }), beta = page.locator('tr', { hasText: 'Beta Institute' })
    await expect(alpha.locator('[data-type-code="university"]')).toHaveAttribute('title', 'TEQSA register: Australian University')
    await expect(beta.locator('[data-type-code="none"]')).toContainText('Needs type')
    await beta.getByLabel('Institution type for Beta Institute').selectOption('private_vet')
    await expect(beta.locator('[data-type-code="private_vet"]')).toContainText('Private VET college · set by hand')
    expect(calls.find(c => c.setType)?.setType).toEqual({ p_provider_id: 'p-b', p_type_code: 'private_vet' })
    expect(prompted).toBe(false)
  })

  test('Providers: a viewer sees the type but cannot set it', async ({ page }) => {
    await setup(page, 1)
    await page.goto('/#providers')
    await expect(page.locator('tr', { hasText: 'Alpha University' }).locator('[data-type-code="university"]')).toBeVisible()
    await expect(page.getByLabel('Institution type for Alpha University')).toHaveCount(0)
  })

  test('Pipeline settings: the rules card lists the rules; Platform Admin changes a type and runs the rules', async ({ page }) => {
    const calls = await setup(page, 6)
    await page.goto('/#environment')
    const card = page.locator('[data-settings-section="institution_type"]')
    await expect(card.locator('[data-type-rule="10"]')).toContainText('TEQSA Australian University (Active)')
    await expect(card.locator('[data-type-rule="20"]')).toContainText('CRICOS Government · offers VET courses')
    await expect(card.locator('[data-type-counts]')).toContainText('University 45 · No type 12')
    await card.getByLabel('Type for CRICOS Government provider offering VET').selectOption('private_vet')
    await expect(card.getByRole('status')).toContainText('10 providers typed, 2 need a type')
    expect(calls.find(c => c.rules?.p_action === 'save')?.rules).toEqual({ p_action: 'save', p_args: { id: 'r20', result_type: 'private_vet' } })
    await card.getByRole('button', { name: 'Run the rules now' }).click()
    await expect(card.getByRole('status')).toContainText('1 changed')
  })
})
