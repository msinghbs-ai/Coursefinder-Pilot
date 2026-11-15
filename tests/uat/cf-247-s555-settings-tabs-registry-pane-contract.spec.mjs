// Guards: Settings Hub tabs and the prompt registry on the AI tab (Platform Admin 16 Nov 2026 07:41): Settings › Settings draws one group at a time as tabs, opening on the settings a person changed (or the first group with settings), and Models & services › AI shows the prompt registry (shadow) with each prompt's live copy, text and model parity
// CF-247 S555. src/SettingsRegister.jsx, src/AiModelsServices.jsx, migration 20261116070000 (the AI route's balance reading through an index). Mocked REST responses: nothing reaches a real backend.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { aiOverview } from './support/ai-overview-fixture.mjs'

const UI = fs.readFileSync('src/SettingsRegister.jsx', 'utf8')
const AI = fs.readFileSync('src/AiModelsServices.jsx', 'utf8')

test('one group drawn at a time; the default is the changed settings, else the first group', () => {
  expect(UI).toContain('role="tablist" aria-label="Settings groups" data-hub-tabs')
  expect(UI).toContain("(edited.length>0?'Edited':groups[0]?.[0])")
  expect(UI).toContain('groups.filter(([g])=>g===current).map(')
  expect(AI).toContain('<PromptRegistryPane d={d}/>')
})

test('the latest OpenRouter balance reading is found through an index', () => {
  const M = fs.readFileSync('supabase/migrations/20261116070000_cf247_ai_route_observation_index.sql', 'utf8')
  expect(M).toContain('create index if not exists layer3_openrouter_observations_kind_observed_idx on pipeline.layer3_openrouter_observations (kind, observed_at desc);')
})

test.describe('mocked browser', () => {
  test('the AI tab lists the registered prompts with their parity', async ({ page }) => {
    await mockAdmin(page)
    const overview = { ...aiOverview(), prompt_registry: [
      { service: 'course_description', version: 'cdesc-source-grounded-v2', status: 'shadow', source: 'worker code: course-text.ts CDESC_SYSTEM', system_text_matches: null, models_match_route: true },
      { service: 'provider_description', version: 'v4', status: 'shadow', source: 'pipeline.provider_description_prompts version 4', system_text_matches: true, models_match_route: true },
      { service: 'scholarship_extraction', version: 'v3', status: 'shadow', source: 'pipeline.scholarship_ai_prompts version 3', system_text_matches: false, models_match_route: true }] }
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_ai_overview_v1', route => route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(overview) }))
    await page.goto('/#models-services?tab=ai')
    const pane = page.locator('[data-ai-pane="prompt-registry"]')
    await expect(pane).toContainText('3 prompts')
    await pane.locator('.cf-card-toggle').click()
    await expect(pane.locator('[data-prompt-row]')).toHaveCount(3)
    await expect(pane.locator('[data-prompt-row="provider_description"]')).toContainText('Matches')
    await expect(pane.locator('[data-prompt-row="scholarship_extraction"]')).toContainText('Differs')
    await expect(pane.locator('[data-prompt-row="course_description"]')).toContainText('Checked by spec')
  })
})
