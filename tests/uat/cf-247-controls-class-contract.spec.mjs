// Guards: Platform Admin 10 Nov 2026 – minimum human-maintained settings (F-OPS.05): every setting carries a control class (human, automatic, retiring); Settings groups by it and keeps every value visible and editable
// CF-247 F-OPS.05 ("Simplify production controls"). Source contract for the migration (column, backfill key lists, screen read) and a mocked browser check of the grouping on
// Settings › Pipeline settings. Mocked REST responses: nothing reaches a real backend. The phone-width check is tagged @responsive and runs on the phone project only.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261110080000_cf247_control_class.sql', 'utf8')
const UI = fs.readFileSync('src/SettingsRegister.jsx', 'utf8')
const PHONE_MAX = 480

const HUMAN = ['pdesc.enabled', 'pdesc.countries', 'pdesc.provider_types', 'pdesc.ai_usd_max', 'pdesc.firecrawl_reads_max', 'pdesc.acquire_firecrawl', 'pdesc.acquire_direct',
  'pdesc.machine_admit_on', 'pdesc.registry_factual_on', 'pdesc.machine_refused_words', 'pdesc.machine_refused_words_fr', 'pdesc.machine_numbers_allowed',
  'pdesc.evidence_claim_words', 'pdesc.pending_max', 'reading.provider_quote_fragments_on', 'pdesc.superlatives', 'pdesc.claim_words', 'pdesc.machine_neutral_words', 'pdesc.provider_keys']
// still read by deployed functions (scope test, enqueue, manual cohorts), so neither is retiring yet; provider_keys is a live scope pin (human), queue_per_run stays automatic
const STILL_READ = ['pdesc.provider_keys', 'pdesc.queue_per_run']

test('migration: one nullable column with three classes, commented, idempotent, replaces and retires nothing, drops nothing', () => {
  expect(MIG).toMatch(/^-- Replaces: nothing$/m)
  expect(MIG).toMatch(/^-- Retires: nothing$/m)
  expect(MIG).toContain("alter table pipeline.platform_toolset_settings add column if not exists control_class text check (control_class in ('human', 'automatic', 'retiring'));")
  expect(MIG).toContain('comment on column pipeline.platform_toolset_settings.control_class is')
  expect(MIG).toMatch(/Null = not yet classified, shown as human/)
  expect(MIG).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(MIG).not.toMatch(/insert into pipeline\.platform_toolset_settings/i) // no new setting is added
  expect(MIG).not.toMatch(/insert into pipeline\.component_register/i) // nothing is retiring yet, so nothing is registered as retiring
  // only rows still null are set, so applying it twice never overwrites a later decision
  expect(MIG.match(/control_class is null/g).length).toBeGreaterThanOrEqual(3)
})

test('migration: the human keys are exactly the 19 agreed, the rest of the provider-description controls are automatic, the two still read are not retiring', () => {
  const human = MIG.match(/set control_class = 'human'[\s\S]*?;/)[0]
  const keys = [...human.matchAll(/'((?:pdesc|reading)\.[a-z_]+)'/g)].map((m) => m[1])
  expect(keys.sort()).toEqual([...HUMAN].sort())
  const auto = MIG.match(/set control_class = 'automatic'[\s\S]*?;/)[0]
  expect(auto).toContain("key like 'pdesc.%'")
  expect(auto).toContain("key = 'batch.provider_description'")
  expect(auto).toContain("key like 'reading.provider\\_%' escape '\\'")
  expect(MIG).not.toMatch(/set control_class = 'retiring'/)
  expect(human).toContain("'pdesc.provider_keys'") // a live scope pin: a person decides it
  expect(human).not.toContain("'pdesc.queue_per_run'")
  expect(STILL_READ).toHaveLength(2)
  // the dependency evidence: the live readers the migration names are still in the migrations that define them
  const all = fs.readdirSync('supabase/migrations').filter((f) => f.endsWith('.sql')).map((f) => fs.readFileSync(`supabase/migrations/${f}`, 'utf8')).join('\n')
  expect(all).toContain("security.toolset_setting('pipeline', 'pdesc.provider_keys')")
  expect(all).toContain("security.pipeline_num_v1('pdesc.queue_per_run', 10)")
})

test('migration: the screen read carries control_class and replaced_by, guarded by the live body md5, post-checked', () => {
  expect(MIG).toContain('e340e9cf37475ea2e8310b6fb0401931')
  expect(MIG).toContain("'control_class', s.control_class")
  expect(MIG).toContain("'replaced_by', (select r.replaced_by from pipeline.component_register r where r.name = s.toolset_key || '.' || s.key and r.status = 'retiring' limit 1)")
  expect(MIG).toContain("if v_src like '%control_class%' then return; end if;")
  expect(MIG).toContain("raise exception 'F-OPS.05 post-check")
  // existing keys of the read are all still there (additive only)
  for (const k of ["'can_manage'", "'sections'", "'settings'", "'used_by'", "'updated_at'", "'check'", "'jobs'"]) expect(MIG).toContain(k)
  expect(MIG).not.toMatch(/api\.|website_v2_|zoho_edge_|website_edge_/) // consumer API (G3) not touched
})

test('screen source: human first, automatic and retiring collapsed groups, rows and their attributes unchanged, reason still required', () => {
  expect(UI).toContain('Automatically managed (software-tuned within safe limits)')
  expect(UI).toContain("data-control-group={c}")
  expect(UI).toContain('data-register-setting={s.key}')
  expect(UI).toContain("<details key={c} className=\"sr-group\"")
  expect(UI).toContain('reason.trim().length<4') // the existing Reason requirement stays on every row
  expect(UI).toContain("s.control_class==='automatic'||s.control_class==='retiring'?s.control_class:'human'") // null is human
})

