// Guards: Decision 269 (SS-020 step 4, Platform Admin 3 Nov 2026 22:05): Layer 2/3 consolidation; Progress, Build adapter and the Attributes run controls move to named homes, old addresses land there, roles unchanged
// CF-247 SS-020 step 4. Admin docs/platform/ui-audit/2026-11-03-admin-menu-build-prompt.md step 4 and review C21, C22, C24, C26, C29, C30, C31,
// C32, C9, C33: Progress → Operations (overview, journeys, every hour) and Services & limits (Firecrawl and AI today); Build adapter → a Build
// row action on Universities and step 0 of the Adapter builder; Attributes run controls → Enrich fields (Attributes read only, linking there);
// scholarship Settings and jobs → Layer 2/3 › Scholarships; review readiness → a header line on the Inbox (review pause recorded in the report).
// Controls-audit items 4, 7, 8, 9 and 10 were delivered by migration 20261103120000 (v2.15.419 to v2.15.421) and are not repeated here.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { PAGES, resolveTarget } from '../../src/nav-map.js'

const go = (addr) => { const [a, q] = addr.split('?'); const r = resolveTarget(a, new URLSearchParams(q || '')); return `${r.page}/${r.tab}${r.params.toString() ? '?' + r.params : ''}` }
const read = (p) => fs.readFileSync(p, 'utf8')

test('menu: Layer 2/3 in the approved order with its roles; Coverage keeps Courses and Attributes', () => {
  expect(PAGES.layer2.tabs.map((t) => `${t.key}:${t.min}`)).toEqual(['operations:3', 'universities:3', 'enrich:3', 'plan:3', 'builder:5', 'sources:3', 'flags:3', 'scholarships:4'])
  expect(PAGES.coverage.tabs.map((t) => `${t.key}:${t.min}`)).toEqual(['courses:1', 'attributes:1'])
})

test('LEGACY: Progress and Build adapter addresses open their new homes, with their filters', () => {
  expect(go('coverage?tab=progress')).toBe('layer2/operations')
  expect(go('coverage?tab=progress&view=journeys&stage=admit')).toBe('layer2/operations?view=journeys&stage=admit')
  expect(go('coverage?tab=progress&view=running')).toBe('jobs/tasks')
  expect(go('layer-2-discovery?tab=build')).toBe('layer2/universities')
  expect(go('layer-2-discovery?tab=build&provider=p9')).toBe('layer2/universities?build=p9')
  expect(go('scheduled-jobs?tab=priority')).toBe('layer2/universities')
})

test('source: no control drawn twice; same reads; the Inbox change is one header line', () => {
  const fc = read('src/FieldCoverage.jsx')
  expect(fc).toContain('<StalledFields scope={scope} readOnly onChanged={load} onError={onError}/>')
  expect(fc).toContain("if(part==='pdesc')return <ProviderDescriptions")
  const main = read('src/mature-main.jsx')
  expect(main).toContain('<FieldCoverage part="run" rank={rank}')
  expect(main).toContain('<Progress part="services" onError={err}/>')
  expect(main).toContain('<ScholarshipSettings rank={rank} onError={err}/>')
  expect(read('src/ScholarshipCoverage.jsx')).toContain('data-scholarship-controls-moved')
  expect(read('src/AerCoverage.jsx')).toContain('export function ReviewReadinessLine()')
  expect(read('src/Layer4Inbox.jsx').match(/SS-020/g)).toHaveLength(1)
})

test('browser: Attributes is read only and links each stalled field to Enrich fields; Enrich fields has the controls', async ({ page }) => {
  await mockAdmin(page)
  await page.goto('/#coverage?tab=attributes')
  await expect(page.locator('[data-field-coverage]').first()).toBeVisible()
  await expect(page.locator('[data-card="coverage.gap-queue"]')).toHaveCount(0)
  await expect(page.locator('[data-card="coverage.provider-descriptions"]')).toHaveCount(0)
  await page.goto('/#layer-2-discovery?tab=enrich')
  await expect(page.locator('[data-field-coverage="run"]')).toBeVisible()
  await expect(page.locator('[data-card="coverage.gap-queue"]')).toBeVisible()
  await expect(page.locator('[data-card="coverage.provider-descriptions"]')).toBeVisible()
})

test('browser: Operations shows Progress; Universities offers Build per row; Adapter builder has step 0', async ({ page }) => {
  await mockAdmin(page)
  await page.goto('/#coverage?tab=progress')
  await expect(page).toHaveURL(/#layer-2-discovery/)
  await expect(page.locator('[data-operations-progress] [data-progress-overview]')).toBeVisible()
  await page.goto('/#layer-2-discovery?tab=universities&build=p-rmit')
  await expect(page.locator('[data-uni-build-open="p-rmit"] [data-build-adapter]')).toBeVisible()
  await page.goto('/#layer-2-discovery?tab=builder')
  await expect(page.locator('[data-fold="builder-step0"] [data-build-adapter]')).toBeVisible()
  await page.goto('/#models-services')
  await expect(page.locator('[data-progress-today] [data-progress-budget]')).toBeVisible()
})
