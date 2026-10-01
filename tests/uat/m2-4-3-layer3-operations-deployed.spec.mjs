import fs from 'node:fs/promises'
import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, DETERMINISTIC_UI_TIMEOUT, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'
import { openLayer3 } from './support/navigation.mjs'
async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}
test.describe('M2.4.3 Layer 3 AI Operations Maturity @deployed',()=>{
 test.beforeAll(async()=>{if(!process.env.UAT_BASE_URL)throw new Error('UAT_BASE_URL is required for deployed acceptance.');if(!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)throw new Error('UAT credentials are required for deployed acceptance.');await writeRunEnvironment({suite:'m2-4-3-layer3-operations-v1',change_control:'CF-CHG-20260829-047'})})
 test('shows the model cascade per task, deterministic Layer 2 Evidence and human-review provenance without credentials',async({page},testInfo)=>{const runtime=observeRuntime(page);try{await loginAsUatUser(page);const dialog=await openLayer3(page);// v2.15.108: model routes live on the Control tab (cascade per task); the Work queue no longer lists every profile.
// v2.15.127: the Work queue shows work by task and recent results; the one-off manual run form was removed.
await expect(dialog.getByRole('heading',{name:'Qualified model routes'})).toHaveCount(0);await expect(dialog.getByRole('heading',{name:'Work by task'})).toBeVisible();await expect(dialog.getByRole('button',{name:'Run eligible interpretation'})).toHaveCount(0);await expect(dialog.getByRole('heading',{name:'Recent results'})).toBeVisible();await expect(dialog.getByText('API key',{exact:true})).toHaveCount(0);await page.locator('.cf-page-tabs [role="tab"]').filter({hasText:'Control'}).first().click();await expect(page.locator('.l3c-task')).toHaveCount(3,{timeout:DETERMINISTIC_UI_TIMEOUT});await expect(page.locator('.l3c-task').first().locator('tbody tr').first()).toBeVisible();await milestoneScreenshot(page,testInfo,'m2-4-3-layer3-operations')}finally{await finish(testInfo,runtime)}})
 test('checked-in Layer 3 contract preserves replay, confidence, concurrency, recovery and benchmark provenance',async()=>{
  const foundation=await fs.readFile('supabase/migrations/20260829125553_m2_4_3_layer3_operations_maturity_foundation.sql','utf8')
  expect(foundation).toContain("'layer2_resolved'")
  expect(foundation).toContain("'unchanged_evidence'")
  expect(foundation).toContain("'review_confidence_min'")
  expect(foundation).toContain("'low_confidence'")
  expect(foundation).toContain('layer3_fallback_profile_service')
  const recovery=await fs.readFile('supabase/migrations/20260829130640_m2_4_3_layer3_concurrency_recovery_housekeeping.sql','utf8')
  expect(recovery).toContain("'in_flight'")
  expect(recovery).toContain('layer3_interpretations_one_active_entity_task_profile_idx')
  expect(recovery).toContain('layer3_housekeeping_service')
  expect(recovery).toContain("'history_deleted',false")
  const evidencePerf=await fs.readFile('supabase/migrations/20260829212940_m2_4_3_evidence_verification_lookup_hardening.sql','utf8')
  expect(evidencePerf).toContain('course_fees_evidence_verified_idx')
  const provenance=await fs.readFile('supabase/migrations/20260829213038_m2_4_3_prompt_profile_provenance.sql','utf8')
  expect(provenance).toContain('profile_snapshot')
  expect(provenance).toContain('prompt_hash')
  expect(provenance).toContain('layer3_execution_provenance_service')
  const interpret=await fs.readFile('supabase/functions/layer3-interpret/index.ts','utf8')
  expect(interpret).toContain('sha256Hex')
  expect(interpret).toContain('layer3_execution_provenance_service')
  expect(interpret).toContain('prompt_contract_version')
  const benchmark=await fs.readFile('supabase/functions/layer3-source-pattern-benchmark/index.ts','utf8')
  expect(benchmark).toContain('layer3-source-pattern-benchmark-v1.1.0')
  expect(benchmark).toContain('attempt_trace')
  expect(benchmark).toContain('retry_count')
 })
})
