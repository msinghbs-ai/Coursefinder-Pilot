import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, DETERMINISTIC_UI_TIMEOUT, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'
async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('A24 unified Layer workspace headers @deployed',()=>{
  test.beforeAll(async()=>{await writeRunEnvironment({suite:'m2-4-4-a24-unified-layer-headers',change_control:'CF-CHG-20260830-048'})})

  test('all four canonical Layer routes use the Layer 2 dark header architecture',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    const cases=[
      ['Layer 1 — Authority','1','Layer 1 — Regulatory',/authoritative \/ regulatory/i],
      ['Layer 2 — Enrichment','2','Layer 2 — Enrichment',/background enrichment/i],
      ['Layer 3 — AI Interpretation','3','Layer 3 — AI Interpretation',/evidence-bound AI interpretation/i],
      ['Layer 4 — Human Resolution','4','Layer 4 — Human Resolution',/governed human resolution/i],
    ]
    for(const [navLabel,layer,title,eyebrow] of cases){
      await page.locator('.m-nav').getByRole('button',{name:navLabel,exact:true}).click()
      const header=page.locator(`[data-layer-header="${layer}"]`)
      await expect(header).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
      await expect(header.getByRole('heading',{name:title,exact:true})).toBeVisible()
      await expect(header).toContainText(eyebrow)
      const state=await header.evaluate(el=>({background:getComputedStyle(el).backgroundColor,width:el.scrollWidth,client:el.clientWidth}))
      expect(state.background).toBe('rgb(23, 32, 51)')
      expect(state.width).toBeLessThanOrEqual(state.client+2)
    }
    await milestoneScreenshot(page,testInfo,'a24-unified-layer-headers')
  }finally{await finish(testInfo,runtime)}})
})
