// v2.15.253 (Platform Admin, 12 Oct 2026): universities are onboarded automatically up to Ready to admit (admitting stays a person's
// step); central page approvals moved to the Adapter builder (1.3) and Providers › Onboarding; Layer 4 Flagged values, Fee rules,
// Attributes, Scholarship publishing and Blocks retired; a credit and limit banner on every page.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { creditNoticesCritical } from './support/admin-fixtures.mjs'
import { PAGES, resolveTarget } from '../../src/nav-map.js'

const read = p => fs.readFileSync(p, 'utf8')

test('migration: the onboarding table, tick, stop at Ready to admit, no auto-admit, new-provider trigger, credit notices, catalogued cron', () => {
  const m = read('supabase/migrations/20261012010200_cf247_provider_onboarding.sql')
  expect(m).toContain('create table if not exists pipeline.provider_onboarding (')
  expect(m).toContain('create table if not exists pipeline.provider_onboarding_settings (')
  expect(m).toContain('create or replace function security.provider_onboarding_tick_v1()')
  expect(m).toContain("update pipeline.provider_onboarding set status = 'waiting_admit'")
  expect(m).toContain('A Platform Admin admits')
  // a passing check never admits by itself
  expect(m).not.toContain('admin_uni_adapter_control')
  expect(m).not.toMatch(/\badmit\s*=\s*true\b/i)
  expect(m).not.toMatch(/'admit'\s*,\s*true/i)
  expect(m).toContain('create or replace trigger providers_onboarding_new after insert on catalogue.providers')
  expect(m).toContain('create or replace function public.admin_credit_notices()')
  expect(m).toContain('revoke all on function public.admin_credit_notices() from public, anon;')
  expect(m).toContain("select cron.schedule('provider-onboarding'")
  expect(m).toMatch(/insert into pipeline\.automation_catalogue\(jobname[^)]*\)\s*values \('provider-onboarding'/)
  // nothing is dropped, deleted or truncated (the foreign key's "on delete cascade" is not a statement)
  expect(m).not.toMatch(/^\s*(drop|truncate)\b/im)
  expect(m).not.toMatch(/\bdelete\s+from\b/i)
  expect(m).not.toMatch(/\btruncate\b/i)
  expect(m).not.toMatch(/\bdrop\s+(table|function|trigger|index|view|schema|column)\b/i)
  expect(fs.existsSync('supabase/migrations/20261012010300_cf247_provider_onboarding_tick_fix.sql')).toBe(true)
})

