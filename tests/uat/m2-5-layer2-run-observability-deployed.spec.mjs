import fs from 'node:fs/promises'
import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, clickPrimaryNav, DETERMINISTIC_UI_TIMEOUT, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

// Permanent M2.5 corrective contract: terminal lineage must remain operator-visible.
test.describe('M2.5 Layer 2 terminal run observability correction @deployed',()=>{
  test.beforeAll(async()=>{await writeRunEnvironment({suite:'m2-5-layer2-run-observability',change_control:'CF-CHG-20260901-052'})})

  // Skipped in v2.15.203: this drives a Layer 2 screen retired in v2.15.200 (Decision 254). Its facts now live on Layer 2 > Adapters and Scheduled jobs > Jobs.
  test.skip('terminal production lineage remains visible and operator timestamps are rendered',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await clickPrimaryNav(page,'Layer 2 — Enrichment')
      await page.locator('.cf-page-tabs [role="tab"]').filter({hasText:'History'}).first().click({timeout:DETERMINISTIC_UI_TIMEOUT}) // v2.15.128
      const ws=page.getByLabel('Layer 2 Operations')
      await expect(ws).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})

      // Decision 220 (v2.15.147): the old pipeline is retired; History shows daily progress by country instead of its
      // batches, runs and fetches.
      await expect(ws.getByRole('heading',{name:'Daily progress',exact:true})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
      await expect(ws.locator('[data-l2-daily] tbody tr').first()).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
      await expect(ws.getByRole('heading',{name:'Current progress',exact:true})).toHaveCount(0)
      await milestoneScreenshot(page,testInfo,'m2-5-layer2-terminal-run-observability')
    } finally { await finish(testInfo,runtime) }
  })

  test('server and UI contracts distinguish qualification waiting and preserve terminal child lineage',async()=>{
    const migration=await fs.readFile('supabase/migrations/20260901062200_m2_5_layer2_run_observability_correction.sql','utf8')

    expect(migration).toContain("'status','qualification_waiting'")
    expect(migration).toContain("'observed_at',now()")
    expect(migration).toContain("wi.status in('dispatched','completed','failed')")
    expect(migration).toContain("'child_jobs',coalesce(items.child_jobs,0)")
    expect(migration).toContain("'evidence_count',coalesce(ev.evidence_count,0)")

    // v2.15.214: the old Layer 2 screen (and its sync-result texts) is deleted; Fetch an area was retired in v2.15.200.
  })
})
