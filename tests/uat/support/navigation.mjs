import { expect } from '@playwright/test'
import { clickPrimaryNav, DETERMINISTIC_UI_TIMEOUT } from './runtime-evidence.mjs'

const ui = { timeout: DETERMINISTIC_UI_TIMEOUT }

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

// v2.15.200 (Decision 254): Layer 2 opens on Adapters; Overview, Fetch an area, History and Source profiles are retired.
// The tabs now are Adapters and Scholarships. Source profiles moved to Scrapers & fetchers (a card, closed until opened).
export async function openLayer2Tab(page, tab) {
  await openLayer2(page)
  if (tab && tab !== 'Adapters') await page.locator('.cf-page-tabs [role="tab"]').filter({ hasText: tab }).first().click(ui)
  const workspace = tab && tab !== 'Adapters' ? page.locator('main') : page.locator('[data-adapters-workspace]')
  await expect(workspace.first()).toBeVisible(ui)
  return workspace.first()
}

export async function openLayer2(page) {
  await clickPrimaryNav(page, 'Layer 2 — Enrichment')
  const workspace = page.locator('[data-adapters-workspace]')
  await expect(workspace).toBeVisible(ui)
  // Decision 133: the screen title is the page title (Layer panels no longer repeat it).
  await expect(page.getByRole('heading', { name: 'Layer 2 Discovery & reading' }).first()).toBeVisible(ui)
  return workspace
}

// v2.15.107: former Administration tools now live on their own pages (src/nav-map.js).
const ADMIN_TOOL_ROUTES={'Extraction Profiles':['Scrapers & fetchers',''],'Scraper Config':['Scrapers & fetchers','']}
async function openAdministrationTool(page,tabName,heading){
  const [menu,tab]=ADMIN_TOOL_ROUTES[tabName]||[tabName,'']
  await clickPrimaryNav(page,menu)
  if(tab)await page.locator('.cf-page-tabs [role="tab"]').filter({hasText:tab}).first().click({timeout:DETERMINISTIC_UI_TIMEOUT})
  const headingLocator=page.getByRole('heading',{name:heading,exact:true}).first()
  await expect(headingLocator).toBeVisible(ui)
  // v2.15.200: every card is closed until opened.
  const toggle=headingLocator.locator('xpath=ancestor::*[contains(@class,"cf-card-head")]//button[contains(@class,"cf-card-toggle")]').first()
  if(await toggle.count()&&(await toggle.getAttribute('aria-expanded'))==='false')await toggle.click(ui)
  return headingLocator.locator('xpath=ancestor-or-self::*[@role="region"][1] | ancestor::section[1]').first()
}

export async function openLayer2Advanced(page) {
  return openAdministrationTool(page,'Extraction Profiles','Source profiles')
}

export async function openLayer2Providers(page) {
  // Heading renamed in the provider screen: 'Layer 2 Acquisition Providers' -> 'Acquisition providers'.
  return openAdministrationTool(page,'Scraper Config','Acquisition providers')
}

export async function openLayer2Trials(page) {
  throw new Error('Layer 2 acquisition trials are not a canonical A23 operator route; use background enrichment and governed Evidence instead.')
}

// v2.15.252 (Platform Admin, 12 Oct 2026): Layer 3 AI validation retired. Its old address opens Layer 2 › Adapters;
// this helper opens the old address and checks where it lands (the Layer 3 menu item no longer exists).
export async function openRetiredLayer3(page, address = '/#layer-3-ai') {
  await page.goto(address)
  await expect(page).toHaveURL(/#layer-2-discovery$/, ui)
  await expect(page.locator('.m-topbar h1')).toHaveText('Layer 2 Discovery & reading', ui)
  await expect(page.locator('.m-nav').getByRole('button', { name: 'Layer 3 AI validation', exact: true })).toHaveCount(0)
  return page.locator('main').first()
}

export async function openLayer3() {
  throw new Error('Layer 3 AI validation was retired in v2.15.252; use openRetiredLayer3 to check that its old address opens Layer 2 › Adapters.')
}

export async function openLayer4(page) {
  await clickPrimaryNav(page, 'Layer 4 — Human Resolution')
  const workspace = page.locator('.m23-stack').first()
  await expect(workspace.getByRole('heading', { name: 'Layer 4 status' })).toBeVisible(ui)
  return workspace
}

export async function openEvidence(page) {
  await clickPrimaryNav(page, 'Evidence')
  await expect(page.locator('.m-title-wrap h1')).toContainText(/Evidence/i, ui)
}

export async function openOnboarding(page) {
  return openAdministrationTool(page,'Onboarding','Country / Provider / Course Onboarding')
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

