import fs from 'node:fs/promises'
import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, clickPrimaryNav, DETERMINISTIC_UI_TIMEOUT, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

// Permanent CF-053 corrective contract.
// Includes stale-control handoff coverage.

test.describe('M2.5 Layer 2 finalizer fairness and wave classification @deployed',()=>{
  test.beforeAll(async()=>{await writeRunEnvironment({suite:'m2-5-layer2-finalizer-fairness',change_control:'CF-CHG-20260901-053'})})

  test('source contract prioritises dispatchable pattern work without deleting pending controls',async()=>{
    const [sql,stale]=await Promise.all([
      fs.readFile('supabase/migrations/20260901083800_m2_5_layer2_finalizer_fairness.sql','utf8'),
      fs.readFile('supabase/migrations/20260901085000_m2_5_layer2_stale_pattern_control_handoff.sql','utf8')
    ])
    expect(sql).toContain("then 'pending_dispatch'")
    expect(sql).toContain("then 'pending_control'")
    expect(sql).toContain("coalesce(nullif(q.result_summary->>'qualification_finalizer_at','')::timestamptz")
    expect(sql).toContain("'qualification_finalizer_selection_class',v_selection_class")
    expect(sql).toContain("'qualification_finalizer_progressed',v_progressed")
    expect(sql).toContain("'recorded_failed_items',r.failed_items")
    expect(sql).toContain("'rescheduled_items',coalesce(classify.acceptance_isolation_items,0)")
    expect(sql).toContain("lower(coalesce(ai.blocker,'')) like '%acceptance isolation%'")
    expect(sql).not.toContain("delete from pipeline.layer2_scale_qualification_items")
    expect(stale).toContain("now()-interval '30 minutes'")
    expect(stale).toContain("'pattern_control_status','incomplete_timeout'")
    expect(stale).toContain("'reason','pattern_control_incomplete_timeout'")
    expect(stale).toContain("'handoff','layer3_source_pattern_interpretation'")
  })

  test('terminal parent presents acceptance-isolation markers separately from operational failures',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    await clickPrimaryNav(page,'Layer 2 — Enrichment')
    const ws=page.getByLabel('Layer 2 Operations')
    await expect(ws).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    // Decision 220 (v2.15.147): the old Layer 2 pipeline is retired (its jobs paused); its run lineage panel is gone and
    // the Overview lists only actionable Layer 2 items.
    await expect(ws.locator('[data-l2-latest-terminal]')).toHaveCount(0)
    await expect(ws.locator('[data-l2-action]')).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    await milestoneScreenshot(page,testInfo,'m2-5-layer2-finalizer-fairness')
  }finally{await finish(testInfo,runtime)}})
})