const row = (key, extra = {}) => ({ key, label: `Label for ${key} with enough words that it wraps on a phone`, help: 'Help.', used_by: 'a job', kind: 'number', value: 10, min: 1, max: 99, unit: 'items', updated_at: '2026-11-09T22:00:00Z', reason: 'Set', ...extra })
const register = (canManage) => ({
  can_manage: canManage, jobs: 61, check: [],
  sections: [{ section: 'Provider descriptions', settings: [
    row('pdesc.tries', { control_class: 'automatic' }),
    row('pdesc.enabled', { control_class: 'human', kind: 'boolean', value: true }),
    row('batch.old_sizes'), // no class: shown as human
    row('pdesc.max_chars', { control_class: 'automatic', value: 1200, max: 5000 }),
    row('pdesc.legacy', { control_class: 'retiring', replaced_by: 'pdesc.queue_cap' }),
  ] }],
})

async function mount(page, { admin = true } = {}) {
  const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' }
  await page.route('**/rest/v1/rpc/**', async (route) => {
    const req = route.request()
    if (req.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: cors })
    const name = new URL(req.url()).pathname.split('/').pop()
    const body = name === 'admin_settings_register_read' ? register(admin) : name === 'admin_policy_tables_read' ? { can_manage: admin, tables: [], providers: {} } : {}
    return route.fulfill({ status: 200, headers: { ...cors, 'content-type': 'application/json' }, body: JSON.stringify(body) })
  })
  await page.addInitScript(() => { try { window.sessionStorage.setItem('cf.card.settings.register.provider-descriptions', '1') } catch { /* storage unavailable */ } })
  await page.goto('/')
  await page.evaluate(async () => {
    const React = await import('/node_modules/.vite/deps/react.js')
    const { default: ReactDOM } = await import('/node_modules/.vite/deps/react-dom_client.js')
    const { default: SettingsRegister } = await import('/src/SettingsRegister.jsx')
    document.body.innerHTML = '<div id="sr-root"></div>'
    ReactDOM.createRoot(document.getElementById('sr-root')).render(React.default.createElement(SettingsRegister, {}))
  })
  await expect(page.locator('[data-settings-register]')).toBeVisible()
}

test('Settings › Pipeline settings groups by class: human and unclassified rows first, automatic and retiring collapsed but present and editable', async ({ page }) => {
  await mount(page)
  const sec = page.locator('[data-register-section="Provider descriptions"]')
  await expect(sec.locator('[data-register-setting="pdesc.enabled"]')).toBeVisible()
  await expect(sec.locator('[data-register-setting="batch.old_sizes"]')).toBeVisible()
  // human rows are outside any group and come first in the section
  const order = await sec.locator('[data-register-setting]').evaluateAll((els) => els.map((e) => [e.getAttribute('data-register-setting'), Boolean(e.closest('[data-control-group]'))]))
  expect(order.map((o) => o[0])).toEqual(['pdesc.enabled', 'batch.old_sizes', 'pdesc.tries', 'pdesc.max_chars', 'pdesc.legacy'])
  expect(order.map((o) => o[1])).toEqual([false, false, true, true, true])
  const auto = sec.locator('[data-control-group="automatic"]')
  const retiring = sec.locator('[data-control-group="retiring"]')
  await expect(auto.locator('summary')).toContainText('Automatically managed (software-tuned within safe limits)')
  await expect(auto.locator('summary')).toContainText('2')
  await expect(retiring.locator('summary')).toContainText('Retiring')
  expect(await auto.evaluate((e) => e.open)).toBe(false)
  expect(await retiring.evaluate((e) => e.open)).toBe(false)
  await expect(sec.locator('[data-register-setting="pdesc.tries"]')).toBeHidden()
  // opening the group shows the live value and keeps the edit-with-a-reason flow
  await auto.locator('summary').click()
  const tries = sec.locator('[data-register-setting="pdesc.tries"]')
  await expect(tries).toBeVisible()
  await expect(tries.locator('input[type=number]')).toHaveValue('10')
  expect(await tries.locator('button', { hasText: 'Save' }).count()).toBe(0)
  await tries.locator('input[type=number]').fill('12')
  await expect(tries.getByPlaceholder('Reason (kept in the log)')).toBeVisible()
  await expect(tries.locator('button', { hasText: 'Save' })).toBeDisabled()
  await tries.getByPlaceholder('Reason (kept in the log)').fill('Test reason')
  await expect(tries.locator('button', { hasText: 'Save' })).toBeEnabled()
  // the retiring group names what replaced the setting
  await retiring.locator('summary').click()
  await expect(retiring.locator('[data-replaced-by="pdesc.legacy"]')).toContainText('Replaced by pdesc.queue_cap')
})

test('a role that cannot change settings still sees every automatic value @responsive', async ({ page }) => {
  const w = page.viewportSize()?.width || 9999
  expect(w, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(PHONE_MAX)
  await mount(page, { admin: false })
  const sec = page.locator('[data-register-section="Provider descriptions"]')
  await sec.locator('[data-control-group="automatic"] summary').click()
  await expect(sec.locator('[data-register-setting="pdesc.max_chars"]')).toContainText('1,200')
  await expect(sec.locator('input[type=number]')).toHaveCount(0)
  const over = await page.evaluate(() => document.documentElement.scrollWidth - innerWidth)
  expect(over, 'the page does not scroll sideways').toBeLessThanOrEqual(1)
  const tap = await sec.locator('[data-control-group] summary').evaluateAll((els) => els.map((e) => e.getBoundingClientRect().height))
  for (const h of tap) expect(h, 'group header is a tap target').toBeGreaterThanOrEqual(24)
})
