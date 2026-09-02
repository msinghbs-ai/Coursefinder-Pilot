import { expect } from '@playwright/test'
import { clickPrimaryNav, DETERMINISTIC_UI_TIMEOUT } from './runtime-evidence.mjs'

const ui = { timeout: DETERMINISTIC_UI_TIMEOUT }

export async function openLayer1(page) {
  await clickPrimaryNav(page, 'Layer 1 — Authority')
  const workspace = page.locator('.l1v2-page .l1v2-shell')
  await expect(workspace).toBeVisible(ui)
  await expect(workspace.getByRole('heading', { name: 'Layer 1 — Authority & Statistical Ingestion' })).toBeVisible(ui)
  return workspace
}

export async function openLayer2(page) {
  await clickPrimaryNav(page, 'Layer 2 — Enrichment')
  const workspace = page.locator('.l2o-shell')
  await expect(workspace).toBeVisible(ui)
  await expect(workspace.getByRole('heading', { name: 'Layer 2 — Enrichment' })).toBeVisible(ui)
  return workspace
}

async function openAdministrationTool(page,tabName,heading){
  await clickPrimaryNav(page,'Administration')
  await expect(page.getByRole('heading',{name:'Administration overview',exact:true})).toBeVisible(ui)
  const tab=page.getByRole('tab',{name:tabName,exact:true})
  await expect(tab).toBeVisible(ui)
  await tab.click({timeout:DETERMINISTIC_UI_TIMEOUT})
  const headingLocator=page.getByRole('heading',{name:heading,exact:true}).first()
  await expect(headingLocator).toBeVisible(ui)
  return headingLocator.locator('xpath=ancestor-or-self::*[@role="region"][1] | ancestor::section[1]').first()
}

export async function openLayer2Advanced(page) {
  return openAdministrationTool(page,'Layer 2 sources','Enrichment Source Configuration')
}

export async function openLayer2Providers(page) {
  return openAdministrationTool(page,'Acquisition','Layer 2 Acquisition Providers')
}

export async function openLayer2Trials(page) {
  throw new Error('Layer 2 acquisition trials are not a canonical A23 operator route; use background enrichment and governed Evidence instead.')
}

export async function openLayer3(page) {
  await clickPrimaryNav(page, 'Layer 3 — AI Interpretation')
  const workspace = page.locator('.m23-stack').first()
  await expect(workspace.getByRole('heading', { name: 'Layer 3 status' })).toBeVisible(ui)
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
