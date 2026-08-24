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

test.describe('CourseFinder deployed Course Detail PIM v2.14.1 acceptance @deployed',()=>{
  test.beforeAll(async()=>{
    if(!process.env.UAT_BASE_URL)throw new Error('UAT_BASE_URL is required for deployed acceptance.')
    if(!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)throw new Error('UAT credentials are required for deployed acceptance.')
    await writeRunEnvironment({suite:'deployed-course-detail-v2.14.1',course_id:COURSE_ID})
  })

  test('Federation Bachelor of Arts shows concise facts, layer provenance and responsive reversible Evidence navigation',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await page.goto(`${process.env.UAT_BASE_URL}/#courses?id=${COURSE_ID}`)
      const drawer=page.locator('aside.m-drawer')
      await expect(drawer).toBeVisible({timeout:45_000})
      await expect(drawer.getByRole('heading',{name:'Bachelor of Arts',exact:true})).toBeVisible()
      await expect(page.locator('#governed-runtime-marker')).toContainText('PIM Admin v2.14.1')

      const official=drawer.getByRole('link',{name:/Open first-party page/i})
      await expect(official).toBeVisible()
      await expect(official).toHaveAttribute('href',COURSE_URL)

      await expect(drawer.getByRole('heading',{name:'Fees',exact:true})).toHaveCount(1)
      await expect(drawer.getByText('Registered CRICOS course cost',{exact:true})).toBeVisible()
      await expect(drawer.getByText('Current Provider tuition',{exact:true})).toBeVisible()
      await expect(drawer.getByText('AUD 77,100',{exact:true})).toBeVisible()
      await expect(drawer.getByText('No evidence-backed current Provider tuition captured.',{exact:true})).toBeVisible()
      await expect(drawer.getByText('Fee semantics',{exact:true})).toHaveCount(0)

      await expect(drawer.getByText('L1',{exact:true}).first()).toBeVisible()
      await expect(drawer.getByText('L2',{exact:true}).first()).toBeVisible()

      await expect(drawer.getByRole('heading',{name:'Categories',exact:true})).toHaveCount(0)
      await expect(drawer.getByRole('heading',{name:'Collections',exact:true})).toHaveCount(0)
      await expect(drawer.getByRole('heading',{name:'Academic options',exact:true})).toHaveCount(0)

      await expect(drawer.getByRole('heading',{name:'Regulatory facts',exact:true})).toBeVisible()
      await expect(drawer.getByText(/Authoritative CRICOS observations retained from Layer 1/)).toBeVisible()
      await expect(drawer.getByText(/CRICOS registration/i).first()).toBeVisible()

      const evidenceSection=drawer.locator('section.m-detail-section').filter({has:drawer.getByRole('heading',{name:'Evidence',exact:true})})
      await expect(evidenceSection).toBeVisible()
      const openEvidence=evidenceSection.getByText('Open Evidence',{exact:true}).first()
      await expect(openEvidence).toBeVisible()
      await milestoneScreenshot(page,testInfo,'federation-course-detail-v2-14-1')

      const started=Date.now()
      await openEvidence.click()
      await expect(page).toHaveURL(/#evidence\?evidence_id=.*return_course_id=/,{timeout:10_000})
      await expect(page.locator('aside.evidence-drawer')).toBeVisible({timeout:45_000})
      await expect.poll(()=>Date.now()-started,{timeout:10_000}).toBeLessThan(10_000)
      const back=page.getByRole('button',{name:/Back to Course/i})
      await expect(back).toBeVisible()
      await milestoneScreenshot(page,testInfo,'federation-course-evidence-return-v2-14-1')
      await back.click()
      await expect(page).toHaveURL(new RegExp(`#courses\\?id=${COURSE_ID}`))
      await expect(page.locator('aside.m-drawer')).toBeVisible({timeout:45_000})
    }finally{
      await finish(testInfo,runtime)
    }
  })
})
