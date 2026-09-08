import fs from 'node:fs/promises'
import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, clickPrimaryNav, DETERMINISTIC_UI_TIMEOUT, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

// Permanent M2.5 corrective contract: terminal lineage must remain operator-visible.
test.describe('M2.5 Layer 2 terminal run observability correction @deployed',()=>{
  test.beforeAll(async()=>{await writeRunEnvironment({suite:'m2-5-layer2-run-observability',change_control:'CF-CHG-20260901-052'})})

  test('terminal production lineage remains visible and operator timestamps are rendered',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await clickPrimaryNav(page,'Layer 2 — Enrichment')
      const ws=page.getByLabel('Layer 2 Operations')
      await expect(ws).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})

      const attempts=ws.locator('.l2o-attempts .l2o-attempt')
      await expect(attempts.first()).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
      await expect(attempts.first().locator('small').first()).toContainText(/\d{1,2}[/.-]\d{1,2}[/.-]\d{4}/)

      const managed=ws.locator('.l2o-runs .l2o-run')
      await expect(managed.first()).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
      await expect(managed.first().locator('.l2o-state small')).toContainText(/\d{1,2}[/.-]\d{1,2}[/.-]\d{4}/)

      const latest=ws.locator('[data-l2-latest-terminal="true"]')
      if(await latest.count()){
        await expect(latest).toContainText('Latest terminal production run')
        await expect(latest).toContainText(/\b\d+ Jobs retained\b/)
        await expect(latest).not.toContainText('0 Jobs retained')
        await expect(latest).toContainText(/Evidence/)
      }

      await expect(ws.getByRole('heading',{name:'Current progress',exact:true})).toBeVisible()
      await expect(ws.getByText(/Active parent work is shown separately from the latest terminal production history/i)).toBeVisible()
      await milestoneScreenshot(page,testInfo,'m2-5-layer2-terminal-run-observability')
    } finally { await finish(testInfo,runtime) }
  })

  test('server and UI contracts distinguish qualification waiting and preserve terminal child lineage',async()=>{
    const migration=await fs.readFile('supabase/migrations/20260901062200_m2_5_layer2_run_observability_correction.sql','utf8')
    const ui=await fs.readFile('src/layer2-operations-entry.jsx','utf8')

    expect(migration).toContain("'status','qualification_waiting'")
    expect(migration).toContain("'observed_at',now()")
    expect(migration).toContain("wi.status in('dispatched','completed','failed')")
    expect(migration).toContain("'child_jobs',coalesce(items.child_jobs,0)")
    expect(migration).toContain("'evidence_count',coalesce(ev.evidence_count,0)")

    expect(ui).toContain("syncResult.status==='qualification_waiting'")
    expect(ui).toContain('Server observed {fmtDate(syncResult.observed_at)}')
    expect(ui).toContain("a.completed_at||a.started_at")
    expect(ui).toContain('data-l2-latest-terminal="true"')
    expect(ui).toContain('Jobs retained')
    expect(ui).toContain("setError('Production request was accepted, but the operator view could not refresh:")
  })
})
