// v2.15.107 admin simplification: one menu map, one page layout, old links redirect,
// Platform health, Layer 3 tabs and sources side by side. Source checks plus a mocked browser run
// against the local dev server (no real backend).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { PAGES, SECTIONS, LEGACY, LEGACY_ADMIN_SECTIONS, resolveTarget, hrefFor, effectiveTab, canOpen } from '../../src/nav-map.js'
import { mockAdmin } from './support/admin-mock.mjs'

const read = p => fs.readFileSync(p, 'utf8')

test('menu map: five plain sections, every page reachable, old addresses and names redirect', () => {
  expect(SECTIONS.map(s => s.label)).toEqual(['', 'Catalogue', 'Data pipeline', 'Operations', 'Platform settings', 'Administration'])
  expect(SECTIONS.find(s => s.label === 'Catalogue').pages).toContain('contacts')
  expect(SECTIONS.find(s => s.label === 'Administration').pages).toEqual(['users'])
  const inMenu = SECTIONS.flatMap(s => s.pages)
  expect(new Set(inMenu).size).toBe(inMenu.length)
  expect(Object.keys(PAGES).sort()).toEqual([...inMenu].sort())
  // Every old menu entry, hidden route and alias.
  const old = { 'dashboard': 'dashboard', 'providers': 'providers', 'courses': 'courses', 'campuses': 'providers', 'scholarships': 'scholarships', 'provider-contacts': 'contacts', 'layer-1-operations': 'layer1', 'layer-2-enrichment': 'layer2', 'layer-3-ai-interpretation': 'layer3', 'layer-4-human-resolution': 'layer4', 'jobs-schedules': 'jobs', 'evidence': 'evidence', 'completeness': 'coverage', 'data-quality-readiness': 'coverage', 'course-coverage': 'coverage', 'statistics-rankings': 'rankings', 'compare': 'rankings', 'administration': 'scrapers', 'outcomes-qilt': 'rankings', 'student-flow-prisms': 'rankings', 'sources': 'sources', 'attributes': 'dataModel', 'settings': 'health', 'onboarding': 'providers', 'jobs': 'jobs', 'scheduled-tasks': 'jobs', 'important-links': 'reference', 'important-dates': 'reference', 'review-queue': 'layer4', 'refresh-scheduling': 'jobs', 'layer-1-regulatory': 'layer1', 'layer-1-authority': 'layer1', 'layer-2-operations': 'layer2', 'layer-3-ai': 'layer3', 'layer-4-review': 'layer4', 'users-roles': 'users' }
  for (const [slug, page] of Object.entries(old)) expect(resolveTarget(slug).page, slug).toBe(page)
  // Old menu labels passed to navigate().
  for (const [label, page] of [['Layer 4 — Human Resolution', 'layer4'], ['Statistics & Rankings', 'rankings'], ['Outcomes (QILT)', 'rankings'], ['Provider Contacts', 'contacts'], ['Jobs', 'jobs'], ['Compare', 'rankings'], ['Evidence', 'evidence']]) expect(resolveTarget(label).page, label).toBe(page)
  for (const [section, page] of Object.entries({ 'sources-imports': 'reference', 'layer1-sources': 'layer1', 'layer2-providers': 'scrapers', 'provider-assets': 'providers', 'layer2-sources': 'layer2', 'onboarding': 'providers', 'pim': 'dataModel', 'users-roles': 'users', 'environment-migration': 'environment', 'platform': 'health', 'statistics-datasets': 'rankings' })) {
    const r = resolveTarget('administration', new URLSearchParams({ section, system: 'the_wur' }))
    expect(r.page, section).toBe(page)
    expect(r.params.get('section')).toBeNull()
    expect(r.params.get('system')).toBe('the_wur')
  }
  expect(Object.keys(LEGACY_ADMIN_SECTIONS).length).toBeGreaterThanOrEqual(11)
  expect(Object.keys(LEGACY).length).toBeGreaterThanOrEqual(25)
  expect(resolveTarget('layer-3-ai', new URLSearchParams({ tab: 'models' })).page).toBe('services')
  expect(hrefFor('layer3', 'routing')).toBe('#layer-3-ai')
})

