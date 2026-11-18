// Guards: Platform Admin 18 Nov 2026 14:23 (weather icons and the entity correlation model): a climate figure shows a lucide icon chosen by one documented rule (sunny, partly cloudy, rain, heavy rain, storm, snow, wind) that describes a long-term average, never a forecast; Guides › Platform guide shows how destinations, providers, courses, rules and outcomes join, naming only live API v3 paths.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { climateIcon, CLIMATE_ICONS, HEAVY_RAIN_MM, SNOW_MIN_C } from '../../src/lib/climate-icons.js'
import { ENTITY_LINKS, ENTITY_RULES } from '../../src/guide/entityModel.js'

test('the climate icon rule', () => {
  expect(climateIcon('climate_summer_mean_max_c', 32)).toBe('sunny')
  expect(climateIcon('climate_winter_mean_min_c', 0.8)).toBe('snow')
  expect(climateIcon('climate_winter_mean_min_c', SNOW_MIN_C + 0.1)).toBe('partly_cloudy')
  expect(climateIcon('climate_annual_rainfall_mm', 525.8)).toBe('rain')
  expect(climateIcon('climate_annual_rainfall_mm', HEAVY_RAIN_MM)).toBe('heavy_rain')
  expect(climateIcon('climate_thunderstorm_days', 30)).toBe('storm')
  expect(climateIcon('climate_mean_wind_kmh', 20)).toBe('wind')
  expect(climateIcon('population_total', 5)).toBeNull()
  for (const k of ['sunny', 'partly_cloudy', 'rain', 'heavy_rain', 'storm', 'snow', 'wind']) expect(CLIMATE_ICONS[k]).toBeTruthy()
  expect(fs.readFileSync('src/lib/climate-icons.js', 'utf8')).toContain('not forecasts')
})

test('the model joins on codes and names only live API v3 paths', () => {
  expect(ENTITY_LINKS.map((l) => `${l.from} → ${l.to}`)).toEqual(['Destination → Provider', 'Provider → Course', 'Course → Course facts', 'Course → Study rules & career outcomes'])
  const all = ENTITY_LINKS.flatMap((l) => l.paths).join(' ')
  for (const p of ['item.campuses[].locality.locality_id', 'item.campuses[].is_primary', 'item.provider.accreditations[].body_code', 'item.study_load', 'item.empty_reason_code',
    'item.entry_requirements.summary', 'item.scholarships[].name', 'study_rules[].rule_category', 'career_outcomes[].locality_id', 'localities[].metrics[].key']) expect(all).toContain(p)
  expect(ENTITY_RULES.join(' ')).toContain('never on names')
})

test.describe('mocked browser', () => {
  test('Destination data shows a climate icon beside a climate measure; the Platform guide shows how the data connects', async ({ page }) => {
    await mockAdmin(page, { rank: 6 })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_destination_review', (r) => r.fulfill({ json: { rows: [
      { id: 'm1', locality_name: 'Hobart', country_code: 'AU', metric_category: 'climate', metric_key: 'climate_winter_mean_min_c', numeric_value: 0.8, unit: '°C', reference_period: '1991-2020', dataset_edition: 'BOM normals', status: 'draft' },
      { id: 'm2', locality_name: 'Darwin', country_code: 'AU', metric_category: 'climate', metric_key: 'climate_annual_rainfall_mm', numeric_value: 1732.4, unit: 'mm', reference_period: '1991-2020', dataset_edition: 'BOM normals', status: 'draft' },
      { id: 'm3', locality_name: 'Sydney', country_code: 'AU', metric_category: 'population', metric_key: 'population_total', numeric_value: 5000000, unit: 'people', reference_period: '2021', dataset_edition: 'ABS', status: 'draft' }] } }))
    await page.goto('/#destination-data?tab=metrics')
    await expect(page.locator('[data-dst-metric="m1"] [data-dst-climate="snow"]')).toBeVisible()
    await expect(page.locator('[data-dst-metric="m2"] [data-dst-climate="heavy_rain"]')).toBeVisible()
    await expect(page.locator('[data-dst-metric="m3"] [data-dst-climate]')).toHaveCount(0)
    await page.goto('/#platform-guide')
    const m = page.locator('[data-guide-model]')
    await expect(m).toContainText('How the data connects')
    await expect(m.locator('[data-guide-model-link]')).toHaveCount(4)
    await expect(m).toContainText('item.campuses[].locality.locality_id')
  })
})
