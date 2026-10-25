// Guards: CF-247 admin simplify: v2.15.107 admin simplification: one menu map, one page layout, old links redirect, Platform health, Layer 3 tabs and sources side by side.
// v2.15.107 admin simplification: one menu map, one page layout, old links redirect,
// Platform health, Layer 3 tabs and sources side by side. Source checks plus a mocked browser run
// against the local dev server (no real backend).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { PAGES, SECTIONS, LEGACY, LEGACY_ADMIN_SECTIONS, resolveTarget, hrefFor, effectiveTab, canOpen } from '../../src/nav-map.js'
import { mockAdmin } from './support/admin-mock.mjs'

const read = p => fs.readFileSync(p, 'utf8')

test('menu map: five plain sections, every page reachable, old addresses and names redirect', () => {
  expect(SECTIONS.map(s => s.label)).toEqual(['', 'Catalogue', 'Data pipeline', 'Operations', 'Platform settings', 'Administration', 'Guides'])
  expect(SECTIONS.find(s => s.label === 'Catalogue').pages).toContain('contacts')
  expect(SECTIONS.find(s => s.label === 'Administration').pages).toEqual(['users'])
  const inMenu = SECTIONS.flatMap(s => s.pages)
  expect(new Set(inMenu).size).toBe(inMenu.length)
  expect(Object.keys(PAGES).sort()).toEqual([...inMenu].sort())
  // Every old menu entry, hidden route and alias.
  const old = { 'dashboard': 'dashboard', 'providers': 'providers', 'courses': 'courses', 'campuses': 'providers', 'scholarships': 'scholarships', 'provider-contacts': 'contacts', 'layer-1-operations': 'layer1', 'layer-2-enrichment': 'layer2', 'layer-3-ai-interpretation': 'layer2', 'layer-4-human-resolution': 'layer4', 'jobs-schedules': 'jobs', 'evidence': 'evidence', 'completeness': 'coverage', 'data-quality-readiness': 'coverage', 'course-coverage': 'coverage', 'statistics-rankings': 'rankings', 'compare': 'rankings', 'administration': 'services', 'outcomes-qilt': 'rankings', 'student-flow-prisms': 'rankings', 'sources': 'layer1', 'attributes': 'coverage', 'settings': 'migration', 'onboarding': 'layer2', 'jobs': 'jobs', 'scheduled-tasks': 'jobs', 'important-links': 'reference', 'important-dates': 'reference', 'review-queue': 'layer4', 'refresh-scheduling': 'jobs', 'layer-1-regulatory': 'layer1', 'layer-1-authority': 'layer1', 'layer-2-operations': 'layer2', 'layer-3-ai': 'layer2', 'layer-4-review': 'layer4', 'users-roles': 'users' }
  for (const [slug, page] of Object.entries(old)) expect(resolveTarget(slug).page, slug).toBe(page)
  // Old menu labels passed to navigate().
  for (const [label, page] of [['Layer 4 — Human Resolution', 'layer4'], ['Statistics & Rankings', 'rankings'], ['Outcomes (QILT)', 'rankings'], ['Provider Contacts', 'contacts'], ['Jobs', 'jobs'], ['Compare', 'rankings'], ['Evidence', 'evidence']]) expect(resolveTarget(label).page, label).toBe(page)
  for (const [section, page] of Object.entries({ 'sources-imports': 'rankings', 'layer1-sources': 'layer1', 'layer2-providers': 'services', 'provider-assets': 'providers', 'layer2-sources': 'layer2', 'onboarding': 'layer2', 'pim': 'coverage', 'users-roles': 'users', 'environment-migration': 'environment', 'platform': 'migration', 'statistics-datasets': 'rankings' })) {
    const r = resolveTarget('administration', new URLSearchParams({ section, system: 'the_wur' }))
    expect(r.page, section).toBe(page)
    expect(r.params.get('section')).toBeNull()
    expect(r.params.get('system')).toBe('the_wur')
  }
  expect(Object.keys(LEGACY_ADMIN_SECTIONS).length).toBeGreaterThanOrEqual(11)
  expect(Object.keys(LEGACY).length).toBeGreaterThanOrEqual(25)
  expect(resolveTarget('layer-3-ai', new URLSearchParams({ tab: 'models' })).page).toBe('services')
  // v2.15.252 (Platform Admin, 12 Oct 2026): Layer 3 retired; its old addresses open Layer 2 › Adapters.
  expect(PAGES.layer3).toBeUndefined()
  // v2.15.300: Layer 2/3 › Universities replaces Adapters; Operations is the first tab
  for (const tab of ['routing', 'work', 'scholarships', '']) expect(resolveTarget('layer-3-ai', new URLSearchParams(tab ? { tab } : {}))).toMatchObject({ page: 'layer2', tab: 'universities' })
  expect(hrefFor('layer2', 'operations')).toBe('#layer-2-discovery')
})