test('source: Onboarding component, builder approvals, Layer 4 retirements, banner', () => {
  const main = read('src/mature-main.jsx')
  // v2.15.300: the Onboarding list retired into Layer 2/3 › Universities (each university) and Operations (stages, settings, approvals)
  expect(main).not.toContain("const ProviderOnboarding=lazyPage(()=>import('./ProviderOnboarding'))")
  expect(main).toContain("if(tab==='universities')return <AdaptersWorkspace merged rank={rank} actorId={actorId} onError={err} routeParams={routeParams}/>")
  expect(main).toContain("<CreditBanner rank={rank} canOpenServices={canOpen('services',rank)}/>")
  for (const gone of ['ProviderOnboardingNotice', 'Layer4Attributes', 'FlaggedValues', 'FeeRules', 'ScholarshipPublishing', 'view="blocks"']) expect(main).not.toContain(gone)
  for (const f of ['src/FlaggedValues.jsx', 'src/FeeRules.jsx', 'src/ScholarshipPublishing.jsx', 'src/layer2-provider-onboarding.jsx']) expect(fs.existsSync(f)).toBe(false)
  expect(read('src/platform-maturity-entry.jsx')).not.toContain('BlockConsole')
  expect(PAGES.layer4.tabs.map(t => t.key)).toEqual(['inbox']) // v2.15.298: Inbox first; v2.15.300: the old tabs are Inbox kinds
  const ob = read('src/ProviderOnboarding.jsx')
  expect(ob).toContain("supabase.rpc('admin_provider_onboarding'")
  expect(ob).not.toContain('admin_uni_adapter_control') // admitting stays on Layer 2 › Adapters
  expect(ob).not.toContain('export default function ProviderOnboarding') // v2.15.300
  expect(read('src/Layer23Operations.jsx')).toContain("supabase.rpc('admin_provider_onboarding',{p_action:'read'")
  const builder = read('src/AdapterBuilderTab.jsx')
  expect(builder).toContain('<FeeSchedules provider={provider}/><ProviderPolicies provider={provider}/>')
  const banner = read('src/CreditBanner.jsx')
  expect(banner).toContain("supabase.rpc('admin_credit_notices')")
  expect(banner).toContain('setInterval(read,300000)')
  expect(banner).not.toMatch(/localStorage|sessionStorage/)
  expect(read('src/admin-pages.css')).toMatch(/@media \(prefers-reduced-motion:reduce\)\{\.cf-credit-banner \.cf-credit-items\{animation:none/)
})

test('old Layer 4 addresses lead to where the work now happens', () => {
  // v2.15.300: the Review queue retired; its old addresses open the Inbox on course links, Attributes on central pages to approve
  for (const t of ['flags', 'rules', 'blocks', 'review']) { const r = resolveTarget('layer-4-review', new URLSearchParams(`tab=${t}`)); expect(r).toMatchObject({ page: 'layer4', tab: 'inbox' }); expect(r.params.get('kind')).toBe('course_link') }
  expect(resolveTarget('layer-4-review', new URLSearchParams('tab=attributes')).params.get('kind')).toBe('central_to_approve')
  expect(resolveTarget('layer-4-review', new URLSearchParams('tab=publishing'))).toMatchObject({ page: 'scholarships', tab: 'coverage' })
  expect(resolveTarget('scholarships', new URLSearchParams('tab=publishing'))).toMatchObject({ page: 'scholarships', tab: 'coverage' })
})

test.describe('mocked browser', () => {
  // v2.15.300 (Platform Admin, 20 Oct 2026, Layer 2/3 "Operations first"): the Onboarding list's parts moved to Operations and Universities
  test('Operations: stages with what is stopped for a person (each kind opens the Inbox), the pace, and approvals across universities', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#providers?tab=onboarding')
    await expect(page).toHaveURL(/layer-2-discovery\?tab=universities/)
    await page.goto('/#layer-2-discovery')
    const op = page.locator('[data-layer23-operations]')
    await expect(op.locator('[data-layer23-stage]')).toHaveCount(5)
    await expect(op.locator('[data-layer23-stage="adapter"] [data-layer23-kind="nothing_ready"]')).toHaveAttribute('href', '#layer-4-review?kind=nothing_ready')
    await expect(op.locator('[data-layer23-stage="adapter"]')).toContainText('305')
    await expect(op.locator('[data-layer23-enrich-review]')).toContainText('634 Enrich fields values to review')
    await expect(op.locator('[data-layer23-pace]')).toContainText('20 universities finished a stage in the last hour')
    await expect(op.locator('[data-po-action="start-all"]')).toContainText('Onboard universities not yet queued (0)')
    await op.locator('[data-onboarding-approvals] > summary').click()
    await expect(op.locator('[data-onboarding-approvals] [data-fee-schedules]')).toBeVisible()
    await expect(op.locator('[data-onboarding-approvals] [data-provider-policies]')).toBeVisible()
  })

  test('Universities: a stopped university says why and what to do; Retry asks for a reason; the journey opens in the row', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#layer-2-discovery?tab=universities')
    const w = page.locator('[data-adapters-workspace]')
    await w.getByRole('combobox', { name: 'Journey stage' }).selectOption('person')
    await expect(w.locator('[data-adapter-row]')).toHaveCount(1)
    const row = w.locator('[data-adapter-row="u1"]')
    await expect(row.locator('[data-uni-stage]')).toContainText('Needs a person')
    await row.locator('.adp-row-head .adp-row-name').click()
    const ob = row.locator('[data-uni-onboarding="u1"]')
    await expect(ob.locator('[data-uni-stop-help]')).toContainText('mark the values on the sample pages')
    await ob.locator('[data-po-action="uni-retry"]').click()
    await expect(ob.locator('[data-po-confirm="uni-retry"]')).toBeDisabled()
    await ob.getByLabel('Reason: Retry from the step that stopped').fill('Patterns fixed in the builder')
    await ob.locator('[data-po-confirm="uni-retry"]').click()
    await expect.poll(() => page.l3calls.find(c => c.onboarding === 'retry')?.args).toEqual({ ids: ['ob-1'], reason: 'Patterns fixed in the builder' })
    await expect(ob.locator('[data-onboarding-journey="ob-1"]')).toContainText('AI attempts in this onboarding')
  })

  test('a Curator sees the universities in onboarding without Retry, Stop or settings', async ({ page }) => {
    await mockAdmin(page, { rank: 3 })
    await page.goto('/#layer-2-discovery?tab=universities')
    const w = page.locator('[data-adapters-workspace]')
    await expect(w.locator('[data-adapter-row]').first()).toBeVisible()
    await page.goto('/#layer-2-discovery')
    await expect(page.locator('[data-layer23-operations]')).toBeVisible()
    await expect(page.locator('[data-layer23-onboarding]')).toHaveCount(0)
    await expect(page.locator('[data-onboarding-settings]')).toHaveCount(0)
  })

  test('old Layer 4 addresses open the Inbox on their kind and Scholarships › Coverage', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#layer-4-review?tab=flags')
    await expect(page).toHaveURL(/#layer-4-review\?kind=course_link$/)
    await expect(page.getByRole('tab', { name: 'Flagged values' })).toHaveCount(0)
    await page.goto('/#layer-4-review?tab=attributes')
    await expect(page).toHaveURL(/#layer-4-review\?kind=central_to_approve$/)
    await page.goto('/#layer-4-review?tab=publishing')
    await expect(page).toHaveURL(/#scholarships\?tab=coverage$/)
    await expect(page.getByRole('tab', { name: 'Coverage' })).toHaveAttribute('aria-selected', 'true')
  })

  test('the Adapter builder shows the university\'s approvals in step 1.3', async ({ page }) => {
    await mockAdmin(page)
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_adapter_builder_basics', r => r.fulfill({ json: { provider_id: 'p-acu', name: 'Australian Catholic University', country: 'AU', courses: 152, website: 'https://www.acu.edu.au', can_manage: true, central: [], suggested: [], pages: { read: 0 } } }))
    await page.goto('/#layer-2-discovery?tab=builder&provider=p-acu')
    const approvals = page.locator('[data-builder-step="1.3"] [data-builder-approvals]')
    await expect(approvals.locator('[data-fee-schedules]')).toContainText('Australian Catholic University')
    await expect(approvals.locator('[data-fee-schedules] [data-doc]')).toHaveCount(1) // only this university's schedules
    await expect(approvals.locator('[data-provider-policies]')).toBeVisible()
  })

  test('no banner when all is fine', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#dashboard')
    await expect(page.locator('[data-waiting]')).toBeVisible()
    await expect(page.locator('[data-credit-banner]')).toHaveCount(0)
  })

  test('the credit banner shows a critical notice when the server reports one', async ({ page }) => {
    await mockAdmin(page, { creditNotices: creditNoticesCritical })
    await page.goto('/#dashboard')
    const b = page.locator('[data-credit-banner]')
    await expect(b).toHaveAttribute('data-credit-banner', 'critical')
    await expect(b).toHaveClass(/tone-danger/)
    await expect(b.locator('[data-credit-notice="critical"]')).toContainText('Firecrawl: Firecrawl credits: 180 left')
    await expect(b.locator('[data-credit-notice="warning"]')).toContainText('OpenRouter:')
    await expect(b.getByRole('link', { name: 'Models & services' })).toHaveAttribute('href', '#models-services?tab=limits')
    await b.getByRole('button', { name: /Hide the credit notices/ }).click()
    await expect(page.locator('[data-credit-banner]')).toHaveCount(0)
    await page.goto('/#providers') // stays hidden for the rest of the session
    await expect(page.locator('[data-credit-banner]')).toHaveCount(0)
  })
})
