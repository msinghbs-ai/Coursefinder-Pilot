// CF-247 v2.15.262 (S26): Platform Admin, 12 Oct 2026 21:47: "Report Firecrawl credit used per uni and pages produced, that will give
// us how much waste is happening, and tweak it along." Decisions: all five tweaks; a daily budget of 15,000 credits.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const sql = fs.readFileSync('supabase/migrations/20261012011900_cf247_firecrawl_daily_budget.sql', 'utf8')
const worker = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const outside = s => s.replace(/\$f\$[\s\S]*?\$f\$/g, '').replace(/CREATE OR REPLACE FUNCTION[\s\S]*?\$function\$;/g, '')

test('11900: daily budget 15,000 split by purpose, per-university caps, search stop, report; nothing dropped', () => {
  for (const [k, v] of [['daily_budget_total', '15000'], ['daily_share_course_search', '6000'], ['daily_share_reads', '3000'], ['daily_share_scholarships', '3500'],
                        ['daily_share_central', '1500'], ['daily_share_other', '1000'], ['search_stop_after', '30'], ['scholarship_cap_per_uni', '150'], ['central_refresh_days', '30']])
    expect(sql).toContain(`('firecrawl', '${k}', '${v}'`)
  expect(sql).toContain('create or replace function public.svc_fc_spend(p_units numeric, p_purpose text, p_provider_id uuid, p_url text) returns boolean')
  expect(sql).toContain("v_why := 'university_cap'")
  expect(sql).toContain("v_why := 'not_due'")
  expect(sql).toContain("v_why := 'search_stopped'")
  expect(sql).toContain("and s.provider_id <> all (v_stopped)")
  expect(sql).toContain("v_lim := least(v_lim, floor(security.fc_budget_left_v1('course_link_search') / 2)::int);")
  expect(sql).toContain("'key', 'firecrawl:2:search_stopped'")
  expect(sql).toContain('create or replace function public.admin_firecrawl_credits(p_hours int default 24)')
  expect(sql).toContain('live % differs from the definition this change replaces')
  expect(outside(sql)).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(sql).not.toMatch(/cron\.unschedule/)
})

test('worker v0.21.4: every useFc spend goes through svc_fc_spend; Firecrawl runs stop at the daily share', () => {
  expect(worker).toMatch(/const WORKER = "coverage-sweep-worker-v0\.2[1-9]\.\d+"/)
  expect(worker).toContain('if (!(await rpc("svc_fc_spend", { p_units: units, p_purpose: purpose, p_provider_id: providerId, p_url: url }))) return false;')
  expect(worker).toContain('stopReason = "daily_budget"')
  const useFc = worker.slice(worker.indexOf('const useFc = async'), worker.indexOf('const robots = new Map'))
  expect(useFc).not.toContain('svc_coverage_usage')
})

test.describe('mocked browser', () => {
  test('Toolsets › Firecrawl shows today’s budget and credits by university; a stopped search can be resumed', async ({ page }) => {
    const prompts = []
    page.on('dialog', d => { prompts.push(d.message()); d.accept('Website checked: humber.ca') })
    await mockAdmin(page)
    await page.goto('/#models-services?tab=limits')
    const card = page.locator('[data-fc-by-uni]')
    await expect(card).toBeVisible()
    await card.locator('.cf-card-toggle').first().click()
    await expect(card.locator('[data-fc-group="reads"]')).toContainText('100%')
    await expect(card.locator('[data-fc-group="total"]')).toContainText('12,400')
    await expect(card.locator('[data-fc-totals]')).toContainText('66% waste')
    await expect(card.locator('[data-fc-uni="u-gbc"]')).toContainText('Mostly wrong pages')
    await card.locator('[data-fc-uni="u-hum"]').getByRole('button', { name: 'Search again' }).click()
    await expect.poll(() => page.l3calls.find(c => c.fcResume)).toEqual({ fcResume: 'u-hum', reason: 'Website checked: humber.ca' })
    await card.getByLabel('Flagged only').check()
    await expect(card.locator('[data-fc-uni="u-con"]')).toHaveCount(0)
    await card.getByRole('button', { name: 'Last 7 days' }).click()
    await expect.poll(() => page.l3calls.some(c => c.fcCredits === 168)).toBe(true)
  })
})

test('12000: top 50 Australian providers by CRICOS courses queued first; small pilot rows held; data only', () => {
  const m = fs.readFileSync('supabase/migrations/20261012012000_cf247_au_top50_cohort.sql', 'utf8')
  expect(m).toContain("c.course_code ~ '^[0-9]{6}[0-9A-Z]$'")
  expect(m).toContain('order by x.courses desc, x.provider_id limit 50')
  expect(m).toContain("'au-top-2026-10-12'")
  expect(m).toContain('400000 + t.courses')
  expect(m).toContain('update pipeline.provider_onboarding o set priority = -1')
  expect(m).toContain("< 30;")
  expect(m).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})
