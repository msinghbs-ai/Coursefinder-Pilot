// CF-247 v2.15.275 (S37): Platform Admin, 14 Oct 2026 12:04: "make sure all config and limits can be controlled through UI ... maintain
// stats and telemetry. raise and use the scraper and AI accordingly."
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const read = f => fs.readFileSync(f, 'utf8')
const mig = read('supabase/migrations/20261014013800_cf247_enrich_controls_and_telemetry.sql')
const worker = read('supabase/functions/coverage-sweep/index.ts')

test('worker values are settings; the worker reads them; nothing fixed in the enrich step', () => {
  expect(mig).toContain("('pipeline', 'enrich.page_chars', 'Enrich fields: page text the AI reads'")
  expect(mig).toContain("('pipeline', 'enrich.title_batch', 'Enrich fields: titles in one AI call'")
  expect(mig).toContain("or (s.toolset_key = 'pipeline' and s.key like 'enrich.%'));")
  expect(worker).toContain('const PAGE_CHARS = wsNum("enrich.page_chars", 24000), TITLE_BATCH = wsNum("enrich.title_batch", 20);')
  const seg = worker.slice(worker.indexOf('if (mode === "enrich_ai") {'), worker.indexOf('if (mode === "scholarship_inspect") {'))
  expect(seg).not.toMatch(/\.slice\(0, (24000|16000|20000)\)/)
  expect(seg).not.toContain('b += 20')
})

test('stats: hourly coverage snapshot (catalogued job), telemetry and the limits in force', () => {
  expect(mig).toContain("select cron.schedule('enrich-coverage-snapshot', '7 * * * *', 'select security.enrich_coverage_snapshot_v1()');")
  expect(mig).toContain("values ('enrich-coverage-snapshot', 'Reports', 50, 'Field coverage snapshot',")
  expect(mig).toContain("elsif p_action = 'stats' then")
  expect(mig).toContain("'ai_guard_usd', (select (value #>> '{}')::numeric from pipeline.platform_toolset_settings where toolset_key = 'openrouter' and key = 'guard_enrich_fields')")
  expect(mig).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

test.describe('mocked browser', () => {
  test('Coverage and telemetry card shows shares, movement, the last 24 hours and where limits are changed', async ({ page }) => {
    await mockAdmin(page)
    const stats = { snapshot_at: '2026-10-14T02:07:00Z', first_snapshot_at: '2026-10-14T01:20:00Z',
      coverage: [{ country: 'NZ', field: 'duration', courses: 6474, filled: 2000, first: 1500, day_ago: 1400 }],
      last_24h: { last_hour: 3200, filled: 9000, ai_calls: 400, ai_failed: 2, ai_cost_usd: 6.5, scraper_credits: 40, pages_requested: 120 },
      limits: { model: 'openai/gpt-4.1-mini', ai_guard_usd: 25, ai_spent_today_usd: 6.5, openrouter_mode: 'observe', calls_at_once: 6, items_per_call: 30, items_a_minute: 400, campus_min_pages: 2, scraper_share: 1000, reads_share: 3000 } }
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_enrich_fields', async route => {
      const b = route.request().postDataJSON() || {}
      const r = b.p_action === 'stats' ? stats : b.p_action === 'fields' ? { fields: [{ field: 'duration', label: 'Duration', allowed: ['adapter'] }], rules: [], countries: ['NZ'], can_start: true } : b.p_action === 'jobs' ? { jobs: [] } : {}
      return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(r) })
    })
    await page.goto('/#layer-2-discovery?tab=enrich')
    const card = page.locator('[data-enrich-telemetry]')
    await card.locator('.cf-card-toggle').click()
    await expect(card.locator('[data-coverage-row="NZ:duration"]')).toContainText('31%')
    await expect(card.locator('[data-coverage-row="NZ:duration"]')).toContainText('+500')
    await expect(card.locator('[data-enrich-last24]')).toContainText('3,200')
    await expect(card.locator('[data-enrich-limits]')).toContainText('AI daily guard US$25')
    await expect(card.locator('[data-enrich-limits]')).toContainText('Settings › Pipeline settings')
  })
})
