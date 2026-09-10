import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, clickPrimaryNav, DETERMINISTIC_UI_TIMEOUT, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CF-092 Scheduled Jobs configuration @deployed',()=>{
  test.beforeAll(async()=>{await writeRunEnvironment({suite:'cf-092-scheduled-jobs-config',change_control:'CF-CHG-20260910-092'})})

  test('Scheduling presents governed Layer 1-3 control and readable run follow-through without mutating state',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    await clickPrimaryNav(page,'Scheduled Tasks')
    await expect(page.getByRole('heading',{name:'Scheduled Jobs & Run Control',exact:true})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    await clickPrimaryNav(page,'Administration')
    await expect(page.getByRole('heading',{name:'Administration overview',exact:true})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    await expect(page.getByRole('tab',{name:'Scheduling',exact:true})).toHaveCount(0)
    await clickPrimaryNav(page,'Scheduled Tasks')
    await expect(page.getByRole('heading',{name:'Scheduled Jobs & Run Control',exact:true})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    const workspace=page.locator('.cf-scheduler-v2-native')
    for(const header of ['Layer','Country','Scheduled Target','Freshness Policy','Cadence','Next Run','Schedule Status','Actions'])await expect(workspace.getByRole('columnheader',{name:header,exact:true}).first()).toBeVisible()
    await expect(workspace.getByRole('heading',{name:'Latest Refresh Queue',exact:true})).toBeVisible()
    await expect(workspace.getByRole('heading',{name:'Recent Job Runs',exact:true})).toBeVisible()
    await expect(workspace.getByRole('button',{name:'Open Jobs',exact:true})).toBeVisible()
    await expect(workspace.getByRole('button',{name:'Open Evidence',exact:true})).toBeVisible()
    for(const layer of [1,2,3])await expect(workspace.getByRole('button',{name:new RegExp(`Layer ${layer}`)}).first()).toBeVisible()
    const edit=workspace.getByRole('button',{name:'Edit schedule',exact:true}).first()
    const run=workspace.getByRole('button',{name:'Run on demand',exact:true}).first()
    await expect(edit).toBeVisible();await expect(run).toBeVisible()
    await edit.click()
    await expect(page.getByRole('dialog',{name:'Edit schedule'})).toBeVisible()
    await expect(page.getByLabel('Governance reason')).toBeVisible()
    await page.getByRole('button',{name:'Cancel',exact:true}).click()
    await expect(page.getByRole('dialog',{name:'Edit schedule'})).toHaveCount(0)
    await milestoneScreenshot(page,testInfo,'scheduled-jobs-config')
  }finally{await finish(testInfo,runtime)}})
})