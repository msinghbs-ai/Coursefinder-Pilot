import { expect } from '@playwright/test'
import { clickPrimaryNav, DETERMINISTIC_UI_TIMEOUT } from './runtime-evidence.mjs'

const ui = { timeout: DETERMINISTIC_UI_TIMEOUT }
// Workspaces drawn from a data read (Universities: admin_layer23 'universities', about 0.6 MB; Fetchers: the provider registry) appear
// only when the read returns, so they get the data-load timeout rather than the 6-second UI timeout.
const data = { timeout: 30_000 }
// When a read-driven workspace does not appear, say where the page was (address, selected tab, title, any alert) so a deployed run's
// annotation shows the cause without the trace.
async function visibleOrExplain(locator, page, what) {
  try { await expect(locator).toBeVisible(data) } catch (e) {
    const where = await page.evaluate(() => ({ hash: location.hash, tab: [...document.querySelectorAll('.cf-page-tabs [role="tab"][aria-selected="true"]')].map(x => x.textContent.trim()).join('|'), h1: document.querySelector('.m-topbar h1')?.textContent, alert: [...document.querySelectorAll('[role="alert"],.m-alert,.fr-error')].map(x => x.textContent.trim().slice(0, 160)).join(' | '), loading: document.querySelectorAll('.m-loader,.m-spinner,.m-drawer-loading').length, main: (document.querySelector('.m-main')?.innerText || '').replace(/\s+/g, ' ').slice(0, 400) })).catch(() => ({}))
    throw new Error(`${what} did not appear: ${JSON.stringify(where)}\n${e.message}`)
  }
}

export async function openLayer1(page) {
  await clickPrimaryNav(page, 'Layer 1 — Operations')
  // v2.15.246 (bugs 11/10-3, Feature 2): Layer 1 › Sources is one list with expandable rows
  const workspace = page.locator('[data-l1-sources]')
  await expect(workspace).toBeVisible(ui)
  await expect(workspace.locator('[data-l1-source]').first()).toBeVisible(ui)
  // Decision 133: the screen title is the page title (the embedded panel no longer repeats it).
  await expect(page.getByRole('heading', { name: 'Layer 1 Register' }).first()).toBeVisible(ui)
  return workspace
}

// v2.15.300 (Platform Admin, 20 Oct 2026, "Operations first"): Layer 2 is Layer 2/3 Build & enrich. It opens on Operations; the old
// Adapters and Onboarding tabs are one Universities tab (data-adapters-workspace), and every old Adapters address opens it (src/nav-map.js).
// 'Adapters' is accepted as the old name of Universities so the specs keep reading as they were written.
export async function openLayer2Tab(page, tab) {
  if (!tab || tab === 'Adapters' || tab === 'Universities') return openLayer2(page)
  await clickPrimaryNav(page, 'Layer 2/3 Build & enrich')
  await page.locator('.cf-page-tabs [role="tab"]').filter({ hasText: tab }).first().click(ui)
  const workspace = page.locator('main').first()
  await expect(workspace).toBeVisible(ui)
  return workspace
}

export async function openLayer2(page) {
  await clickPrimaryNav(page, 'Layer 2 — Enrichment')
  const workspace = page.locator('[data-adapters-workspace]')
  await visibleOrExplain(workspace, page, 'Layer 2/3 › Universities')
  // Decision 133: the screen title is the page title (Layer panels no longer repeat it).
  await expect(page.getByRole('heading', { name: 'Layer 2/3 Build & enrich' }).first()).toBeVisible(ui)
  return workspace
}

// v2.15.107: former Administration tools now live on their own pages (src/nav-map.js).
// v2.15.300 (Platform Admin, 20 Oct 2026): Scrapers & fetchers is Models & services › Fetchers (old addresses redirect).
// Clean-up batch 2 (9 Oct 2026): Source profiles were retired; the acquisition provider registry stays on Fetchers.
async function openFetchersCard(page,heading){
  await clickPrimaryNav(page,'Scrapers & fetchers')
  const headingLocator=page.getByRole('heading',{name:heading,exact:true}).first()
  await visibleOrExplain(headingLocator, page, `Fetchers › ${heading}`)
  return headingLocator.locator('xpath=ancestor-or-self::*[@role="region"][1] | ancestor::section[1]').first()
}

export async function openLayer2Providers(page) {
  // Heading renamed in the provider screen: 'Layer 2 Acquisition Providers' -> 'Acquisition providers'.
  return openFetchersCard(page,'Acquisition providers')
}

export async function openLayer2Trials(page) {
  throw new Error('Layer 2 acquisition trials are not a canonical A23 operator route; use background enrichment and governed Evidence instead.')
}

// v2.15.252 (Platform Admin, 12 Oct 2026): Layer 3 AI validation retired. Its old address opens Layer 2 › Adapters, which is
// Layer 2/3 › Universities since v2.15.300 (resolveTarget: legacyL3 → layer2, tab universities);
// this helper opens the old address and checks where it lands (the Layer 3 menu item no longer exists).
export async function openRetiredLayer3(page, address = '/#layer-3-ai') {
  await page.goto(address)
  await expect(page).toHaveURL(/#layer-2-discovery\?tab=universities$/, ui)
  await expect(page.locator('.m-topbar h1')).toHaveText('Layer 2/3 Build & enrich', ui)
  await expect(page.locator('[data-adapters-workspace]')).toBeVisible(data)
  await expect(page.locator('.m-nav').getByRole('button', { name: 'Layer 3 AI validation', exact: true })).toHaveCount(0)
  return page.locator('main').first()
}

export async function openLayer3() {
  throw new Error('Layer 3 AI validation was retired in v2.15.252; use openRetiredLayer3 to check that its old address opens Layer 2 › Adapters.')
}

// v2.15.298 / v2.15.300 (Platform Admin, 20 Oct 2026): Layer 4 Review is one Inbox (data-l4-inbox); the old Layer 4 status panel and
// tabs are retired into Inbox kinds.
export async function openLayer4(page) {
  await clickPrimaryNav(page, 'Layer 4 — Human Resolution')
  await expect(page.locator('.m-topbar h1')).toHaveText('Layer 4 Review', ui)
  const workspace = page.locator('[data-l4-inbox]').first()
  await expect(workspace).toBeVisible({ timeout: 20_000 })
  return workspace
}

export async function openEvidence(page) {
  await clickPrimaryNav(page, 'Evidence')
  await expect(page.locator('.m-title-wrap h1')).toContainText(/Evidence/i, ui)
}

export async function openGuides(page) {
  await clickPrimaryNav(page, 'Guides & Runbooks')
  const dialog = page.getByRole('dialog', { name: 'Guides & Runbooks' })
  await expect(dialog).toBeVisible(ui)
  return dialog
}

export async function openGovernanceProvider(page) {
  await clickPrimaryNav(page, 'Layer 3 Provider')
  const dialog = page.getByRole('dialog', { name: 'Layer 3 provider credential' })
  await expect(dialog).toBeVisible(ui)
  return dialog
}

