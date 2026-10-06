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


 test('retired Layer 2 source address lands on Adapters and Source profiles sit on Scrapers & fetchers',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page)
  await page.goto(new URL('/#administration?section=layer2-sources',process.env.UAT_BASE_URL).toString())
  await expect(page.locator('[data-adapters-workspace]')).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  await page.goto(new URL('/#scrapers',process.env.UAT_BASE_URL).toString())
  const card=page.locator('[data-card="scrapers.source-profiles"]');await expect(card).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  await expect(card).toHaveAttribute('data-card-open','false') // every card is closed until opened
  await milestoneScreenshot(page,testInfo,'a23-source-profiles-moved')
 }finally{await finish(testInfo,runtime)}})

 test('background qualification self-continuation uses the service-only public bridge',async()=>{
  const worker=await fs.readFile('supabase/functions/layer2-scale-qualify-scheduled/index.ts','utf8')
  const bridge=await fs.readFile('supabase/migrations/20260831105700_m2_4_4_a23_qualification_continuation_bridge.sql','utf8')
  expect(worker).toContain('layer2-scale-qualify-scheduled-v1.0.3')
  expect(worker).toContain('layer2_qualification_continue_service')
  expect(worker).not.toContain('prpc(svc,"svc_pilot_submit_nonce"')
  expect(bridge).toMatch(/security invoker/i)
  expect(bridge).toMatch(/revoke all on function public\.layer2_qualification_continue_service\(uuid\) from public,anon,authenticated/i)
  expect(bridge).toMatch(/grant execute on function public\.layer2_qualification_continue_service\(uuid\) to service_role/i)
  expect(bridge).toContain("q.status='running'")
  expect(bridge).toContain("qi.status='qualifying'")
  const acl=await fs.readFile('supabase/migrations/20260831111100_m2_4_4_a23_qualification_continuation_acl_reconcile.sql','utf8')
  expect(acl).toMatch(/create or replace function security\.layer2_qualification_continue_impl/i)
  expect(acl).toMatch(/security definer/i)
  expect(acl).toMatch(/create or replace function public\.layer2_qualification_continue_service/i)
  expect(acl).toMatch(/security invoker/i)
  expect(acl).toMatch(/revoke all on function security\.layer2_qualification_continue_impl\(uuid\) from public,anon,authenticated/i)
  expect(acl).toMatch(/grant execute on function security\.layer2_qualification_continue_impl\(uuid\) to service_role/i)
  expect(acl).toMatch(/grant execute on function public\.layer2_qualification_continue_service\(uuid\) to service_role/i)
 })

 test('background production runner preserves the selected Firecrawl route and terminal partial batches do not block later waves',async()=>{
  const runner=await fs.readFile('supabase/functions/layer2-batch-runner/index.ts','utf8')
  const terminal=await fs.readFile('supabase/migrations/20260901092500_m2_4_4_a26_partial_batch_terminal_dispatch.sql','utf8')
  const recovery=await fs.readFile('supabase/migrations/20260901105500_m2_4_4_a26_stale_item_recovery.sql','utf8')
  const resume=await fs.readFile('supabase/migrations/20260901110000_m2_4_4_a26_resume_context.sql','utf8')
  expect(runner).toContain('provider_id:priorProvider||undefined')
  expect(runner).toContain('route_mode==="scraper_first"&&!priorProvider')
  expect(runner).toContain('layer2_run_batch_recover_stale')
  expect(runner).toContain('transportBoundedWave=Math.min(configuredWave,4)')
  expect(runner).toContain('route_mode==="scraper_first"?Math.min(transportBoundedWave,2):transportBoundedWave')
  expect(runner).toContain('layer2_run_item_resume_context')
  expect(recovery).toContain("j.status='succeeded'")
  expect(recovery).toContain("set status='extracting'")
  expect(resume).toContain("and i.status='extracting'")
  expect(terminal).toContain("v_old text := 'if exists(select 1 from pipeline.layer2_run_batches b where b.profile_id=r.profile_id and b.status in(''queued'',''running'',''partial'')) then'")
  expect(terminal).toContain("v_new text := 'if exists(select 1 from pipeline.layer2_run_batches b where b.profile_id=r.profile_id and b.status in(''queued'',''running'')) then'")
  expect(terminal).toContain("v_def:=replace(v_def,v_old,v_new)")
 })

 test('background finaliser completes deterministic controls and governed handoff without autonomous Layer 3 AI',async()=>{
  const finalizer=await fs.readFile('supabase/migrations/20260831115800_m2_4_4_a23_qualification_finalizer_handoff.sql','utf8')
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