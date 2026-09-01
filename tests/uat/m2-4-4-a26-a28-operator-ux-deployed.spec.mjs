import fs from 'node:fs/promises'
import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, clickPrimaryNav, DETERMINISTIC_UI_TIMEOUT, loginAsUatUser, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'
import { openLayer2, openLayer3 } from './support/navigation.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('M2.4.4 A26-A28 operator UX @deployed',()=>{
  test.beforeAll(async()=>{await writeRunEnvironment({suite:'m2-4-4-a26-a28-operator-ux',change_control:'CF-CHG-20260830-048'})})

  test('Administration opens a non-empty default workspace and switches sub-contexts',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    await clickPrimaryNav(page,'Administration')
    await expect(page.getByRole('heading',{name:'Administration overview',exact:true})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    const tabs=page.getByRole('tab')
    await expect(tabs).not.toHaveCount(0)
    const acquisition=page.getByRole('tab',{name:'Acquisition',exact:true})
    await acquisition.click()
    await expect(acquisition).toHaveAttribute('aria-selected','true')
    await expect(page.getByRole('heading',{name:'Layer 2 Acquisition Providers',exact:true})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    const scheduling=page.getByRole('tab',{name:'Scheduling',exact:true})
    await scheduling.click()
    await expect(scheduling).toHaveAttribute('aria-selected','true')
    await expect(page.getByRole('heading',{name:'Source/entity freshness policies',exact:true})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  }finally{await finish(testInfo,runtime)}})

  test('Layer 2 uses production wording, canonical Jobs/Evidence links and actionable blockers only',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    const ws=await openLayer2(page)
    await expect(ws.getByRole('button',{name:'Start production enrichment',exact:true})).toBeVisible()
    await expect(ws.getByText(/Parent [0-9a-f]{8}…/i).first()).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    await expect(ws.getByText(/scheduled remainder/i).first()).toBeVisible()
    await expect(ws.getByText(/no manual per-Provider action is required/i)).toHaveCount(0)
    await expect(ws.getByRole('button',{name:'Jobs',exact:true})).toBeVisible()
    await expect(ws.getByRole('button',{name:/Open Evidence/i})).toBeVisible()
    const blockerPanel=ws.locator('.l2o-blockers')
    if(await blockerPanel.count())await expect(blockerPanel.getByRole('heading',{name:'Action required',exact:true})).toBeVisible()
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
    await expect(ws.getByRole('heading',{name:'Current operations summary',exact:true})).toBeVisible()
    await expect(ws.getByText(/Governed Evidence awaiting interpretation/i)).toBeVisible()
    await expect(ws.getByRole('button',{name:'Open Jobs',exact:true}).first()).toBeVisible()
    await expect(ws.getByRole('button',{name:'Open Evidence',exact:true}).first()).toBeVisible()
    await expect(ws.getByRole('button',{name:'Pause',exact:true})).toHaveCount(0)
    await expect(ws.getByText(/managed centrally under Administration/i).first()).toBeVisible()
  }finally{await finish(testInfo,runtime)}})
})
