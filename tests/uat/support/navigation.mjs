import { expect } from '@playwright/test'
import { clickPrimaryNav, DETERMINISTIC_UI_TIMEOUT } from './runtime-evidence.mjs'

const ui = { timeout: DETERMINISTIC_UI_TIMEOUT }

export async function openLayer1(page) {
  await clickPrimaryNav(page, 'Layer 1 — Authority')
  const workspace = page.locator('.l1o-page .l1o-shell')
  await expect(workspace).toBeVisible(ui)
  await expect(workspace.getByRole('heading', { name: 'Layer 1 — Regulatory' })).toBeVisible(ui)
  return workspace
}

export async function openLayer2(page) {
  await clickPrimaryNav(page, 'Layer 2 — Enrichment')
  const workspace = page.locator('.l2o-shell')
  await expect(workspace).toBeVisible(ui)
  await expect(workspace.getByRole('heading', { name: 'Layer 2 — Enrichment' })).toBeVisible(ui)
  return workspace
}

async function openAdministrationTool(page,title,heading){
  await clickPrimaryNav(page,'Administration')
  const card=page.locator('.m-attention').filter({hasText:title}).first()
  await expect(card).toBeVisible(ui)
  await card.getByRole('button',{name:'Open',exact:true}).click({timeout:DETERMINISTIC_UI_TIMEOUT})
  const workspace=page.getByRole('region').filter({has:page.getByRole('heading',{name:heading,exact:true})}).first()
  await expect(workspace).toBeVisible(ui)
  return workspace
}

export async function openLayer2Advanced(page) {
  return openAdministrationTool(page,'Layer 2 source profiles','Enrichment Source Configuration')
}

export async function openLayer2Providers(page) {
  return openAdministrationTool(page,'Layer 2 acquisition providers','Layer 2 Acquisition Providers')
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
  return openM23(page, 'Onboarding', 'Onboarding')
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
  await clickPrimaryNav(page, 'Scholarship Selection')
  const dialog = page.getByRole('dialog', { name: 'Scholarship Selection' })
  await expect(dialog).toBeVisible(ui)
  return dialog
}
