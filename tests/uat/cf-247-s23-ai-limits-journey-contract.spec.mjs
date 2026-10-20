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
  expect(worker).toMatch(/coverage-sweep-worker-v0\.(?:2[1-9]|3\d)\.\d+/)
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
  // v2.15.300: Layer 2/3 › Universities; Layer 4 Attributes opens the Inbox on central pages to approve
  expect(resolveTarget('providers', new URLSearchParams('tab=onboarding'))).toMatchObject({ page: 'layer2', tab: 'universities' })
  expect(resolveTarget('onboarding')).toMatchObject({ page: 'layer2', tab: 'universities' })
  expect(resolveTarget('layer-4-review', new URLSearchParams('tab=attributes'))).toMatchObject({ page: 'layer4', tab: 'inbox' })
})

test.describe('mocked browser', () => {
  // v2.15.300: the Onboarding list retired; the stepper is in each university's row (Layer 2/3 › Universities), the pace on Operations
  test('Layer 2/3: the stepper in a university row, and the pace and the not-yet-queued button on Operations', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#layer-2-discovery?tab=universities')
    const row = page.locator('[data-adapter-row="u1"]')
    await row.locator('.adp-row-head .adp-row-name').click()
    await expect(row.locator('[data-uni-onboarding="u1"] [data-journey-stage] .po-stepper li')).toHaveCount(7)
    await expect(row.locator('[data-uni-onboarding="u1"] [data-journey-stage]')).toContainText('Stage 4 of 7: Admit')
    await expect(row.locator('[data-journey-enriched]')).toContainText('After it is admitted')
    await page.goto('/#layer-2-discovery')
    await expect(page.locator('[data-layer23-pace]')).toContainText('20 universities finished a stage in the last hour')
    const start = page.locator('[data-po-action="start-all"]')
    await expect(start).toContainText('Onboard universities not yet queued (0)')
    await expect(start).toBeDisabled()
  })

  test('Models & services › OpenRouter: each AI use against its daily guard, and the credit floor', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#models-services?tab=limits')
    await openCards(page) // cards start collapsed
    const or = page.locator('[data-openrouter]')
    await expect(or).toContainText('credit floor US$5')
    await expect(or.locator('[data-or-use="scholarship_ai"]')).toContainText('Running')
    await expect(or.locator('[data-or-use="central_ai"]')).toContainText('Past its guard (observed)')
  })
})
