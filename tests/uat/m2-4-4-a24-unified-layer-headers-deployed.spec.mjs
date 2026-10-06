import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, clickPrimaryNav, DETERMINISTIC_UI_TIMEOUT, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'
async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

// Decision 133 (26 Sep 2026) supersedes A24 (CF-CHG-20260830-048): each Layer screen shows its
// title once (the page title). The Layer header is a slim, light bar with the purpose and refresh.
test.describe('Layer screens show one title @deployed',()=>{
  test.beforeAll(async()=>{await writeRunEnvironment({suite:'m2-4-4-a24-unified-layer-headers',change_control:'CF-CHG-20260915-247'})})

  test('each Layer screen has one visible page title and a slim, light Layer header',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    for(const [navLabel,layer] of [['Layer 1 — Operations','1'],['Layer 2 — Enrichment','2'],['Layer 3 — AI Interpretation','3'],['Layer 4 — Human Resolution','4']]){
      await clickPrimaryNav(page,navLabel)
      const header=page.locator(`[data-layer-header="${layer}"]`)
      await expect(header).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
      await expect(page.getByRole('heading',{name:navLabel,exact:true}).first()).toBeVisible()
      await expect(header.getByRole('heading',{name:navLabel,exact:true})).toHaveCount(0)
      const visibleTitles=await page.evaluate(t=>[...document.querySelectorAll('h1')].filter(h=>h.offsetParent!==null&&h.textContent.trim()===t).length,navLabel)
      expect(visibleTitles).toBe(1)
      const state=await header.evaluate(el=>({background:getComputedStyle(el).backgroundColor,width:el.scrollWidth,client:el.clientWidth}))
      expect(state.background).not.toBe('rgb(23, 32, 51)')
      expect(state.width).toBeLessThanOrEqual(state.client+2)
    }
    await milestoneScreenshot(page,testInfo,'a24-one-title-per-layer-screen')
  }finally{await finish(testInfo,runtime)}})
})
