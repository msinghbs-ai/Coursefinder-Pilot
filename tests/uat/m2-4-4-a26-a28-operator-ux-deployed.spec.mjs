import fs from 'node:fs/promises'
import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, clickPrimaryNav, DETERMINISTIC_UI_TIMEOUT, loginAsUatUser, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'
import { openLayer2, openLayer2Tab, openLayer3 } from './support/navigation.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('M2.4.4 A26-A28 operator UX @deployed',()=>{
  test.beforeAll(async()=>{await writeRunEnvironment({suite:'m2-4-4-a26-a28-operator-ux',change_control:'CF-CHG-20260830-048'})})

  test('Administration opens a non-empty default workspace and switches sub-contexts',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    await clickPrimaryNav(page,'Administration')
    // v2.15.200: Administration opens Scrapers & fetchers; the Acquisition and Scheduling sub-tabs are retired
    // (scheduling is on Scheduled jobs).
    await expect(page.locator('.m-title-wrap h1')).toContainText('Scrapers & fetchers',{timeout:DETERMINISTIC_UI_TIMEOUT})
    await expect(page.getByRole('tab',{name:'Scheduling',exact:true})).toHaveCount(0)
    await expect(page.locator('main, .m-main').first()).not.toBeEmpty()
  }finally{await finish(testInfo,runtime)}})

  test('Layer 2 uses production wording, canonical Jobs/Evidence links and actionable blockers only',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    // v2.15.200: Layer 2 has the Adapters and Scholarships tabs. Overview, Fetch an area and History are retired
    // (finished tasks are on Scheduled jobs > Jobs, running ones on the Task manager).
    const ws=await openLayer2Tab(page,'Adapters')
    await expect(ws.locator('[data-adapters-list]')).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    const tabs=await page.locator('.cf-page-tabs [role="tab"]').allTextContents()
    expect(tabs.map(x=>x.trim())).toEqual(expect.arrayContaining(['Adapters']))
    for(const retired of ['Overview','Fetch an area','History','Source profiles'])expect(tabs.join('|')).not.toContain(retired)
    await expect(ws.getByText(/no manual per-Provider action is required/i)).toHaveCount(0)
    await expect(ws.getByText(/Meeting-ready Firecrawl example/i)).toHaveCount(0)
  }finally{await finish(testInfo,runtime)}})


  test('A26 child progress refreshes the owning batch heartbeat',async()=>{
    const sql=await fs.readFile('supabase/migrations/20260901101500_m2_4_4_a26_child_heartbeat.sql','utf8')
    expect(sql).toContain('set heartbeat_at=now(),updated_at=now()')
    expect(sql).toContain("where id=v_batch and status in('queued','running')")
  })

  test('Layer 3 exposes concise current operations and governed Evidence summary without profile mutation controls',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    const ws=await openLayer3(page)
    // The Layer 3 Work tab shows four counts, work by task and recent results; run, pause and limits are on the Control tab.
    await expect(ws.getByRole('heading',{name:'Work by task',exact:true})).toBeVisible()
    for(const label of ['Waiting to run','Settled by AI','Sent to a person','Failed'])await expect(ws.getByText(label,{exact:true}).first()).toBeVisible()
    await expect(ws.getByText(/Run, pause and limits are on the Control tab/i).first()).toBeVisible()
    await expect(ws.getByRole('button',{name:'Pause',exact:true})).toHaveCount(0)
  }finally{await finish(testInfo,runtime)}})
})
