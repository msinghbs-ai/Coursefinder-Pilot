import { test, expect } from '@playwright/test'
import {
  attachRuntimeEvidence,
  assertNoServerErrors,
  loginAsUatUser,
  milestoneScreenshot,
  observeRuntime,
  writeRunEnvironment,
} from './support/runtime-evidence.mjs'

const COURSE_ID='3ea5e651-dbcc-4ef4-8143-1de6900e012e'
const COURSE_URL='https://www.federation.edu.au/courses/dhm5-bachelor-of-arts/'

async function finish(testInfo,runtime){
  await attachRuntimeEvidence(testInfo,runtime)
  assertNoServerErrors(runtime)
}

test.describe('CourseFinder deployed Course Detail PIM v2.14.2 recovery acceptance @deployed',()=>{
  test.beforeAll(async()=>{
    if(!process.env.UAT_BASE_URL)throw new Error('UAT_BASE_URL is required for deployed acceptance.')
    if(!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)throw new Error('UAT credentials are required for deployed acceptance.')
    await writeRunEnvironment({suite:'deployed-course-detail-v2.14.2-recovery',course_id:COURSE_ID})
  })

  test('Federation Bachelor of Arts remains responsive and Evidence opens without locking the page',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await page.goto(`${process.env.UAT_BASE_URL}/#courses?id=${COURSE_ID}`)
      const drawer=page.locator('aside.m-drawer')
      await expect(drawer).toBeVisible({timeout:45_000})
      await expect(drawer.getByRole('heading',{name:'Bachelor of Arts',exact:true})).toBeVisible()
      await expect(page.locator('#governed-runtime-marker')).toContainText('PIM Admin v2.14.2')

      const official=drawer.getByRole('link',{name:/Open first-party page/i})
      await expect(official).toBeVisible()
      await expect(official).toHaveAttribute('href',COURSE_URL)

      await expect(drawer.getByRole('heading',{name:'Fees',exact:true})).toHaveCount(1)
      await expect(drawer.getByText('AUD 77,100',{exact:true})).toBeVisible()
      await expect(drawer.getByText('L1',{exact:true}).first()).toBeVisible()
      await expect(drawer.getByText('L2',{exact:true}).first()).toBeVisible()

      const evidenceSection=drawer.locator('section.m-detail-section').filter({has:drawer.getByRole('heading',{name:'Evidence',exact:true})})
      const openEvidence=evidenceSection.getByText('Open Evidence',{exact:true}).first()
      await expect(openEvidence).toBeVisible()
      await openEvidence.click()
      await expect(page).toHaveURL(/#evidence\?evidence_id=/,{timeout:10_000})
      await expect(page.locator('aside.evidence-drawer')).toBeVisible({timeout:45_000})
      await expect(page.locator('.evidence-page')).toBeVisible()
      await milestoneScreenshot(page,testInfo,'federation-course-evidence-v2-14-2-responsive')
    }finally{
      await finish(testInfo,runtime)
    }
  })
})
