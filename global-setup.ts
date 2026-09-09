import { writeFile } from 'node:fs/promises'
import { resolve } from 'node:path'
import { chromium, type FullConfig } from '@playwright/test'

const STORAGE_STATE_PATH = resolve('storageState.json')

function requireEnvironmentValue(name: 'UAT_USERNAME' | 'UAT_PASSWORD', fallbackName?: 'UAT_EMAIL'): string {
  const primaryValue = process.env[name]?.trim()
  const fallbackValue = fallbackName ? process.env[fallbackName]?.trim() : undefined
  const value = primaryValue || fallbackValue

  if (!value) {
    const acceptedNames = fallbackName ? `${name} or ${fallbackName}` : name
    throw new Error(`Missing required UAT credential environment variable: ${acceptedNames}`)
  }

  return value
}

async function writeAnonymousStorageState(): Promise<void> {
  await writeFile(STORAGE_STATE_PATH, JSON.stringify({ cookies: [], origins: [] }, null, 2), { encoding: 'utf8' })
}

export default async function globalSetup(_config: FullConfig): Promise<void> {
  const configuredBaseUrl = process.env.UAT_BASE_URL?.trim()

  if (!configuredBaseUrl) {
    await writeAnonymousStorageState()
    return
  }

  const username = requireEnvironmentValue('UAT_USERNAME', 'UAT_EMAIL')
  const password = requireEnvironmentValue('UAT_PASSWORD')
  const loginPath = process.env.UAT_LOGIN_PATH?.trim() || '/'
  const usernameSelector = process.env.UAT_USERNAME_SELECTOR?.trim() || '#username'
  const passwordSelector = process.env.UAT_PASSWORD_SELECTOR?.trim() || '#password'
  const submitSelector = process.env.UAT_SUBMIT_SELECTOR?.trim()
  const baseUrl = `${configuredBaseUrl.replace(/\/$/, '')}/`
  const loginUrl = new URL(loginPath, baseUrl).toString()
  const browser = await chromium.launch()

  try {
    const context = await browser.newContext()
    const page = await context.newPage()
    const usernameInput = page.locator(usernameSelector).first()
    const passwordInput = page.locator(passwordSelector).first()

    await page.goto(loginUrl, { waitUntil: 'domcontentloaded' })
    await usernameInput.fill(username)
    await passwordInput.fill(password)

    if (submitSelector) {
      await page.locator(submitSelector).first().click()
    } else {
      await page.getByRole('button', { name: /^sign in$/i }).click()
    }

    await usernameInput.waitFor({ state: 'hidden' })
    await context.storageState({ path: STORAGE_STATE_PATH })
  } finally {
    await browser.close()
  }
}
