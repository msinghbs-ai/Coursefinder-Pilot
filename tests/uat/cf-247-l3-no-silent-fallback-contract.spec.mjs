// CF-247 Decision 221 (v2.15.148): intakes and English never fall back to the single routed profile (Claude Sonnet 4.6,
// from before the cascade). With no cascade step switched on nothing is claimed and no model is called. Recent results
// shows a cascade claim no step has answered yet as "Cascade · step not chosen yet", not as its placeholder profile.
import fs from 'node:fs/promises'
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'

test('worker: no claim without a switched-on step; ladder mode never reaches the single-profile path', async () => {
  const w = await fs.readFile('supabase/functions/layer3-model-routing/index.ts', 'utf8')
  expect(w).toContain('if (pre?.route_mode === "ladder" && !usable(pre).length) return j(200')
  expect(w).toContain('nothing sent to any model')
  expect(w).toContain('const isLadder = ladder?.route_mode === "ladder";')
  expect(w).toContain('if (isLadder) {')
  expect(w).not.toContain('if (tiers.length) {')
  expect(w).toContain('if (!its.length) { const r = await rpc("layer3_fact_release_service"')
  expect(w).toContain('blockers.length && tiers.length')
  // the claim check comes before the claim
  expect(w.indexOf('usable(pre).length')).toBeLessThan(w.indexOf('rpc("layer3_fact_claim_service"'))
})

test('migration: placeholder profile hidden for unanswered cascade claims, behind an md5 guard', async () => {
  const m = await fs.readFile('supabase/migrations-archive/20261002181900_cf247_l3_recent_results_cascade_label.sql', 'utf8')
  expect(m).toContain("'9b752374045543ecd2d6c544f6f56bdf'")
  expect(m).toContain("b.route_mode='ladder'")
  expect(m).toContain('i.cascade_tier_no is null and i.aggregator_response_model is null as v')
  expect(m).toContain('case when pend.v then null else p.model_identifier end as model_identifier')
  expect(m).not.toMatch(/\bdrop\s|delete\s+from|truncate/i)
})

test('browser: Recent results labels a pending cascade claim and shows the answering step', async ({ page }) => {
  await mockAdmin(page)
  await page.goto('/#layer-3-ai?tab=work')
  const runs = page.locator('.l3w-runs')
  await expect(runs.locator('[data-model-pending]')).toHaveText('Cascade · step not chosen yet')
  await expect(runs.locator('tbody tr').nth(1)).toContainText('step 2')
  await expect(runs).not.toContainText('claude-sonnet')
})
