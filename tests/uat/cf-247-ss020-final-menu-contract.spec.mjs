// Guards: Decision 269 (SS-020, Platform Admin 3 Nov 2026 22:05): the admin menu ends at 47 tabs, every old address of a merged or moved tab opens its new home, and each moved section keeps its minimum role
// CF-247 SS-020 step 5 and the programme's end state. Step 5: Rankings › Outcomes (QILT) and Student flow (PRISMS) are "View data" on
// Rankings › Datasets (C16, C17, C18), the Overview cards link there. The Final board names 22 pages; the menu has 20 (the board's own page
// table lists 20; recorded with the Integration Controller as a count error). Link refresh → Settings (C20, C42) is parked: DECISION REQUIRED.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { PAGES, resolveTarget } from '../../src/nav-map.js'

const go = (addr) => { const [a, q] = addr.split('?'); const r = resolveTarget(a, new URLSearchParams(q || '')); return `${r.page}/${r.tab}${r.params.toString() ? '?' + r.params : ''}` }

test('the menu: 47 tabs on 20 pages, as the Final board', () => {
  expect(Object.values(PAGES).reduce((n, p) => n + (p.tabs ? p.tabs.length : 1), 0)).toBe(47)
  expect(Object.keys(PAGES)).toHaveLength(20)
  expect(PAGES.rankings.tabs.map((t) => `${t.key}:${t.min}`)).toEqual(['overview:1', 'compare:1', 'datasets:1'])
})

test('every old address of a tab SS-020 merged or moved opens its new home', () => {
  const cases = {
    'statistics-rankings?tab=qilt': 'rankings/datasets?data=qilt', 'statistics-rankings?tab=prisms': 'rankings/datasets?data=prisms',
    'outcomes-qilt': 'rankings/datasets?data=qilt', 'student-flow-prisms': 'rankings/datasets?data=prisms',
    'coverage?tab=progress': 'layer2/operations', 'layer-2-discovery?tab=build': 'layer2/universities',
    'platform-health?tab=queues': 'health/queues', 'platform-health?tab=integration&view=yield': 'health/queues',
    'models-services?tab=limits': 'services/services', 'models-services?tab=fetchers': 'services/services', 'scrapers-fetchers': 'services/services',
  }
  for (const [from, to] of Object.entries(cases)) expect(go(from), from).toBe(to)
})

test('Datasets: the QILT and PRISMS data open for every role; the dataset register and imports stay Pipeline Operator and above', () => {
  const main = fs.readFileSync('src/mature-main.jsx', 'utf8')
  expect(main).toContain('{rank>=4&&<StatisticsDatasets rank={rank} onView={view}/>}{rank>=4&&<section data-ranking-imports>')
  expect(main).toContain("{data==='qilt'&&<section data-dataset-view=\"qilt\"><Qilt onError={onError}/></section>}")
  expect(main).not.toContain("navigate('Outcomes (QILT)')")
})

test('browser: a Viewer opens QILT data from Datasets; the register is not shown to them', async ({ page }) => {
  await mockAdmin(page, { rank: 1 })
  await page.goto('/#statistics-rankings?tab=qilt')
  await expect(page).toHaveURL(/tab=datasets/)
  await expect(page.locator('[data-dataset-view="qilt"]')).toBeVisible()
  await expect(page.locator('[data-ranking-imports]')).toHaveCount(0)
  await page.getByRole('button', { name: 'View data: PRISMS student flow' }).click()
  await expect(page.locator('[data-dataset-view="prisms"]')).toBeVisible()
})