test('role gates are unchanged from the screens they came from', () => {
  const min = (p, t) => PAGES[p].tabs ? PAGES[p].tabs.find(x => x.key === t).min : PAGES[p].min
  expect([min('layer1', 'operations'), min('layer1', 'settings'), min('layer2', 'operations'), min('layer3', 'routing'), min('layer4', 'review'), min('jobs', 'jobs'), min('evidence')]).toEqual([4, 6, 4, 3, 3, 4, 3])
  expect([min('users'), min('environment'), min('migration'), min('layer1', 'batch'), min('dataModel'), min('scrapers'), min('health', 'readiness')]).toEqual([6, 6, 6, 6, 5, 4, 6])
  expect(canOpen('users', 5)).toBe(false)
  // v2.15.112: Key dates and Key links moved to Reference data, Onboarding to Providers (still rank 3)
  expect(canOpen('layer1', 3)).toBe(false)
  expect(canOpen('reference', 3)).toBe(true)
  expect(effectiveTab('reference', 'imports', 3)).toBe('dates')
  expect(PAGES.providers.tabs.find(t => t.key === 'onboarding').min).toBe(3)
  for (const tab of ['imports', 'dates', 'links', 'onboarding']) expect(resolveTarget('layer-1-register', new URLSearchParams({ tab })).page).toBe(tab === 'onboarding' ? 'providers' : 'reference')
})

test('no screen draws its own shell; one layout in the kit', () => {
  const kit = read('src/ui-kit.jsx'), html = read('index.html'), dq = read('src/data-quality-entry.jsx'), main = read('src/mature-main.jsx')
  for (const c of ['export function PageHeader', 'export function PageTabs', 'export function PageLayout', 'export function StatusDot']) expect(kit).toContain(c)
  expect(html).not.toContain('data-quality-root')
  expect(html).not.toContain('data-quality-entry')
  expect(dq).not.toContain('dq-shell')
  expect(dq).not.toContain('createRoot')
  expect(main).toContain('<PageLayout tabs={tabs} active={tab} onTab={onTab}')
  expect(main).not.toContain('m-admin-subnav')
  expect(main).not.toContain('m-subtabs')
  expect(fs.existsSync('src/layer2-navigation-restore.js')).toBe(false)
})

test('new reads: guarded, read-only, granted to signed-in users only', () => {
  const m = read('supabase/migrations/20260930000000_cf247_admin_ui_reads.sql')
  expect(m).toContain("raise exception 'cf247_admin_ui_reads: a function with one of these names already exists")
  expect(m).not.toMatch(/create or replace function/i)
  expect(m).not.toMatch(/\b(insert|update|delete)\s+(into|from)?\s*(pipeline|catalogue|scholarship)\./i)
  expect(m).toContain("security.current_role_rank() < 3")
  expect(m).toContain("revoke all on function public.admin_source_comparison(text,uuid) from public, anon;")
  expect(m).toContain("(to_jsonb(pr)->>'retired_at') is not null")
  expect(read('src/Layer3Operations.jsx')).toContain("supabase.rpc('admin_layer3_control_read'")
  expect(read('src/SourceComparison.jsx')).toContain("supabase.rpc('admin_source_comparison'")
})

