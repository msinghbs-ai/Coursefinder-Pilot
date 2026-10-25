// Guards: M2.4.4: A25 Evidence type-aware preview and screenshot lineage
import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, DETERMINISTIC_UI_TIMEOUT, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'

const JSON_EVIDENCE='eb305cd4-577e-4ced-988b-243fc3318f6e'
const HTML_EVIDENCE='55026c98-20f6-4500-9173-071070b85761'
const SCREENSHOT_EVIDENCE='e465eb03-e983-4007-b3f5-d63d00c925fe'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}
async function openEvidence(page,id){
  await page.evaluate(evidenceId=>{location.hash='#evidence?evidence_id='+encodeURIComponent(evidenceId)},id)
  const drawer=page.locator('.evidence-drawer')
  await expect(drawer).toBeVisible({timeout:20000})
  return drawer
}

test.describe('A25 Evidence type-aware preview and screenshot lineage @deployed',()=>{
  test.beforeAll(async()=>{await writeRunEnvironment({suite:'m2-4-4-a25-evidence-preview-integrity',change_control:'CF-CHG-20260830-048'})})

  // v2.15.293: the one-screen Evidence panel (admin_evidence_summary) has no inline preview or related-screenshot card. Each saved file
  // shows its own type under Technical details and View page opens that file only, so a JSON or screenshot file never inherits a screenshot.
  async function ownType(drawer,mime){
    await expect(drawer.locator('.ev-sum-actions').getByRole('button',{name:'View page'})).toBeVisible({timeout:20000})
    const tech=drawer.locator('details.ev-sum-tech')
    await tech.locator('summary').click()
    await expect(tech.locator('dd').filter({hasText:mime}).first()).toBeVisible()
    await expect(drawer.locator('.evidence-visual-card')).toHaveCount(0)
  }

  test('JSON Evidence shows its own JSON type and never inherits a website screenshot',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    const drawer=await openEvidence(page,JSON_EVIDENCE)
    await expect(drawer.locator('h2')).toHaveText('Saved data file')
    await ownType(drawer,/json/i)
    await milestoneScreenshot(page,testInfo,'a25-json-evidence')
  }finally{await finish(testInfo,runtime)}})

  test('HTML Evidence shows its own HTML type',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    const drawer=await openEvidence(page,HTML_EVIDENCE)
    await ownType(drawer,/text\/html/i)
    await milestoneScreenshot(page,testInfo,'a25-html-evidence')
  }finally{await finish(testInfo,runtime)}})

  test('Screenshot Evidence shows its own image type rather than a related thumbnail',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    const drawer=await openEvidence(page,SCREENSHOT_EVIDENCE)
    await ownType(drawer,/image\//i)
    await milestoneScreenshot(page,testInfo,'a25-screenshot-own-image')
  }finally{await finish(testInfo,runtime)}})
})
