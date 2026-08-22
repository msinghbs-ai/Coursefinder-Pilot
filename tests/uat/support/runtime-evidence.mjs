import fs from 'node:fs/promises'
import path from 'node:path'
import { expect } from '@playwright/test'

const ARTIFACT_DIR = path.resolve('uat-artifacts')

async function ensureArtifacts() {
  await fs.mkdir(ARTIFACT_DIR, { recursive: true })
}

export async function writeRunEnvironment(extra = {}) {
  await ensureArtifacts()
  const payload = {
    captured_at: new Date().toISOString(),
    base_url: process.env.UAT_BASE_URL || 'local-vite-smoke',
    github_sha: process.env.GITHUB_SHA || null,
    github_run_id: process.env.GITHUB_RUN_ID || null,
    github_run_attempt: process.env.GITHUB_RUN_ATTEMPT || null,
    ...extra,
  }
  await fs.writeFile(path.join(ARTIFACT_DIR, 'environment.json'), JSON.stringify(payload, null, 2))
}

function governedOperation(request) {
  try {
    if (!request.url().includes('/rest/v1/rpc/admin_read')) return null
    const body = request.postDataJSON()
    return typeof body?.p_operation === 'string' ? body.p_operation : null
  } catch {
    return null
  }
}

function responseEvidence(response) {
  const request = response.request()
  return {
    status: response.status(),
    url: response.url(),
    method: request.method(),
    operation: governedOperation(request),
  }
}

export function observeRuntime(page) {
  const serverErrors = []
  const clientErrors = []
  const consoleErrors = []

  page.on('response', response => {
    const status = response.status()
    if (status >= 500) serverErrors.push(responseEvidence(response))
    else if (status >= 400) clientErrors.push(responseEvidence(response))
  })

  page.on('console', message => {
    if (message.type() === 'error') consoleErrors.push({ text: message.text(), location: message.location() })
  })

  page.on('pageerror', error => {
    consoleErrors.push({ text: error.message, stack: error.stack || null, page_error: true })
  })

  return { serverErrors, clientErrors, consoleErrors }
}

export async function attachRuntimeEvidence(testInfo, runtime) {
  await ensureArtifacts()
  const safeTitle = testInfo.title.replace(/[^a-z0-9]+/gi, '-').replace(/^-|-$/g, '').toLowerCase()
  const payload = {
    test: testInfo.title,
    project: testInfo.project.name,
    status_at_capture: testInfo.status,
    expected_status: testInfo.expectedStatus,
    final_status_source: 'Playwright JSON/JUnit report and GitHub job/commit status',
    server_errors: runtime.serverErrors,
    client_errors: runtime.clientErrors,
    console_errors: runtime.consoleErrors,
  }
  const filePath = path.join(ARTIFACT_DIR, `${safeTitle || 'test'}-runtime.json`)
  await fs.writeFile(filePath, JSON.stringify(payload, null, 2))
  await testInfo.attach('runtime-evidence', { path: filePath, contentType: 'application/json' })
}

export function assertNoServerErrors(runtime) {
  expect(runtime.serverErrors, `Unexpected HTTP 5xx responses: ${JSON.stringify(runtime.serverErrors)}`).toEqual([])
}

export async function milestoneScreenshot(page, testInfo, name, options = {}) {
  await ensureArtifacts()
  const safeName = name.replace(/[^a-z0-9]+/gi, '-').replace(/^-|-$/g, '').toLowerCase()
  const filePath = path.join(ARTIFACT_DIR, `${testInfo.project.name}-${safeName}.png`)
  await page.screenshot({ path: filePath, fullPage: options.fullPage ?? true })
  await testInfo.attach(name, { path: filePath, contentType: 'image/png' })
  return filePath
}

export async function loginAsUatUser(page) {
  const email = process.env.UAT_EMAIL?.trim()
  const password = process.env.UAT_PASSWORD
  if (!email || !password) throw new Error('Missing UAT_EMAIL/UAT_PASSWORD. Configure repository Actions secrets COURSEFINDER_UAT_EMAIL and COURSEFINDER_UAT_PASSWORD.')

  await page.goto('/')

  const emailInput = page.locator('input[type="email"]').first()
  if (await emailInput.isVisible().catch(() => false)) {
    await emailInput.fill(email)
    await page.locator('input[type="password"]').first().fill(password)
    await page.getByRole('button', { name: /^sign in$/i }).click()
    await expect(emailInput).toBeHidden({ timeout: 45_000 })
  }
}

export async function openDataQuality(page) {
  const nav = page.locator('button.m-nav-item').filter({ hasText: 'Completeness' })
  if (await nav.isVisible().catch(() => false)) {
    await nav.click()
  } else {
    await page.evaluate(() => { location.hash = '#data-quality-readiness' })
  }
  await expect(page.getByRole('heading', { name: 'Data Quality & Readiness' })).toBeVisible({ timeout: 45_000 })
  await expect(page.getByText('No composite completeness score', { exact: true })).toBeVisible()
}

export async function openRegulatoryFeeSourceNull(page, expected) {
  const card = page.locator('section.dq-domain-card').filter({ has: page.getByRole('heading', { name: 'Regulatory fee', exact: true }) })
  await expect(card).toBeVisible()
  await expect(card.getByTitle(`Present: ${expected.present.toLocaleString('en-US')}`)).toBeVisible()
  await expect(card.getByTitle(`Source-null: ${expected.source_null.toLocaleString('en-US')}`)).toBeVisible()
  await expect(card.getByTitle(`Not applicable: ${expected.not_applicable.toLocaleString('en-US')}`)).toBeVisible()
  await expect(card.getByTitle(`Zero: ${expected.zero.toLocaleString('en-US')}`)).toBeVisible()
  await expect(card.getByText(`${expected.readiness_pct.toFixed(2)}%`, { exact: true })).toBeVisible()
  await card.getByTitle(`Source-null: ${expected.source_null.toLocaleString('en-US')}`).click()
  await expect(page.getByRole('heading', { name: 'Exceptions & decision context' })).toBeVisible()
  await expect(page.getByText(`${expected.source_null.toLocaleString('en-US')} records`, { exact: true })).toBeVisible()
}