test.describe('mocked browser', () => {
  test('Coverage & completeness renders inside the app shell and the old address redirects', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#data-quality-readiness')
    await expect(page).toHaveURL(/#coverage\?tab=attributes$/)
    await expect(page.locator('.m-sidebar')).toBeVisible()
    await expect(page.locator('.dq-shell')).toHaveCount(0)
    await expect(page.locator('.m-topbar h1')).toHaveText('Coverage & completeness')
    await expect(page.getByRole('tab', { name: 'Attributes' })).toHaveAttribute('aria-selected', 'true')
    await expect(page.getByText('By area: providers, courses, campuses and scholarships')).toBeVisible()
    await page.getByRole('tab', { name: 'Courses' }).click()
    await expect(page).toHaveURL(/#coverage$/)
    await expect(page.getByText('Course completeness score').first()).toBeVisible()
    await expect(page.getByText('Completeness by attribute')).toHaveCount(0)
    await page.getByRole('tab', { name: 'Attributes' }).click()
    await expect(page).toHaveURL(/#coverage\?tab=attributes$/)
    await expect(page.getByText('Completeness by attribute')).toBeVisible()
    await expect(page.getByText('Coverage by pipeline stage')).toBeVisible()
    await expect(page.getByText('Course completeness score')).toHaveCount(0)
  })

  test('Platform health shows status, issues, checks and history; dot in the top bar', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#platform-health')
    await expect(page.getByRole('heading', { name: 'Needs attention' })).toBeVisible()
    await expect(page.getByText('Open issues')).toBeVisible()
    await expect(page.locator('.ph-checks tbody tr')).toHaveCount(8)
    await expect(page.locator('.ph-day')).toHaveCount(14)
    await expect(page.locator('.cf-health-link .cf-status-dot.tone-warning')).toBeVisible()
  })

  test('Platform health says "not available yet" when the checks are not deployed', async ({ page }) => {
    await mockAdmin(page, { healthMissing: true })
    await page.goto('/#platform-health')
    await expect(page.getByRole('heading', { name: 'Health checks not available yet' })).toBeVisible()
  })

  test('Layer 3 control: tasks, cascade in order, controls, models only qualified', async ({ page }) => {
    await mockAdmin(page)
    page.on('dialog', d => d.accept())
    await page.goto('/#layer-3-ai')
    await expect(page.getByRole('tab', { name: 'Control' })).toBeVisible()
    await expect(page.getByRole('tab', { name: 'Test results' })).toHaveCount(0)
    const english = page.locator('.l3c-task', { hasText: 'English requirements' })
    await expect(english.locator('tbody tr')).toHaveCount(3)
    await expect(english.locator('tbody tr').nth(1).locator('.l3v-model')).toHaveAttribute('title', 'mistralai/mistral-small-3.2-24b-instruct')
    await expect(english.locator('tbody tr').nth(1)).toContainText('Mistral Small 3.2 24b')
    await expect(page.locator('.l3c-task', { hasText: 'Intakes' }).locator('tbody tr').nth(1).locator('.l3v-model')).toHaveAttribute('title', 'anthropic/claude-haiku-4.5')
    await expect(page.locator('.l3c-task', { hasText: 'Tuition' })).toContainText('Paused')
    await english.getByRole('button', { name: 'Move mistralai/mistral-small-3.2-24b-instruct up' }).click()
    await expect.poll(() => page.l3calls.map(c => c.p_action)).toContain('tier_move')
    await english.locator('.l3c-add select').selectOption('openrouter-english-l3c-gemini-2-5-flash-lite-v1')
    await english.getByRole('button', { name: 'Add as last step' }).click()
    await expect.poll(() => page.l3calls.map(c => c.p_action)).toContain('tier_add')
    await page.getByRole('button', { name: 'Pause all' }).click()
    await expect.poll(() => page.l3calls.map(c => c.p_action)).toContain('run_all')
    // v2.15.122: the Models tab moved to Platform settings › Models & services.
    await expect(page.getByRole('tab', { name: 'Models' })).toHaveCount(0)
  })

  test('Layer 4 flagged values: tuition recorded as per year can be confirmed, edited or removed', async ({ page }) => {
    await mockAdmin(page)
    page.on('dialog', d => d.accept())
    await page.goto('/#layer-4-review?tab=flags')
    await expect(page.getByRole('tab', { name: 'Flagged values' })).toHaveAttribute('aria-selected', 'true')
    await expect(page.locator('tbody tr')).toHaveCount(2)
    await expect(page.getByText('estimated 1st year indicative fee AUD $54,750')).toBeVisible()
    await page.getByRole('button', { name: 'Confirm per year' }).first().click()
    await expect.poll(() => page.l3calls.map(c => c.p_action)).toContain('confirm')
    await page.getByRole('button', { name: 'Edit fee' }).first().click()
    await page.getByLabel('Fee amount').fill('40000')
    await page.getByLabel('Fee period').selectOption('total_indicative')
    await page.getByRole('button', { name: 'Save' }).click()
    await expect.poll(() => page.l3calls.find(c => c.p_action === 'correct')?.p_args).toEqual({ amount: 40000, basis: 'total_indicative' })
  })

  test('scholarship and course detail show both sources and highlight differences', async ({ page }) => {
    await mockAdmin(page, { courseDiffers: true })
    await page.goto('/#scholarships?id=5f92fc8c-ad2b-5182-a3b7-2e9bba5b3d99')
    const s = page.locator('[data-source-comparison="scholarship"]')
    await expect(s.locator('thead th', { hasText: 'Government (Study Australia)' })).toBeVisible()
    await expect(s.locator('tr[data-compare-state="differs"]')).toHaveCount(2)
    await expect(s.locator('tr[data-compare-state="same"]')).toHaveCount(1)
    await page.goto('/#courses?id=0b1fb6d4-c02f-47c7-98d0-9f0d57240fd5')
    const c = page.locator('[data-source-comparison="course"]')
    await expect(c.locator('thead th', { hasText: 'Regulator (CRICOS)' })).toBeVisible()
    await expect(c.locator('tr.cf-diff')).toHaveCount(1)
    await expect(c.getByText('Provider page is A$1,920 higher a year.')).toBeVisible()
  })
})
