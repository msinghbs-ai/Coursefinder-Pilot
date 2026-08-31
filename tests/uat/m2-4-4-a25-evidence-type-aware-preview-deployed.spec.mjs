import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, DETERMINISTIC_UI_TIMEOUT, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'

const JSON_EVIDENCE='eb305cd4-577e-4ced-988b-243fc3318f6e'
const HTML_EVIDENCE='55026c98-20f6-4500-9173-071070b85761'
const SCREENSHOT_EVIDENCE='e465eb03-e983-4007-b3f5-d63d00c925fe'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}
async function openEvidence(page,id){
  await page.evaluate(evidenceId=>{location.hash='#evidence?evidence_id='+encodeURIComponent(evidenceId)},id)
  const drawer=page.locator('.evidence-drawer')
  await expect(drawer).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  return drawer
}

test.describe('A25 Evidence type-aware preview and screenshot lineage @deployed',()=>{
  test.beforeAll(async()=>{await writeRunEnvironment({suite:'m2-4-4-a25-evidence-preview-integrity',change_control:'CF-CHG-20260830-048'})})

  test('JSON Evidence is visibly JSON and never inherits a website screenshot',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    const drawer=await openEvidence(page,JSON_EVIDENCE)
    const preview=drawer.locator('[data-artifact-format="JSON"]')
    await expect(preview).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    await expect(preview).toContainText(/Structured JSON Evidence/i)
    await expect(drawer.locator('.evidence-visual-card')).toHaveCount(0)
    await expect(drawer.getByText('Layer2 Raw Json',{exact:true})).toBeVisible()
    await milestoneScreenshot(page,testInfo,'a25-json-evidence')
  }finally{await finish(testInfo,runtime)}})

  test('HTML Evidence can show only its exact same-attempt screenshot',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    const drawer=await openEvidence(page,HTML_EVIDENCE)
    await expect(drawer.locator('[data-artifact-format="HTML"]')).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    const visual=drawer.locator('.evidence-visual-card')
    await expect(visual).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    await expect(visual).toContainText(/Exact same-attempt website screenshot/i)
    await expect(visual.getByRole('button',{name:'Open screenshot Evidence'})).toBeVisible()
    await milestoneScreenshot(page,testInfo,'a25-html-related-screenshot')
  }finally{await finish(testInfo,runtime)}})

  test('Screenshot Evidence previews its own image rather than a related thumbnail',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    const drawer=await openEvidence(page,SCREENSHOT_EVIDENCE)
    const preview=drawer.locator('[data-artifact-format="SCREENSHOT"]')
    await expect(preview).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    await expect(preview).toContainText(/selected artifact itself/i)
    await expect(preview.locator('.evidence-own-image img')).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    await expect(drawer.locator('.evidence-visual-card')).toHaveCount(0)
    await milestoneScreenshot(page,testInfo,'a25-screenshot-own-image')
  }finally{await finish(testInfo,runtime)}})
})
