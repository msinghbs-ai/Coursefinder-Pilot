// CF-247 v2.15.259 (S24): Platform Admin, 12 Oct 2026 17:43: "Automate step 4 and onwards, or at least pick 100 universities across AU, NZ
// and CA to prove the mechanism, with hourly updates and a summary table of data completeness". Answers: "Auto-admit everything that
// passes"; pilot 60 AU / 25 NZ / 15 CA, 48 hours.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const sql = fs.readFileSync('supabase/migrations/20261012011600_cf247_onboarding_auto_admit_pilot.sql', 'utf8')
const outside = s => s.slice(0, s.indexOf('CREATE OR REPLACE FUNCTION')) + s.slice(s.lastIndexOf('$function$;'))

test('11600: automatic Admit only while switched on, only the passing fields, logged; recorded with who and why', () => {
  const step = sql.slice(sql.indexOf('FUNCTION security.provider_onboarding_step_v1'), sql.indexOf('FUNCTION public.admin_provider_onboarding'))
  expect(step).toContain("coalesce((select s.auto_admit from pipeline.provider_onboarding_settings s where s.id = 1), false)")
  expect(step).toContain("perform public.admin_uni_adapter_control('admit', jsonb_build_object('provider_id', o.provider_id, 'admit', true, 'fields', o.result->'ready',")
  expect(step).toContain("jsonb_array_length(coalesce(o.result->'ready', '[]'::jsonb)) > 0")
  expect(step).toContain("'auto_admitted', jsonb_build_object('at', now(), 'fields', o.result->'ready')")
  expect(sql).toContain('add column if not exists auto_admit boolean not null default false')
  expect(sql).toContain("auto_admit_reason = case when p_args ? 'auto_admit' then v_reason else auto_admit_reason end")
  expect(sql).toContain('"Auto-admit everything that passes"')
  expect(sql).toContain('live % differs from the definition this change replaces')
  expect(sql).toContain('v2.15.259 post-check: % not as intended')
  expect(outside(sql)).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

test('11600: pilot 60 AU / 25 NZ / 15 CA with a baseline, hourly catalogued snapshot, live report', () => {
  expect(sql).toContain("select security.onboarding_pilot_pick_v1('pilot-2026-10-12', 60, 25, 15);")
  expect(sql).toContain('security.provider_fill_counts_v1(x.provider_id)')
  expect(sql).toContain("values ('onboarding-pilot-snapshot',")
  expect(sql).toContain("cron.schedule('onboarding-pilot-snapshot', '7 * * * *'")
  expect(sql).toContain("if p_action = 'pilot' then")
  expect(sql).toContain("elsif p_action = 'pilot_pick' then")
  expect(sql).toContain('alter table pipeline.onboarding_pilot enable row level security')
})

test.describe('mocked browser', () => {
  test('automatic Admit shows on the page, the Admit stage and in settings; the pilot is linked to Progress', async ({ page }) => {
    await mockAdmin(page, { onboardingAuto: true })
    await page.goto('/#layer-2-discovery?tab=onboarding')
    const ob = page.locator('[data-provider-onboarding]')
    await expect(ob.locator('[data-onboarding-auto-admit]')).toContainText('Auto-admit everything that passes')
    await expect(ob.locator('[data-onboarding-stage="admit"]')).toContainText('Admit (automatic)')
    // v2.15.266: the Pilot panel is retired; the pilot is followed on Coverage & completeness › Progress
    await expect(ob.locator('[data-onboarding-pilot]')).toHaveCount(0)
    await expect(ob.locator('[data-onboarding-progress-link] a')).toHaveAttribute('href', '#coverage?tab=progress&group=pilot')
    await ob.locator('[data-onboarding-settings] summary').click()
    await expect(ob.locator('[data-onboarding-auto-admit-setting] input')).toBeChecked()
  })

  test('with Admit automatic off the page says admitting is a person\'s step', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#layer-2-discovery?tab=onboarding')
    await expect(page.locator('[data-provider-onboarding] .po-lead')).toContainText("Admitting is a person's step")
    await expect(page.locator('[data-onboarding-auto-admit]')).toHaveCount(0)
  })
})
