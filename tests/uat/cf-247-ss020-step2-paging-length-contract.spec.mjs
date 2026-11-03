// Guards: Decision 269 (SS-020 step 2, Platform Admin 3 Nov 2026 22:05): the longest admin screens are paged or collapsed and no control is lost
// CF-247 SS-020 step 2. Admin docs/platform/ui-audit/2026-11-03-admin-menu-build-prompt.md step 2: Course sources (50 universities a page),
// Course entry requirements (Course-level reading 100 providers a page; the requirement list was already 50 rows a page on the server),
// Reference data (Key dates read only, edited in a drawer), Automations areas collapsed, the Layer 2/3 notice strip on Operations only.
// Layer 1 › Sources rows were already collapsed and All layers already paged on the server (50) on v2.15.444. Layer 4 › Inbox paging is
// parked: branch cf247-l4-course-link changes src/Layer4Inbox.jsx and public.admin_layer4_inbox.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const read = (p) => fs.readFileSync(p, 'utf8')

test('source shape: page sizes are screen lengths, filters return to the first page, counts still cover everything', () => {
  const cs = read('src/CourseSources.jsx')
  expect(cs).toContain('const CS_PAGE=50')
  expect(cs).toContain('useEffect(()=>setOffset(0),[q,country])')
  expect(cs).toContain("const all=d.providers||[]")
  const aer = read('src/AerWorkspace.jsx')
  expect(aer).toContain('const PROGRAMME_PAGE=100')
  expect(aer).toContain('<DataTable rows={pageRows} columns={cols} loading={!d&&!err} tableId="aer-course-programme"')
  expect(aer).toContain("options={rows.filter(r=>Number(r.remaining)>0)") // the picker still lists every provider
  const kd = read('src/KeyDates.jsx')
  expect(kd).toContain('const KD_PAGE=50')
  expect(kd).toContain('function DateDrawer(')
  const main = read('src/mature-main.jsx')
  expect(main).toContain("const notices=layerNo&&!(pageKey==='layer2'&&tab&&tab!=='operations')")
  // already aligned on v2.15.444: All layers is paged on the server, Layer 1 rows open one at a time
  expect(read('src/pipeline-ops-entry.jsx')).toContain("adminRead('pipeline_sources_page',{limit:PAGE_SIZE,offset,")
  expect(read('src/layer1-operations-entry.jsx')).toContain('openKey={open} onOpen={setOpen} dataAttr="data-l1-source"')
  // parked: the Inbox belongs to another branch in flight
  expect(read('src/Layer4Inbox.jsx')).not.toContain('SS-020')
})

test('browser: Automations areas start closed; a filter opens the matching areas; controls are inside', async ({ page }) => {
  await mockAdmin(page)
  await page.goto('/#scheduled-jobs')
  const areas = page.locator('.au-area')
  await expect(areas.first()).toBeVisible()
  await expect(page.locator('.au-area[data-area-open="yes"]')).toHaveCount(0)
  await expect(page.locator('.au-table')).toHaveCount(0)
  const first = areas.first()
  await first.locator('[data-area-toggle]').click()
  await expect(first.locator('.au-table')).toBeVisible()
  await expect(first.locator('tr[data-job]').first()).toBeVisible()
  await first.locator('[data-area-toggle]').click()
  await expect(first.locator('.au-table')).toHaveCount(0)
  await page.getByLabel('Find an automation').fill('a')
  await expect(page.locator('.au-area[data-area-open="no"]')).toHaveCount(0)
})

test('browser: Layer 2/3 notice strip only on Operations', async ({ page }) => {
  await mockAdmin(page)
  await page.goto('/#layer-2-discovery')
  await expect(page.locator('[data-layer-notices="2"]')).toBeVisible()
  for (const tab of ['enrich', 'universities', 'sources']) {
    await page.goto(`/#layer-2-discovery?tab=${tab}`)
    await expect(page.locator('.cf-page-tabs, [role="tablist"]').first()).toBeVisible()
    await expect(page.locator('[data-layer-notices="2"]')).toHaveCount(0)
  }
})

test('browser: Key dates are read only rows with Edit; the drawer holds the editors', async ({ page }) => {
  await mockAdmin(page)
  await page.goto('/#reference-data?type=dates')
  const t = page.locator('[data-key-dates]')
  await expect(t.locator('tbody tr')).toHaveCount(2)
  await expect(t.locator('select, input')).toHaveCount(0)
  await t.locator('[data-date-edit]').first().click()
  const dr = page.locator('[data-date-drawer]')
  await expect(dr.getByRole('dialog').or(dr)).toBeVisible()
  await expect(dr.locator('select')).toHaveCount(2)
  await dr.getByRole('button', { name: 'Close' }).click()
  await expect(page.locator('[data-date-drawer]')).toHaveCount(0)
})
