import fs from 'node:fs/promises'
import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, clickPrimaryNav, DETERMINISTIC_UI_TIMEOUT, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'
async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}
test.describe('A23 quota-aware Layer 2 background execution @deployed',()=>{
 test.beforeAll(async()=>{await writeRunEnvironment({suite:'m2-4-4-a23-layer2-background-firecrawl',change_control:'CF-CHG-20260830-048'})})
 // Decision 222 (v2.15.149): the old background pipeline (waves, qualification batches) is retired; Fetch an area puts an
 // area first in the course-page sweep and shows no qualification knobs.
 test('operator Adapters screen has no qualification knobs',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page);await clickPrimaryNav(page,'Layer 2 — Enrichment')
  const ws=page.locator('[data-adapters-workspace]');await expect(ws).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  await expect(ws.locator('[data-adapters-list]')).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  await expect(ws.getByRole('button',{name:'Start production enrichment',exact:true})).toHaveCount(0)
  await expect(page.getByLabel('Layer 2 Wave 1 Courses')).toHaveCount(0);await expect(page.getByLabel('Layer 2 acquisition route')).toHaveCount(0)
  await expect(ws.getByText(/Qualification Providers \/ batch/i)).toHaveCount(0)
  await milestoneScreenshot(page,testInfo,'a23-layer2-adapters')
 }finally{await finish(testInfo,runtime)}})


 test('retired Layer 2 source address lands on Adapters; Scrapers & fetchers shows the provider registry',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page)
  await page.goto(new URL('/#administration?section=layer2-sources',process.env.UAT_BASE_URL).toString())
  await expect(page.locator('[data-adapters-workspace]')).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  await page.goto(new URL('/#scrapers',process.env.UAT_BASE_URL).toString())
  // Clean-up batch 2 (9 Oct 2026): Source profiles were retired; the provider registry stays.
  await expect(page.locator('.l2p-provider-list')).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  await expect(page.locator('[data-card="scrapers.source-profiles"]')).toHaveCount(0)
  await milestoneScreenshot(page,testInfo,'a23-scrapers-registry')
 }finally{await finish(testInfo,runtime)}})

 // Clean-up batch 7 (9 Oct 2026): layer2-scale-qualify-scheduled and its continuation bridge were retired.
 test('background finaliser completes deterministic controls and governed handoff without autonomous Layer 3 AI',async()=>{
  const finalizer=await fs.readFile('supabase/migrations-archive/20260831115800_m2_4_4_a23_qualification_finalizer_handoff.sql','utf8')
  expect(finalizer).toContain('qualification_finalizer_run_limit')
  expect(finalizer).toContain('qualification_pattern_provider_limit')
  expect(finalizer).toMatch(/create or replace function security\.layer2_qualification_finalizer_tick_impl/i)
  expect(finalizer).toContain('layer2_scale_pattern_dispatch')
  expect(finalizer).toContain('layer2_scale_pattern_reconcile')
  expect(finalizer).toContain('layer2_scale_cross_layer_handoff')
  expect(finalizer).toContain("p.code='openrouter-source-pattern-v1'")
  expect(finalizer).toContain("'queued_for_governed_operator_execution'")
  expect(finalizer).not.toContain('functions/v1/layer3-interpret')
  expect(finalizer).toContain("'coursefinder-layer2-qualification-finalizer'")
  expect(finalizer).toContain("'2-59/5 * * * *'")
 })

})