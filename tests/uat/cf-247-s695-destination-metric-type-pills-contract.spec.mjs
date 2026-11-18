// Guards: Metric type filter pills on Destination data › City metrics & costs (Platform Admin 18 Nov 2026 21:23): All, Climate & Weather (BOM), Population & Demographics (ABS), Careers, Jobs & Salaries (JSA), Study Rules & Living Costs (Home Affairs); city figures filter by category, careers and study rules show their own lists in place, living-cost figures sit beside the rules.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { routeCorrelated } from './support/correlated-fixtures.mjs'
import { METRIC_TYPES, metricTypeOf, filterMetrics, countByType } from '../../src/lib/destination-metric-types.js'

const LABELS = ['All', 'Climate & Weather (BOM)', 'Population & Demographics (ABS)', 'Careers, Jobs & Salaries (JSA)', 'Study Rules & Living Costs (Home Affairs)']

test('the five pills, in order, and the category each figure belongs to', () => {
  expect(METRIC_TYPES.map((t) => t.label)).toEqual(LABELS)
  expect(metricTypeOf({ metric_category: 'climate' })).toBe('climate')
  expect(metricTypeOf({ metric_category: 'population' })).toBe('population')
  expect(metricTypeOf({ metric_category: 'cost_of_living' })).toBe('rules')
  expect(metricTypeOf({ metric_category: 'unknown' })).toBe(null)
  const rows = [{ metric_category: 'climate' }, { metric_category: 'climate' }, { metric_category: 'population' }, { metric_category: 'cost_of_living' }]
  expect(filterMetrics(rows, 'all')).toHaveLength(4)
  expect(filterMetrics(rows, 'climate')).toHaveLength(2)
  expect(countByType(rows)).toMatchObject({ all: 4, climate: 2, population: 1, rules: 1, careers: 0 })
  expect(fs.readFileSync('src/DestinationData.jsx', 'utf8')).toContain("import{METRIC_TYPES,filterMetrics,countByType,readTypeParam}from'./lib/destination-metric-types.js'")
})

test.describe('mocked browser', () => {
  test('each pill filters the City metrics & costs tab', async ({ page }) => {
    await mockAdmin(page, { rank: 6 })
    await routeCorrelated(page)
    await page.goto('/#destination-data?tab=metrics')
    const pills = page.locator('[data-dst-metric-types] [data-dst-metric-type]')
    await expect(pills).toHaveCount(5)
    for (const [i, l] of LABELS.entries()) await expect(pills.nth(i)).toContainText(l)
    await expect(page.locator('[data-dst-metric]')).toHaveCount(8)
    await page.locator('[data-dst-metric-type="climate"]').click()
    await expect(page.locator('[data-dst-metric]')).toHaveCount(5)
    await expect(page.locator('[data-dst-metric] [data-dst-climate]')).toHaveCount(5)
    await page.locator('[data-dst-metric-type="population"]').click()
    await expect(page.locator('[data-dst-metric]')).toHaveCount(2)
    await page.locator('[data-dst-metric-type="careers"]').click()
    await expect(page.locator('[data-dst-tab="careers"]')).toBeVisible()
    await expect(page.locator('[data-dst-career]')).toHaveCount(2)
    await page.locator('[data-dst-metric-type="rules"]').click()
    await expect(page.locator('[data-dst-tab="rules"]')).toBeVisible()
    await expect(page.locator('[data-dst-city-figures="rules"] [data-dst-metric]')).toHaveCount(1)
    await page.locator('[data-dst-metric-type="all"]').click()
    await expect(page.locator('[data-dst-metric]')).toHaveCount(8)
  })
})
