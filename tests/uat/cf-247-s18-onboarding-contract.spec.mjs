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
  expect(main).toContain("const ProviderOnboarding=lazyPage(()=>import('./ProviderOnboarding'))")
  expect(main).toContain("if(tab==='onboarding')return <ProviderOnboarding rank={rank} actorId={actorId} onError={err}/>")
  expect(main).toContain("<CreditBanner rank={rank} canOpenServices={canOpen('services',rank)}/>")
  for (const gone of ['ProviderOnboardingNotice', 'Layer4Attributes', 'FlaggedValues', 'FeeRules', 'ScholarshipPublishing', 'view="blocks"']) expect(main).not.toContain(gone)
  for (const f of ['src/FlaggedValues.jsx', 'src/FeeRules.jsx', 'src/ScholarshipPublishing.jsx', 'src/layer2-provider-onboarding.jsx']) expect(fs.existsSync(f)).toBe(false)
  expect(read('src/platform-maturity-entry.jsx')).not.toContain('BlockConsole')
  expect(PAGES.layer4.tabs.map(t => t.key)).toEqual(['review', 'aireview', 'websites'])
  const ob = read('src/ProviderOnboarding.jsx')
  expect(ob).toContain("supabase.rpc('admin_provider_onboarding'")
  expect(ob).not.toContain('admin_uni_adapter_control') // admitting stays on Layer 2 › Adapters
  expect(ob).toContain('setInterval(load,30000)')
  const builder = read('src/AdapterBuilderTab.jsx')
  expect(builder).toContain('<FeeSchedules provider={provider}/><ProviderPolicies provider={provider}/>')
  const banner = read('src/CreditBanner.jsx')
  expect(banner).toContain("supabase.rpc('admin_credit_notices')")
  expect(banner).toContain('setInterval(read,300000)')
  expect(banner).not.toMatch(/localStorage|sessionStorage/)
  expect(read('src/admin-pages.css')).toMatch(/@media \(prefers-reduced-motion:reduce\)\{\.cf-credit-banner \.cf-credit-items\{animation:none/)
})

test('old Layer 4 addresses lead to where the work now happens', () => {
  for (const t of ['flags', 'rules', 'blocks']) expect(resolveTarget('layer-4-review', new URLSearchParams(`tab=${t}`))).toMatchObject({ page: 'layer4', tab: 'review' })
  expect(resolveTarget('layer-4-review', new URLSearchParams('tab=attributes'))).toMatchObject({ page: 'layer2', tab: 'onboarding' }) // v2.15.258
  expect(resolveTarget('layer-4-review', new URLSearchParams('tab=publishing'))).toMatchObject({ page: 'scholarships', tab: 'coverage' })
  expect(resolveTarget('scholarships', new URLSearchParams('tab=publishing'))).toMatchObject({ page: 'scholarships', tab: 'coverage' })
})

test.describe('mocked browser', () => {
  test('Onboarding shows the tiles and a stopped row with its note and what to do', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#providers?tab=onboarding')
    const ob = page.locator('[data-provider-onboarding]')
    await expect(ob).toContainText("Admitting is a person's step on Layer 2 › Adapters")
    await expect(ob.locator('[data-onboarding-tile="queued"]')).toContainText('1,100')
    await expect(ob.locator('[data-onboarding-tile="active"]')).toContainText('30')
    await expect(ob.locator('[data-onboarding-tile="stopped"]')).toContainText('No website: 1')
    await expect(ob.locator('[data-onboarding-tile="waiting_admit"]')).toContainText('1')
    await expect(ob.locator('[data-onboarding-tile="without"]')).toContainText('1,153')
    await expect(ob.locator('[data-onboarding-tile="approvals"]')).toHaveAttribute('href', '#layer-2-discovery?tab=builder')
    const rows = ob.locator('[data-onboarding-row]')
    await expect(rows).toHaveCount(6)
    await expect(rows.first()).toHaveAttribute('data-status', 'stopped') // stopped rows first
    const stopped = ob.locator('[data-onboarding-row="ob-2"]')
    await expect(stopped).toContainText('Stopped')
    await expect(stopped).toContainText('No website could be found and verified')
    await expect(stopped.locator('[data-stop-help]')).toContainText('Enter the website in the Adapter builder (1.1)')
    await expect(stopped.getByRole('link', { name: 'Kaplan Business School' })).toHaveAttribute('href', '#layer-2-discovery?tab=builder&provider=pv-ob-2')
    const ready = ob.locator('[data-onboarding-row="ob-3"]')
    await expect(ready).toContainText('Ready to admit')
    await expect(ready).toContainText('Intakes')
    await expect(ready.locator('[data-held="fee"]')).toContainText('agrees on under 90%')
    await expect(ob.locator('[data-onboarding-auto]')).toBeVisible()
    // the stopped filter asks the server for stopped rows only
    await ob.locator('[data-onboarding-filter="stopped"]').click()
    await expect(rows).toHaveCount(2)
    await expect.poll(() => page.l3calls.some(c => c.onboarding === 'read' && c.args?.status === 'stopped')).toBe(true)
    // approvals across universities
    await ob.locator('[data-onboarding-approvals] > summary').click()
    await expect(ob.locator('[data-onboarding-approvals] [data-fee-schedules]')).toBeVisible()
    await expect(ob.locator('[data-onboarding-approvals] [data-provider-policies]')).toBeVisible()
  })

  test('Retry selected asks for a reason and sends the ticked stopped rows', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#providers?tab=onboarding')
    const ob = page.locator('[data-provider-onboarding]')
    await ob.getByLabel('Tick Kaplan Business School').check()
    await ob.getByLabel('Tick Southern Cross University').check() // in progress: can be stopped, not retried
    await expect(ob.locator('[data-po-action="retry"]')).toHaveText('Retry selected (1)')
    await expect(ob.locator('[data-po-action="stop"]')).toHaveText('Stop selected (2)')
    await ob.locator('[data-po-action="retry"]').click()
    const confirm = ob.locator('[data-po-confirm="retry"]')
    await expect(confirm).toBeDisabled()
    await ob.getByLabel('Reason: Retry selected (1)').fill('Website entered by hand')
    await confirm.click()
    await expect.poll(() => page.l3calls.find(c => c.onboarding === 'retry')?.args).toEqual({ ids: ['ob-2'], reason: 'Website entered by hand' })
    await expect(ob.locator('[data-onboarding-note]')).toContainText('Retrying 1')
  })

  test('a Curator sees the list without the Platform Admin controls', async ({ page }) => {
    await mockAdmin(page, { rank: 3 })
    await page.goto('/#providers?tab=onboarding')
    const ob = page.locator('[data-provider-onboarding]')
    await expect(ob.locator('[data-onboarding-row]')).toHaveCount(6)
    await expect(ob.locator('[data-onboarding-actions]')).toHaveCount(0)
    await expect(ob.locator('[data-onboarding-settings]')).toHaveCount(0)
  })

  test('old Layer 4 addresses open the review queue, Providers › Onboarding and Scholarships › Coverage', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#layer-4-review?tab=flags')
    await expect(page).toHaveURL(/#layer-4-review$/)
    await expect(page.getByRole('tab', { name: 'Review queue' })).toHaveAttribute('aria-selected', 'true')
    await expect(page.getByRole('tab', { name: 'Flagged values' })).toHaveCount(0)
    await page.goto('/#layer-4-review?tab=attributes')
    await expect(page).toHaveURL(/#layer-2-discovery\?tab=onboarding$/) // v2.15.258: Onboarding is on Layer 2
    await expect(page.locator('[data-provider-onboarding]')).toBeVisible()
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
