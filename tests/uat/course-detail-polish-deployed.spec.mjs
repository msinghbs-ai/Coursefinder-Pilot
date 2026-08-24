import { test, expect } from '@playwright/test'
import {
  attachRuntimeEvidence,
  assertNoServerErrors,
  loginAsUatUser,
  milestoneScreenshot,
  observeRuntime,
  writeRunEnvironment,
} from './support/runtime-evidence.mjs'

const ARTS_ID='3ea5e651-dbcc-4ef4-8143-1de6900e012e'
const ARTS_URL='https://www.federation.edu.au/courses/dhm5-bachelor-of-arts/'
const SCIENCE_HONOURS_ID='87e23eda-5676-4601-b512-b337ee2b48e6'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CourseFinder deployed Course Detail PIM v2.15.1 recovery acceptance @deployed',()=>{
  test.beforeAll(async()=>{
    if(!process.env.UAT_BASE_URL)throw new Error('UAT_BASE_URL is required for deployed acceptance.')
    if(!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)throw new Error('UAT credentials are required for deployed acceptance.')
    await writeRunEnvironment({suite:'deployed-course-detail-v2.15.1-stable-drawer-recovery'})
  })

  test('Federation Bachelor of Arts drawer renders and Evidence remains responsive',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await page.goto(`${process.env.UAT_BASE_URL}/#courses?id=${ARTS_ID}`)
      const drawer=page.locator('aside.m-drawer')
      await expect(drawer).toBeVisible({timeout:45_000})
      await expect(drawer.getByRole('heading',{name:'Bachelor of Arts',exact:true})).toBeVisible()
      await expect(page.locator('#governed-runtime-marker')).toContainText('PIM Admin v2.15.1')
      await expect(drawer.getByRole('link',{name:/Open first-party page/i}).first()).toHaveAttribute('href',ARTS_URL)
      await expect(drawer.getByRole('heading',{name:'Fees',exact:true})).toBeVisible()
      await expect(drawer.getByText('English requirement',{exact:true})).toBeVisible()
      await expect(drawer.getByText(/IELTS Academic/i)).toBeVisible()
      await expect(drawer.getByText(/Overall score 6/i)).toBeVisible()
      await expect(drawer.getByRole('heading',{name:'Operational state',exact:true})).toBeVisible()
      await milestoneScreenshot(page,testInfo,'course-drawer-v2-15-1-recovery')

      const evidenceSection=drawer.locator('section.m-detail-section').filter({has:drawer.getByRole('heading',{name:'Evidence',exact:true})})
      const openEvidence=evidenceSection.getByText('Open Evidence',{exact:true}).first()
      await expect(openEvidence).toBeVisible()
      await openEvidence.click()
      await expect(page).toHaveURL(/#evidence\?evidence_id=/,{timeout:10_000})
      await expect(page.locator('aside.evidence-drawer')).toBeVisible({timeout:45_000})
      await expect(page.locator('.evidence-page')).toBeVisible()
    }finally{await finish(testInfo,runtime)}
  })

  test('Federation Science Honours drawer renders despite unresolved enrichment gaps',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await page.goto(`${process.env.UAT_BASE_URL}/#courses?id=${SCIENCE_HONOURS_ID}`)
      const drawer=page.locator('aside.m-drawer')
      await expect(drawer).toBeVisible({timeout:45_000})
      await expect(drawer.getByRole('heading',{name:'Bachelor of Science (Honours)',exact:true})).toBeVisible()
      await expect(drawer.getByRole('heading',{name:'Fees',exact:true})).toBeVisible()
      await expect(drawer.getByText('English requirement',{exact:true})).toBeVisible()
      await expect(drawer.getByRole('heading',{name:'Operational state',exact:true})).toBeVisible()
      await milestoneScreenshot(page,testInfo,'science-honours-v2-15-1-recovery')
    }finally{await finish(testInfo,runtime)}
  })
})
