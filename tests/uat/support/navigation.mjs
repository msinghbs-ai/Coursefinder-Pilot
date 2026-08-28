import { expect } from '@playwright/test'
import { clickPrimaryNav, DETERMINISTIC_UI_TIMEOUT } from './runtime-evidence.mjs'

const ui = { timeout: DETERMINISTIC_UI_TIMEOUT }

async function openM23(page, navLabel, tabLabel) {
  await clickPrimaryNav(page, navLabel)
  const dialog = page.getByRole('dialog', { name: 'M2.3 Intelligence' })
  await expect(dialog).toBeVisible(ui)
  await expect(dialog.getByRole('button', { name: tabLabel, exact: true })).toHaveClass(/active/, ui)
  return dialog
}

export async function openLayer1(page) {
  await clickPrimaryNav(page, 'Layer 1 — Regulatory')
  const dialog = page.getByRole('dialog', { name: 'Layer 1 — Regulatory' })
  await expect(dialog).toBeVisible(ui)
  await expect(dialog.getByRole('heading', { name: 'Layer 1 — Regulatory' })).toBeVisible(ui)
  return dialog
}

export async function openLayer2(page) {
  await clickPrimaryNav(page, 'Layer 2 — Enrichment')
  const dialog = page.getByRole('dialog', { name: 'Layer 2 Operations' })
  await expect(dialog).toBeVisible(ui)
  return dialog
}

export async function openLayer2Advanced(page) {
  const dialog = await openLayer2(page)
  await dialog.getByRole('button', { name: /Advanced configuration/i }).click({ timeout: DETERMINISTIC_UI_TIMEOUT })
  await expect(dialog).toBeHidden(ui)
  await expect(page.getByRole('heading', { name: 'Enrichment Source Configuration' })).toBeVisible(ui)
}

export async function openLayer2Providers(page) {
  const dialog = await openLayer2(page)
  await dialog.getByRole('button', { name: /Advanced configuration/i }).click({ timeout: DETERMINISTIC_UI_TIMEOUT })
  await expect(dialog).toBeHidden(ui)
  const providerButton = page.getByRole('button', { name: 'Acquisition providers', exact: true })
  await expect(providerButton).toBeVisible(ui)
  await providerButton.click({ timeout: DETERMINISTIC_UI_TIMEOUT })
  await expect(page.getByRole('heading', { name: 'Layer 2 Acquisition Providers' })).toBeVisible(ui)
}

export async function openLayer2Trials(page) {
  const dialog = await openLayer2(page)
  await dialog.getByRole('button', { name: /Run bounded trial/i }).click({ timeout: DETERMINISTIC_UI_TIMEOUT })
  await expect(dialog).toBeHidden(ui)
  await expect(page.getByRole('heading', { name: 'Acquisition & Course Completeness Trials' })).toBeVisible(ui)
}

export async function openLayer3(page) {
  return openM23(page, 'Layer 3 — AI Interpretation', 'Layer 3')
}

export async function openLayer4(page) {
  return openM23(page, 'Layer 4 — Human Resolution', 'Layer 4')
}

export async function openEvidence(page) {
  await clickPrimaryNav(page, 'Evidence & Provenance')
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
