import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, DETERMINISTIC_UI_TIMEOUT, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment, clickPrimaryNav } from './support/runtime-evidence.mjs'
import { openLayer3, openLayer4, openOnboarding } from './support/navigation.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CourseFinder deployed M2.3 intelligence acceptance on canonical routes @deployed',()=>{
 test.beforeAll(async()=>{await writeRunEnvironment({suite:'deployed-m2-3-intelligence-canonical-routes',change_control:'CF-CHG-20260830-048'})})

 test('governed Layer 3 profile exposes benchmark-passed pinned models and zero-call governance',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page);const ws=await openLayer3(page)
  const profileCard=ws.getByRole('article').filter({hasText:'openrouter-free-router-v1'});await expect(profileCard.getByText('openrouter-free-router-v1',{exact:true})).toBeVisible()
  await expect(profileCard).toContainText('nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free');await expect(profileCard.getByText('Enabled',{exact:true})).toBeVisible();await expect(profileCard).toContainText(/Quality:\s*Benchmark Passed/i)
  await expect(ws.getByText(/Unchanged Evidence and Layer-2-resolved work take zero-call paths/i)).toBeVisible();await expect(ws.getByText(/Provider credentials remain server-side and are never rendered here/i)).toBeVisible()
  await milestoneScreenshot(page,testInfo,'m2-3-layer3-canonical')
 }finally{await finish(testInfo,runtime)}})

 test('Layer 4 and Refresh/Scheduling are separate governed workspaces',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page);const l4=await openLayer4(page);await expect(l4.getByRole('heading',{name:'Human resolution queue',exact:true})).toBeVisible();await expect(l4.getByPlaceholder(/prioritise unresolved field/i)).toBeVisible()
  await page.evaluate(()=>{location.hash='#refresh-scheduling'});await expect(page.getByRole('heading',{name:'Source/entity freshness policies',exact:true})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT});await expect(page.getByRole('heading',{name:'Targeted refresh queue',exact:true})).toBeVisible();await expect(page.getByRole('heading',{name:'Downstream Search refresh signals',exact:true})).toBeVisible();await expect(page.getByText('UNBOUNDED',{exact:true})).toHaveCount(0)
  await milestoneScreenshot(page,testInfo,'m2-3-layer4-refresh-separate')
 }finally{await finish(testInfo,runtime)}})

 test('Important Links and Important Dates are separate parent-menu registries',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page);await clickPrimaryNav(page,'Important Links');await expect(page.getByRole('heading',{name:'Important Links directory',exact:true})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  await clickPrimaryNav(page,'Important Dates');await expect(page.getByRole('heading',{name:'Important Dates registry',exact:true})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT});await expect(page.getByText(/Vague wording is retained as vague/i)).toBeVisible();await expect(page.getByText(/Date-only sources use date-only storage/i)).toBeVisible();await expect(page.getByText(/Country-reference events cannot trigger ingestion/i)).toBeVisible()
  await milestoneScreenshot(page,testInfo,'m2-3-links-dates-parent-menu')
 }finally{await finish(testInfo,runtime)}})

 test('Onboarding remains governed under central Administration',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page);const ws=await openOnboarding(page);await expect(ws.getByRole('heading',{name:'Country / Provider / Course Onboarding',exact:true})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT});await expect(ws.getByText(/Shared canonical lifecycle only/i)).toBeVisible()
  const stage=ws.getByLabel('Stage');for(const value of ['draft','source_qualification','adapter_assessment','schema_assessment','l1_uat','l2_uat','l3_ready','operational_certification','production_promotion_ready'])await expect(stage.getByRole('option',{name:value,exact:true})).toHaveCount(1)
  await expect(ws.getByRole('heading',{name:'Create governed onboarding case',exact:true})).toBeVisible();await milestoneScreenshot(page,testInfo,'m2-3-onboarding-administration')
 }finally{await finish(testInfo,runtime)}})
})