test('role gates are unchanged from the screens they came from', () => {
  const min = (p, t) => PAGES[p].tabs ? PAGES[p].tabs.find(x => x.key === t).min : PAGES[p].min
  // v2.15.300: Universities opens to Curators (they saw Onboarding); the adapter detail inside a row stays Operator and above (admin_adapters)
  // v2.15.301 (menu review): Layer 1 is one Sources page (rank 4, as both before); Scholarships (was Layer 1, rank 4) is Layer 2/3 › Scholarships (rank 4);
  // API usage (rank 4) is Settings › API usage; Storage & retention (rank 6) is Platform health › Storage; Capacity (rank 6) is on the Go-live checklist (rank 6);
  // Scholarship extraction (rank 3) is on Models & services › AI (now rank 3; the AI configuration inside stays rank 4)
  expect([min('layer1'), min('layer2', 'scholarships') + 2, min('layer2', 'universities'), min('layer4', 'inbox'), min('jobs', 'jobs'), min('evidence')]).toEqual([4, 6, 3, 3, 4, 3])
  expect([min('users'), min('environment', 'settings'), min('migration'), 6, min('environment', 'api'), min('services', 'fetchers'), min('health', 'storage'), min('services', 'ai'), min('layer2', 'flags')]).toEqual([6, 6, 6, 6, 4, 4, 6, 3, 3])
  expect(canOpen('users', 5)).toBe(false)
  // v2.15.112: Key dates and Key links moved to Reference data, Onboarding to Providers (still rank 3)
  expect(canOpen('layer1', 3)).toBe(false)
  expect(canOpen('reference', 3)).toBe(true)
  expect(resolveTarget('reference-data', new URLSearchParams({ tab: 'imports' }))).toMatchObject({ page: 'rankings', tab: 'datasets' }) // v2.15.301
  expect(PAGES.layer2.tabs.find(t => t.key === 'universities').min).toBe(3) // v2.15.258: Onboarding moved to Layer 2, same role gate; v2.15.300: Universities
  for (const tab of ['imports', 'dates', 'links', 'onboarding']) expect(resolveTarget('layer-1-register', new URLSearchParams({ tab })).page).toBe(tab === 'onboarding' ? 'layer2' : tab === 'imports' ? 'rankings' : 'reference')
  expect(resolveTarget('layer-1-register', new URLSearchParams({ tab: 'dates' })).params.get('type')).toBe('dates')
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
  const m = read('supabase/migrations-archive/20260930000000_cf247_admin_ui_reads.sql')
  expect(m).toContain("raise exception 'cf247_admin_ui_reads: a function with one of these names already exists")
  expect(m).not.toMatch(/create or replace function/i)
  expect(m).not.toMatch(/\b(insert|update|delete)\s+(into|from)?\s*(pipeline|catalogue|scholarship)\./i)
  expect(m).toContain("security.current_role_rank() < 3")
  expect(m).toContain("revoke all on function public.admin_source_comparison(text,uuid) from public, anon;")
  expect(m).toContain("(to_jsonb(pr)->>'retired_at') is not null")
  // v2.15.252: Layer3Operations.jsx (the admin_layer3_control_read reader) was deleted with Layer 3.
  expect(fs.existsSync('src/Layer3Operations.jsx')).toBe(false)
  expect(fs.existsSync('src/SourceComparison.jsx')).toBe(false) // v2.15.243: Study Australia comparison retired (country-neutral)
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
    await expect(page.getByRole('heading', { name: 'Some checks need attention' })).toBeVisible() // UI audit Phase 1: the heading does not repeat the health dot's sentence
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

  // v2.15.252 (Platform Admin, 12 Oct 2026): Layer 3 Control retired; the old address opens Layer 2 › Adapters.
  test('old Layer 3 address opens Layer 2/3 › Universities', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#layer-3-ai')
    await expect(page.locator('.m-topbar h1')).toHaveText('Layer 2/3 Build & enrich')
    await expect(page.getByRole('tab', { name: 'Universities' })).toHaveAttribute('aria-selected', 'true')
    await expect(page.getByRole('tab', { name: 'Control' })).toHaveCount(0)
  })

  // v2.15.253 (Platform Admin, 12 Oct 2026): Layer 4 › Flagged values retired; its old address opens the Review queue (cf-247-s18-onboarding-contract).
  test('scholarship detail opens on the record with no government comparison; course detail on its values', async ({ page }) => {
    await mockAdmin(page, { courseDiffers: true })
    await page.goto('/#scholarships?id=5f92fc8c-ad2b-5182-a3b7-2e9bba5b3d99')
    // v2.15.243 (Platform Admin, 11 Oct 2026): the Study Australia comparison is retired; the record has the Evidence & extraction journey
    await expect(page.locator('[data-scholarship-record]')).toBeVisible()
    await expect(page.locator('[data-sr-compare]')).toHaveCount(0)
    // v2.15.159 (Platform Admin, 3 Oct 2026): the course drawer no longer carries the comparison strip; it opens on the
    // course's values with their Change buttons. The strip stays on the scholarship drawer.
    await page.goto('/#courses?id=0b1fb6d4-c02f-47c7-98d0-9f0d57240fd5')
    await expect(page.locator('[data-source-comparison="course"]')).toHaveCount(0)
    const panel = page.locator('[data-editor="course"]')
    await expect(panel).toContainText('Course values')
    await expect(panel.getByRole('button', { name: 'Change Tuition from the course page (international)' })).toBeVisible()
  })
})
