import { test } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
const src = fs.readFileSync('tests/uat/cf-247-s650-coverage-now-contract.spec.mjs', 'utf8')
const pre = src.slice(src.indexOf("const day ="), src.indexOf("test.describe('mocked browser'"))
const T = new Function(pre + '; return T')()
for (const [name, w, h] of [['desktop', 1366, 900], ['phone', 412, 900]]) {
  test(`shot ${name}`, async ({ page }) => {
    await page.setViewportSize({ width: w, height: h })
    await mockAdmin(page)
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_coverage_telemetry_v1', (r) => r.fulfill({ json: T }))
    await page.goto('/#coverage')
    await page.waitForSelector('[data-coverage-telemetry]')
    await page.waitForTimeout(800)
    await page.screenshot({ path: `/tmp/shots/coverage-${name}.png`, fullPage: true })
    const ov = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
    console.log(name, 'overflowX', ov)
  })
}
