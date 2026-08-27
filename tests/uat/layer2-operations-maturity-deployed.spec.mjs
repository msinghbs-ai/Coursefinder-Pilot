import fs from 'node:fs/promises'
import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'
import { openLayer2, openLayer2Providers } from './support/navigation.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}
async function firecrawlDrawer(page){const b=page.locator('.l2p-provider-list > button').filter({hasText:'Firecrawl'}).first();await expect(b).toBeVisible();await b.click();const d=page.locator('.l2p-drawer');await expect(d).toBeVisible();return d}

test.describe('CourseFinder deployed Layer 2 operations maturity @deployed',()=>{
 test.beforeAll(async()=>{if(!process.env.UAT_BASE_URL)throw new Error('UAT_BASE_URL is required');if(!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)throw new Error('UAT credentials are required');await writeRunEnvironment({suite:'deployed-layer2-operations-m2-4-2-v1.6',change_control:'CF-CHG-20260827-044'})})

 test('routine Layer 2 workspace exposes Country State University scope with one governed sync action',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page);const dialog=await openLayer2(page)
  await expect(dialog.getByRole('heading',{name:'Layer 2 — Enrichment'})).toBeVisible()
  await expect(dialog.getByRole('heading',{name:'Sync Course enrichment'})).toBeVisible()
  const country=dialog.getByLabel('Layer 2 sync country'),scope=dialog.getByLabel('Layer 2 fetch scope')
  await expect(country).toHaveValue('AU');await expect(scope).toHaveValue('country')
  const scopeLabels=await scope.locator('option').allTextContents();expect(scopeLabels.join(' ')).toMatch(/Country.*State.*University/i)
  for(const label of ['Universities','Catalogue Courses','Ready to sync','Needs discovery'])await expect(dialog.getByText(label,{exact:true}).first()).toBeVisible()
  await expect(dialog.getByRole('button',{name:/Discover & sync|Sync now/})).toBeVisible()

  await scope.selectOption('state')
  const state=dialog.getByLabel('Layer 2 sync state');await expect(state).toBeVisible()
  const stateLabels=await state.locator('option').allTextContents();expect(stateLabels.join(' ')).toMatch(/Victoria/i);expect(stateLabels.join(' ')).toMatch(/Queensland/i)

  await scope.selectOption('university')
  const uni=dialog.getByLabel('Layer 2 sync university');await expect(uni).toBeVisible()
  const uniLabels=await uni.locator('option').allTextContents();expect(uniLabels.join(' ')).toMatch(/RMIT/i);expect(uniLabels.join(' ')).toMatch(/Queensland/i);expect(uniLabels.join(' ')).toMatch(/Federation/i)
  await expect(dialog.getByText(/Direct HTTP.*Firecrawl.*remaining configured providers/i)).toBeVisible()
  await expect(dialog.getByRole('button',{name:/Run bounded trial/i})).toHaveCount(0)
  await milestoneScreenshot(page,testInfo,'layer2-a9-scope-sync')
 }finally{await finish(testInfo,runtime)}})

 test('routine Layer 2 screen quarantines engineering controls behind one Advanced configuration entry',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page);const dialog=await openLayer2(page)
  await expect(dialog.getByRole('button',{name:/Advanced configuration/i})).toHaveCount(1)
  await expect(dialog.getByRole('heading',{name:'Scope / eligible records'})).toHaveCount(0)
  await expect(dialog.getByRole('heading',{name:'Provider / source performance'})).toHaveCount(0)
  await expect(dialog.getByRole('heading',{name:'Queue / concurrency'})).toHaveCount(0)
  await expect(dialog.getByRole('button',{name:/Schedule & run policy/i})).toHaveCount(0)
  await expect(dialog.getByRole('button',{name:/Advanced provider config/i})).toHaveCount(0)
  await expect(dialog.getByText(/provider credentials|route priority|vendor concurrency/i)).toHaveCount(0)
  await expect(dialog.getByRole('button',{name:/delete|reset|truncate/i})).toHaveCount(0)
 }finally{await finish(testInfo,runtime)}})

 test('Firecrawl vendor limits remain visible only in privileged provider configuration',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page);await openLayer2Providers(page);const d=await firecrawlDrawer(page)
  await expect(d.getByText('Vendor concurrency',{exact:true})).toBeVisible()
  await expect(d.locator('.l2p-info').filter({hasText:'Vendor concurrency'})).toContainText(/\d+/)
  await expect(d.getByText('Rate / timeout',{exact:true})).toBeVisible()
  await expect(page.getByText(/Credentials are write-only and provider concurrency is separate from run concurrency/i)).toBeVisible()
  await expect(d.getByRole('button',{name:'Edit provider settings'})).toHaveCount(0)
  await milestoneScreenshot(page,testInfo,'layer2-firecrawl-provider-privileged')
 }finally{await finish(testInfo,runtime)}})

 test('Layer 2 recovery and reference contracts remain checked in',async()=>{
  const cancelSql=await fs.readFile('supabase/migrations/20260827221500_m2_4_2_cancel_reconcile_guard.sql','utf8')
  expect(cancelSql).toContain("if v_existing='cancelled'")
  expect(cancelSql).toContain("v_status:='cancelled'")
  expect(cancelSql).toMatch(/revoke all on function public\.layer2_run_batch_reconcile\(uuid\) from public,anon,authenticated/i)
  expect(cancelSql).toMatch(/grant execute on function public\.layer2_run_batch_reconcile\(uuid\) to service_role/i)

  const idemSql=await fs.readFile('supabase/migrations/20260827223500_m2_4_2_discovery_terminal_outcome_idempotency.sql','utf8')
  expect(idemSql).toContain("dc.status in ('exact_match','likely_match','ambiguous','identity_mismatch','current_page_not_found')")
  expect(idemSql).toMatch(/grant execute on function public\.layer2_discovery_context\(uuid,integer\) to service_role/i)

  const toeflSql=await fs.readFile('supabase/migrations/20260827223000_m2_4_2_toefl_ibt_apply_mapping.sql','utf8')
  expect(toeflSql).toContain("TOEFL_IBT")
  expect(toeflSql).toContain("layer2_apply_course_candidate")
  expect(toeflSql).toMatch(/grant execute on function public\.layer2_apply_course_candidate\(uuid,boolean\) to service_role/i)

  const discovery=await fs.readFile('supabase/functions/layer2-scope-discover-scheduled/index.ts','utf8')
  expect(discovery).toContain('layer2-scope-discover-scheduled-v1.2.8')
  expect(discovery).toContain('courseBudgetMs')
  expect(discovery).toContain('invocationBudgetMs=85000')
  expect(discovery).toContain('continuation_request_id')
  expect(discovery).toContain('consumedSet')
  expect(discovery).toContain('courseIds.filter')
  expect(discovery).toContain('layer2_assert_profile_executable')
  expect(discovery).toContain('invocationRemainingMs')
  expect(discovery).toContain('budgetCapMs')
 })

})
