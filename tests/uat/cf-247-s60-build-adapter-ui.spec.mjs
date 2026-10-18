// CF-247 (S60) v2.15.287, Decision 267: Layer 2 › Build adapter (Platform Admin 18 Oct 2026 11:58 "Keep Adapter builder too"; 14:05).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { PAGES } from '../../src/nav-map.js'

const field = (state, o = {}) => ({ state, read: 10, agree: 8, differ: 0, new: 2, read_share: 0.9, agree_share: 1, why: state === 'ready' ? 'adds 2 values the catalogue does not hold' : state === 'review' ? '3 of 10 readings differ from the catalogue' : 'not read by the adapter', admitted: false, ...o })
const LIST = { summary: { universities: 2, courses: 900, by_stage: { tested: 1, no_adapter: 1 }, ready: 4, review: 2, not_ready: 2, adds: 120 }, total: 2, limit: 50, offset: 0, can_build: true, can_admit: true,
  items: [{ provider_id: 'u-rb', name: 'Riverbend University', country: 'AU', courses: 600, pages_read: 400, ready: 4, review: 2, not_ready: 2, adds: 120, stage: 'tested', checked_at: '2026-10-18T03:00:00Z' },
          { provider_id: 'u-kc', name: 'Kestrel College', country: 'AU', courses: 300, pages_read: null, ready: null, review: null, not_ready: null, adds: null, stage: 'no_adapter' }] }
const READ = { provider_id: 'u-rb', pages_read: 400, has_adapter: true, adds: 120, min_read: 0.5, min_agree: 0.9, measured_at: '2026-10-18T03:00:00Z',
  fields: { intakes: field('ready', { admitted: true }), fee: field('ready'), english: field('review'), delivery: field('ready'), duration: field('ready'), campus: field('review'), study_level: field('not_ready', { read: 0, new: 0 }), majors: field('not_ready', { read: 0, new: 0, why: 'the adapter does not read majors yet' }) },
  ready: ['intakes', 'fee', 'delivery', 'duration'], review: ['english', 'campus'], not_ready: ['study_level', 'majors'],
  university: { name: 'Riverbend University', country: 'AU', website: 'https://riverbend.example' }, courses: 600, pages: { bound: 420, read: 400, other_course: 12, unreadable: 8 }, links_fixed: 5,
  build: { status: 'done', stop_reason: null, note: 'Done' }, ai_cost_usd: 0.04, wave: null, admitted: {}, can_build: true, can_admit: true }

async function setup(page, rank = 6) {
  await mockAdmin(page, { rank })
  const calls = []; page.buildCalls = calls
  page.on('dialog', d => d.accept(d.message().startsWith('Wave name') ? 'Wave 18' : 'Admit from the browser test'))
  await page.route('**/rest/v1/rpc/admin_adapter_build', async route => {
    const b = route.request().postDataJSON(); calls.push(b)
    const out = b.p_action === 'list' ? LIST : b.p_action === 'read' ? READ : b.p_action === 'waves' ? { waves: [{ wave: 'Wave 18', universities: 8, courses: 2941, by_stage: { tested: 6, building: 1, needs_pages: 1 }, ready: 41, review: 14, not_ready: 9, adds: 6830 }] }
      : b.p_action === 'admit' ? { admitted: [{ provider_id: 'u-rb', adapter_fields: ['delivery', 'fee'], enrich_fields: ['duration'], enrich_job: 'job-1', majors_written: null, left_for_review: ['english', 'campus'], not_ready: ['study_level', 'majors'] }] }
      : b.p_action === 'build' ? { started: 1, retried: 0, already_building: 0 } : {}
    await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(out) })
  })
}

test('the tab sits on Layer 2 beside Adapters, and the Adapter builder stays', () => {
  const keys = PAGES.layer2.tabs.map(t => t.key)
  expect(keys.slice(0, 3)).toEqual(['adapters', 'build', 'builder'])
  expect(PAGES.layer2.tabs.find(t => t.key === 'build').label).toBe('Build adapter')
})

test('browser: universities with stage and readiness; a university page admits Ready fields only, with a reason', async ({ page }) => {
  await setup(page)
  await page.goto('/#layer-2-discovery?tab=build')
  const list = page.locator('[data-build-list]')
  await expect(list.locator('[data-build-row="u-rb"]')).toContainText('Tested')
  await expect(list.locator('[data-build-row="u-rb"]')).toContainText('4 · 2 · 2')
  await expect(list.locator('[data-build-row="u-kc"]')).toContainText('Not measured')
  await expect(page.locator('[data-build-summary]')).toContainText('+120')
  await list.getByRole('button', { name: 'Riverbend University' }).click()
  const fields = page.locator('[data-build-fields]')
  await expect(fields.locator('[data-build-field="fee"]')).toContainText('Ready')
  await expect(fields.locator('[data-build-field="english"]')).toContainText('Review')
  await expect(fields.locator('[data-build-field="majors"]')).toContainText('the adapter does not read majors yet')
  await expect(fields.locator('[data-build-field="intakes"]')).toContainText('Admitted')
  const admit = page.locator('[data-build-admit]')
  await expect(admit).toHaveText('Admit 3 Ready fields') // intakes is admitted already
  await admit.click()
  await expect.poll(() => page.buildCalls.find(c => c.p_action === 'admit')?.p_args).toEqual({ provider_id: 'u-rb', reason: 'Admit from the browser test' })
  await expect(page.locator('[data-build-done]')).toContainText('Left for review: English, Campus')
})

test('browser: build picked universities into a wave; the Waves view lists waves', async ({ page }) => {
  await setup(page)
  await page.goto('/#layer-2-discovery?tab=build')
  await page.getByRole('checkbox', { name: 'Pick Kestrel College' }).check()
  await page.locator('[data-build-picked]').click()
  await expect.poll(() => page.buildCalls.find(c => c.p_action === 'build')?.p_args).toEqual({ provider_ids: ['u-kc'], reason: 'Admit from the browser test', wave: 'Wave 18' })
  await page.getByRole('tab', { name: 'Waves' }).click()
  await expect(page.locator('[data-build-wave="Wave 18"]')).toContainText('+6,830')
})

test('browser: a Curator sees readiness but no Build or Admit', async ({ page }) => {
  await setup(page, 3)
  await page.goto('/#layer-2-discovery?tab=build')
  await expect(page.locator('[data-build-row="u-rb"]')).toBeVisible()
  await expect(page.locator('[data-build-picked]')).toHaveCount(0)
  await page.getByRole('button', { name: 'Riverbend University' }).click()
  await expect(page.locator('[data-build-fields]')).toBeVisible()
  await expect(page.locator('[data-build-admit]')).toHaveCount(0)
})

test('source: one RPC, thresholds from the database, retired pieces gone', () => {
  const ui = fs.readFileSync('src/BuildAdapter.jsx', 'utf8')
  expect(ui).toContain("supabase.rpc('admin_adapter_build'")
  expect(ui).not.toMatch(/0\.9\b|0\.5\b/) // shares come from the database
  expect(fs.existsSync('src/RegulatorySettings.jsx')).toBe(false)
  expect(fs.readFileSync('index.html', 'utf8')).not.toContain('layer4-mass-operations-entry')
})
