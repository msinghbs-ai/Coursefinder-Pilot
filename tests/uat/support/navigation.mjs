import { expect } from '@playwright/test'
import { clickPrimaryNav, DETERMINISTIC_UI_TIMEOUT } from './runtime-evidence.mjs'

const ui = { timeout: DETERMINISTIC_UI_TIMEOUT }

export async function openLayer1(page) {
  await clickPrimaryNav(page, 'Layer 1 — Operations')
  const workspace = page.locator('.l1v2-page .l1v2-shell')
  await expect(workspace).toBeVisible(ui)
  // Decision 133: the screen title is the page title (the embedded panel no longer repeats it).
  await expect(page.getByRole('heading', { name: 'Layer 1 Register' }).first()).toBeVisible(ui)
  return workspace
}

// v2.15.128: Layer 2 is split into tabs — Overview, Fetch an area, History, Source profiles.
export async function openLayer2Tab(page, tab) {
  await openLayer2(page)
  await page.locator('.cf-page-tabs [role="tab"]').filter({ hasText: tab }).first().click(ui)
  const workspace = page.locator('.l2o-shell')
  await expect(workspace).toBeVisible(ui)
  return workspace
}

export async function openLayer2(page) {
  await clickPrimaryNav(page, 'Layer 2 — Enrichment')
  const workspace = page.locator('.l2o-shell')
  await expect(workspace).toBeVisible(ui)
  // Decision 133: the screen title is the page title (Layer panels no longer repeat it).
  await expect(page.getByRole('heading', { name: 'Layer 2 Discovery & reading' }).first()).toBeVisible(ui)
  return workspace
}

// v2.15.107: former Administration tools now live on their own pages (src/nav-map.js).
const ADMIN_TOOL_ROUTES={'Extraction Profiles':['Layer 2 Discovery & reading','Source profiles'],'Scraper Config':['Scrapers & fetchers','']}
async function openAdministrationTool(page,tabName,heading){
  const [menu,tab]=ADMIN_TOOL_ROUTES[tabName]||[tabName,'']
  await clickPrimaryNav(page,menu)
  if(tab)await page.locator('.cf-page-tabs [role="tab"]').filter({hasText:tab}).first().click({timeout:DETERMINISTIC_UI_TIMEOUT})
  const headingLocator=page.getByRole('heading',{name:heading,exact:true}).first()
  await expect(headingLocator).toBeVisible(ui)
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

export async function openLayer3(page) {
  await clickPrimaryNav(page, 'Layer 3 — AI Interpretation')
  // v2.15.107: the Layer 3 operations workspace is the Work queue tab of the Layer 3 AI validation page.
  await page.locator('.cf-page-tabs [role="tab"]').filter({ hasText: 'Work queue' }).first().click(ui)
  // v2.15.127: the Work queue is Layer3Work.jsx.
  const workspace = page.locator('[data-layer3-work]').first()
  await expect(workspace.getByRole('heading', { name: 'Work by task' })).toBeVisible(ui)
  return workspace
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

export async function openScholarshipSelection(page) {
  await clickPrimaryNav(page, 'Scholarships')
  await expect(page.locator('.m-title-wrap h1')).toContainText(/Scholarships/i, ui)
  const open = page.getByRole('button', { name: 'Open Course decision support', exact: true })
  await expect(open).toBeVisible(ui)
  await open.click()
  const dialog = page.getByRole('dialog', { name: 'Scholarship Selection' })
  await expect(dialog).toBeVisible(ui)
  return dialog
}
