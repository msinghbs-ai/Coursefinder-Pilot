// Guards: CF-247 v2.15.255 (S20): Platform Admin, 12 Oct 2026 11:15: "Will this create the adapter automatically, start the scholarships as well, and can I monitor the journey from the…
// CF-247 v2.15.255 (S20): Platform Admin, 12 Oct 2026 11:15: "Will this create the adapter automatically, start the scholarships as well,
// and can I monitor the journey from the UI?" The AI proposes again when no field passes (an old adapter included); nothing ready after
// that is "Needs a person", not Ready to admit; each university opens its journey; new scholarships are counted live.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const sql = fs.readFileSync('supabase/migrations/20261012010700_cf247_onboarding_ai_retry_journey.sql', 'utf8')

test('migration: AI proposes again when no field passes, at most 2 attempts; nothing ready stops for a person; never admits', () => {
  const step = sql.slice(sql.indexOf('FUNCTION security.provider_onboarding_step_v1'))
  expect(step).toContain("if jsonb_array_length(coalesce(v_rd->'ready', '[]'::jsonb)) = 0 and coalesce((o.result->>'ai_attempts')::int, 0) < 2 and v_read >= v_need then")
  expect(step).toContain("'samples', case when coalesce((o.result->>'ai_attempts')::int, 0) = 0 then 6 else 10 end")
  expect(step).toContain("else 'nothing_ready' end")
  expect(step).toContain('The current settings did not pass: ')
  expect(step).toContain("if j.id is null and o.result ? 'scholarships' then j.state := 'done'")
  // admitting stays a person's step
  expect(step).not.toMatch(/admit'?\s*,\s*true|set admit = true/)
  expect(sql).toContain("nullif(p_args->>'samples', '')::int")
  expect(sql).toContain('live % differs from the definition this change replaces')
  expect(sql).toContain('v2.15.255 post-check: % not as intended')
  // outside the replaced function bodies (admin_adapter_builder keeps its own existing statements), nothing is dropped or deleted
  const outside = sql.slice(0, sql.indexOf('CREATE OR REPLACE FUNCTION')) + sql.slice(sql.lastIndexOf('$function$;'))
  expect(outside).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(sql).not.toMatch(/^alter table .* drop /im)
})

test('migration: journey events, journey read, live scholarship counts, the 35 sent back', () => {
  expect(sql).toContain('create table if not exists pipeline.provider_onboarding_events')
  expect(sql).toContain('create trigger provider_onboarding_events_log after insert or update on pipeline.provider_onboarding')
  expect(sql).toContain("if p_action = 'journey' then")
  expect(sql).toContain("'scholarships_live', jsonb_build_object('found'")
  expect(sql).toContain("where status = 'waiting_admit' and jsonb_array_length(coalesce(result->'ready', '[]'::jsonb)) = 0;")
})

test('migration 10800: the course-page search picks only Firecrawl target universities while target-only is on', () => {
  const s = fs.readFileSync('supabase/migrations/20261012010800_cf247_link_search_targets_only.sql', 'utf8')
  expect(s).toContain("exists (select 1 from pipeline.firecrawl_target_cache tc where tc.provider_id = s.provider_id and tc.included)")
  expect(s).toContain('live % differs from the definition this change replaces')
  expect(s.slice(0, s.indexOf('CREATE OR REPLACE FUNCTION'))).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

test('migration 11000: the Needs a person note is short (reasons stay in Fields)', () => {
  const s = fs.readFileSync('supabase/migrations/20261012011000_cf247_onboarding_needs_person_note.sql', 'utf8')
  expect(s).toContain("Nothing passed after %s AI attempt(s); the Fields column shows why for each field.")
  expect(s).toContain('live % differs from the definition this change replaces')
})

test.describe('mocked browser', () => {
  // v2.15.300: the Onboarding list retired; Needs a person is a Journey filter on Layer 2/3 › Universities and the journey opens in the row
  test('Needs a person is its own Journey filter, separate from Stopped', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#layer-2-discovery?tab=universities')
    const w = page.locator('[data-adapters-workspace]')
    await w.getByRole('combobox', { name: 'Provider kind' }).selectOption('any')
    await w.getByRole('combobox', { name: 'Journey stage' }).selectOption('person')
    await expect(w.locator('[data-adapter-row]')).toHaveCount(1)
    await w.getByRole('combobox', { name: 'Journey stage' }).selectOption('stopped')
    await expect(w.locator('[data-adapter-row]')).toHaveCount(0)
  })

  test('the journey opens per university with its steps, AI drafts, Qualify and scholarships', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#layer-2-discovery?tab=universities')
    const row = page.locator('[data-adapter-row="u1"]')
    await row.locator('.adp-row-head .adp-row-name').click()
    const j = row.locator('[data-onboarding-journey="ob-1"]')
    await expect(j).toContainText('AI attempts in this onboarding: 1 of 2')
    await expect(j.locator('[data-journey-item="step"]')).toHaveCount(3)
    await expect(j.locator('[data-journey-item="task"]')).toContainText('Scholarship search')
    await expect(j.locator('[data-journey-qualify]')).toContainText('Passes')
    await expect(j.locator('[data-journey-scholarships]')).toContainText('Global Excellence Scholarship')
    await expect.poll(() => page.l3calls.some(c => c.onboarding === 'journey' && c.args?.id === 'ob-1')).toBe(true)
  })
})
