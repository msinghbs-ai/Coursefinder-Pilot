import fs from 'node:fs/promises'
import path from 'node:path'
import { chromium } from '@playwright/test'

const storageStatePath = path.resolve('storageState.json')

async function writeEmptyStorageState() {
  await fs.writeFile(storageStatePath, JSON.stringify({ cookies: [], origins: [] }, null, 2))
}

export default async function globalSetup() {
  const deployedBaseUrl = process.env.UAT_BASE_URL?.trim()

  // Local/contract UAT does not require authenticated deployed state. Still
  // create the configured storage-state file so the same Playwright config is
  // portable between local validation and governed deployed UAT.
  if (!deployedBaseUrl) {
    await writeEmptyStorageState()
    return
  }

  const email = process.env.UAT_EMAIL?.trim()
  const password = process.env.UAT_PASSWORD
  if (!email || !password) {
    throw new Error('Missing UAT credentials. Configure UAT_EMAIL and UAT_PASSWORD for deployed UAT.')
  }

  const loginPath = process.env.UAT_LOGIN_PATH?.trim() || '/'
  const usernameSelector = process.env.UAT_USERNAME_SELECTOR?.trim() || '#username, input[type="email"]'
  const passwordSelector = process.env.UAT_PASSWORD_SELECTOR?.trim() || '#password, input[type="password"]'
  const submitSelector = process.env.UAT_SUBMIT_SELECTOR?.trim()
  const browser = await chromium.launch()

  try {
    const context = await browser.newContext()
    const page = await context.newPage()
    const loginUrl = new URL(loginPath, `${deployedBaseUrl.replace(/\/$/, '')}/`).toString()

    await page.goto(loginUrl, { waitUntil: 'domcontentloaded', timeout: 45_000 })

    const usernameInput = page.locator(usernameSelector).first()
    const passwordInput = page.locator(passwordSelector).first()
    await usernameInput.waitFor({ state: 'visible', timeout: 45_000 })
    await usernameInput.fill(email)
    await passwordInput.fill(password)

    if (submitSelector) {
      await page.locator(submitSelector).first().click()
    } else {
      await page.getByRole('button', { name: /^sign in$/i }).click()
    }

    // Require the login form to leave the authenticated surface before
    // persisting state. Existing UAT helpers still validate role/shell readiness
    // inside each test and therefore retain the governed authority checks.
    await usernameInput.waitFor({ state: 'hidden', timeout: 45_000 })
    await context.storageState({ path: storageStatePath })
  } finally {
    await browser.close()
  }
}
