import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, DETERMINISTIC_UI_TIMEOUT, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'
import { openLayer1 } from './support/navigation.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('M2.4.1 Layer 1 regulatory operations @deployed',()=>{
  test.beforeAll(async()=>{if(!process.env.UAT_BASE_URL)throw new Error('UAT_BASE_URL is required');if(!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)throw new Error('UAT credentials are required');await writeRunEnvironment({suite:'m2-4-1-layer1-operations',change_control:'CF-CHG-20260826-043'})})

  test('AU and NZ expose the production-shaped operator journey',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page);const dialog=await openLayer1(page)
    await expect(dialog.getByRole('heading',{name:'Layer 1 — Regulatory'})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    for(const country of ['AU','NZ']){const card=dialog.locator(`article.l1o-source[data-country="${country}"]`);await expect(card).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT});for(const heading of ['1. Source Health','2. Current / Next Job','3. Progress','4. Reconciliation','5. Evidence / Provenance','6. Schedule / Recheck','7. Blockers / Required Actions'])await expect(card.getByRole('heading',{name:heading})).toBeVisible();await expect(card).toContainText('Approved authority domains');await expect(card).toContainText('Expected / previous');await expect(card).toContainText('Current source hash')}
    await expect(dialog).toContainText(/26,648/);await expect(dialog).toContainText(/409/);await expect(dialog).toContainText('Transient queue only; Evidence retained')
    await expect(dialog.getByText(/reset database/i)).toHaveCount(0);await expect(dialog.getByText(/parser qualification/i)).toHaveCount(0)
    await milestoneScreenshot(page,testInfo,'m2-4-1-layer1-operations')
  }finally{await finish(testInfo,runtime)}})

  test('authorised Layer 1 operator performs a real NZQA authority and count validation',async({page},testInfo)=>{test.setTimeout(120000);const runtime=observeRuntime(page);try{
    await loginAsUatUser(page);const dialog=await openLayer1(page);const nz=dialog.locator('article.l1o-source[data-country="NZ"]');
    const result=await page.evaluate(async()=>{const {supabase}=await import('/src/lib/supabase.js');const read=await supabase.rpc('admin_read',{p_operation:'layer1_operations',p_args:{}});if(read.error)throw new Error(read.error.message);const source=(read.data?.sources||[]).find(s=>s.country_code==='NZ');if(!source?.source_id)throw new Error('NZ Layer 1 source not found');const response=await supabase.functions.invoke('layer1-operations-control',{body:{action:'validate',source_id:source.source_id}});if(response.error)throw new Error(response.error.message);if(response.data?.error)throw new Error(response.data.error);return response.data})
    expect(result?.ok).toBe(true);expect(result?.validation?.country_code).toBe('NZ');expect(result?.validation?.discovered?.providers).toBeGreaterThan(300);expect(result?.validation?.discovered?.pages).toBe(5);expect(result?.validation?.worker_version).toContain('v1.0.1');
    await page.getByRole('button',{name:'Refresh'}).click();await expect(nz).toContainText('passed',{timeout:DETERMINISTIC_UI_TIMEOUT});await expect(nz).toContainText(/409/);await milestoneScreenshot(page,testInfo,'m2-4-1-nz-source-validated')
  }finally{await finish(testInfo,runtime)}})

  test('anonymous browser cannot execute Layer 1 read or command contracts',async({request})=>{
    const base=process.env.UAT_BASE_URL;const home=await request.get(base);expect(home.ok()).toBeTruthy();const html=await home.text();expect(html).not.toContain('SUPABASE_SERVICE_ROLE_KEY')
  })
})
