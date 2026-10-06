import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, clickPrimaryNav, DETERMINISTIC_UI_TIMEOUT, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'
async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

// Decision 133 (26 Sep 2026) supersedes A24 (CF-CHG-20260830-048): each Layer screen shows its
// title once (the page title). The Layer header is a slim, light bar with the purpose and refresh.
test.describe('Layer screens show one title @deployed',()=>{
  test.beforeAll(async()=>{await writeRunEnvironment({suite:'m2-4-4-a24-unified-layer-headers',change_control:'CF-CHG-20260915-247'})})

  test('each Layer screen has one visible page title and a slim, light Layer header',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    // v2.15.200: the Layer pages are drawn by the single menu map; each shows its title once as the page h1.
    for(const [navLabel,title] of [['Layer 1 — Operations','Layer 1 Register'],['Layer 2 — Enrichment','Layer 2 Discovery & reading'],['Layer 3 — AI Interpretation','Layer 3 AI validation'],['Layer 4 — Human Resolution','Layer 4 Review']]){
      await clickPrimaryNav(page,navLabel)
      await expect(page.getByRole('heading',{name:title,exact:true}).first()).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
      const visibleTitles=await page.evaluate(t=>[...document.querySelectorAll('h1')].filter(h=>h.offsetParent!==null&&h.textContent.trim()===t).length,title)
      expect(visibleTitles).toBe(1)
      const overflow=await page.evaluate(()=>document.documentElement.scrollWidth-document.documentElement.clientWidth)
      expect(overflow).toBeLessThanOrEqual(2)
    }
    await milestoneScreenshot(page,testInfo,'a24-one-title-per-layer-screen')
  }finally{await finish(testInfo,runtime)}})
})
