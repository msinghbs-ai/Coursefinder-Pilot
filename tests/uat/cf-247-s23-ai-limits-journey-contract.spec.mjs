// CF-247 v2.15.258 (S23): Platform Admin bug 12/10-01, 12 Oct 2026: "Model and Services are missing Layer 3 Limits functionality.
// Provider onboarding should be in Layer 2/3 as a tab, mass automatic adapter creation is not there — if I press Onboard all without an
// adapter, what will happen? Prepare the journey milestones". Agreed: seven journey stages, scholarships after courses are enriched,
// AI limits observed (notices only), 100 universities at once.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { openCards } from './support/cards.mjs'
import { resolveTarget } from '../../src/nav-map.js'

const m14 = fs.readFileSync('supabase/migrations/20261012011400_cf247_ai_limits_onboarding_pace.sql', 'utf8')
const m15 = fs.readFileSync('supabase/migrations/20261012011500_cf247_onboarding_journey_stages.sql', 'utf8')
const worker = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const outside = s => s.slice(0, s.indexOf('CREATE OR REPLACE FUNCTION')) + s.slice(s.lastIndexOf('$function$;'))

test('11400: OpenRouter limits read the AI uses that run now; observe never stops; balance read every 15 minutes', () => {
  expect(m14).toContain('create or replace function security.ai_spend_today_v1()')
  expect(m14).toContain('create or replace function security.ai_use_allowed_v1(')
  expect(m14).toContain('svc_openrouter_balance_record')
  expect(m14).toContain("'openrouter-balance'")
  expect(m14).toContain("'*/15 * * * *'")
  for (const k of ['credit_floor_usd', 'guard_scholarship_ai', 'guard_adapter_builder', 'guard_central_ai', 'guard_course_match']) expect(m14).toContain(`'${k}'`)
  // the scholarship AI and central pages AI ask before firing; only 'stop' mode can refuse
  expect((m14.match(/security\.ai_use_allowed_v1\('/g) || []).length).toBeGreaterThanOrEqual(2)
  expect(m14).toContain('live % differs from the definition this change replaces')
  expect(outside(m14)).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(worker).toContain('coverage-sweep-worker-v0.21.1')
  expect(worker).toContain('mode === "openrouter_balance"')
  expect(worker).toContain('https://openrouter.ai/api/v1/credits')
})

test('11500: qualifying ends at Admit; admitted → enrich → scholarship search → admit scholarships → done; never admits', () => {
  const step = m15.slice(m15.indexOf('FUNCTION security.provider_onboarding_step_v1'), m15.indexOf('FUNCTION security.provider_onboarding_tick_v1'))
  expect(step).toContain("v2.15.258 journey: qualifying ends at Admit")
  expect(step).not.toContain("note = 'Qualified; finding scholarships.'")
  expect(step).toContain("jsonb_build_object('phase', 'enrich', 'admitted_at', now())")
  expect(step).toContain("o.result->>'phase' = 'enrich'")
  expect(step).toContain("jsonb_build_object('enriched', v_en, 'phase', 'scholarship_search')")
  expect(step).toContain("o.result->>'phase' = 'scholarship_admit'")
  expect(step).toContain("r.status = 'pending'")
  expect(step).toContain("v_age > interval '7 days'")
  expect(step).not.toMatch(/'admit'\s*,\s*true|set admit = true/)
  // the waiting stages do not count towards "at once" and are checked every 10 minutes
  expect(m15).toContain("coalesce(result->>'phase', 'scholarship_search') = 'scholarship_search'")
  expect(m15).toContain("ob.updated_at < now() - interval '10 minutes'")
  expect(m15).toContain('create or replace function security.provider_onboarding_stage_v1(')
  expect(m15).toContain("'stages', (select")
  expect(m15).toContain("p_args->>'stage' is null")
  expect(m15).toContain('v2.15.258 journey post-check: % not as intended')
  expect(outside(m15)).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(m15).not.toMatch(/drop constraint/i)
})

test('Providers › Onboarding redirects to Layer 2 › Onboarding', () => {
  expect(resolveTarget('providers', new URLSearchParams('tab=onboarding'))).toMatchObject({ page: 'layer2', tab: 'onboarding' })
  expect(resolveTarget('onboarding')).toMatchObject({ page: 'layer2', tab: 'onboarding' })
  expect(resolveTarget('layer-4-review', new URLSearchParams('tab=attributes'))).toMatchObject({ page: 'layer2', tab: 'onboarding' })
})

test.describe('mocked browser', () => {
  test('Layer 2 › Onboarding: seven stages, a stepper per row, stage filter, the pace, and the button counts only universities not yet queued', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#layer-2-discovery?tab=onboarding')
    const ob = page.locator('[data-provider-onboarding]')
    const strip = ob.locator('[data-onboarding-stages]')
    await expect(strip.locator('[data-onboarding-stage]')).toHaveCount(8)
    await expect(strip.locator('[data-onboarding-stage="enrich"]')).toContainText('Enrich courses')
    await expect(strip.locator('[data-onboarding-stage="enrich"]')).toContainText('2')
    await expect(ob.locator('[data-onboarding-pace]')).toContainText('20 universities finished a stage in the last hour')
    await expect(ob.locator('[data-onboarding-pace]')).toContainText('About 3 days for the 1,100 queued')
    await expect(ob.locator('[data-onboarding-row="ob-3"] .po-stepper li')).toHaveCount(7)
    await expect(ob.locator('[data-onboarding-row="ob-3"] .po-stepper')).toHaveAttribute('data-stage', 'admit')
    await expect(ob.locator('[data-onboarding-row="ob-1"] [data-onboarding-origin]')).toContainText('From the Layer 1 register')
    await strip.locator('[data-onboarding-stage="admit"]').click()
    await expect(ob.locator('[data-onboarding-row]')).toHaveCount(3)
    const start = ob.locator('[data-po-action="start-all"]')
    await expect(start).toContainText('Onboard universities not yet queued (0)')
    await expect(start).toBeDisabled()
    await expect(ob.locator('[data-onboarding-all-queued]')).toBeVisible()
  })

  test('the journey shows the stage and that scholarships wait until the courses are enriched', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#providers?tab=onboarding')
    await expect(page).toHaveURL(/layer-2-discovery\?tab=onboarding/)
    const ob = page.locator('[data-provider-onboarding]')
    await ob.locator('[data-onboarding-journey-toggle="ob-3"]').click()
    const j = ob.locator('[data-onboarding-journey="ob-3"]')
    await expect(j.locator('[data-journey-stage="admit"]')).toContainText('Stage 4 of 7: Admit')
    await expect(j.locator('[data-journey-enriched]')).toContainText('After it is admitted')
  })

  test('Models & services › OpenRouter: each AI use against its daily guard, and the credit floor', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#models-services')
    await openCards(page) // cards start collapsed
    const or = page.locator('[data-openrouter]')
    await expect(or).toContainText('credit floor US$5')
    await expect(or.locator('[data-or-use="scholarship_ai"]')).toContainText('Running')
    await expect(or.locator('[data-or-use="central_ai"]')).toContainText('Past its guard (observed)')
  })
})
