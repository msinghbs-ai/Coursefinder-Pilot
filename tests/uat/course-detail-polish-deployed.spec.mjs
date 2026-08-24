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
const REQUIRED_ATTRIBUTES=['Provider','CRICOS / Course code','Study level','Field of study','Duration','Delivery mode','Official Course URL','Course description','Current Provider tuition','Intakes','English requirement','Campuses','Academic options','Categories','Collections','Regulatory facts']

async function finish(testInfo,runtime){
  await attachRuntimeEvidence(testInfo,runtime)
  assertNoServerErrors(runtime)
}

test.describe('CourseFinder deployed Course Detail PIM v2.15 field-state acceptance @deployed',()=>{
  test.beforeAll(async()=>{
    if(!process.env.UAT_BASE_URL)throw new Error('UAT_BASE_URL is required for deployed acceptance.')
    if(!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)throw new Error('UAT credentials are required for deployed acceptance.')
    await writeRunEnvironment({suite:'deployed-course-detail-v2.15-field-state'})
  })

  test('Course drawer stays responsive and every governed attribute remains visible',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await page.goto(`${process.env.UAT_BASE_URL}/#courses?id=${ARTS_ID}`)
      const drawer=page.locator('aside.m-drawer')
      await expect(drawer).toBeVisible({timeout:45_000})
      await expect(drawer.getByRole('heading',{name:'Bachelor of Arts',exact:true})).toBeVisible()
      await expect(page.locator('#governed-runtime-marker')).toContainText('PIM Admin v2.15.0')
      await expect(drawer.getByRole('link',{name:/Open first-party page/i}).first()).toHaveAttribute('href',ARTS_URL)
      const attributes=drawer.locator('section.m-detail-section').filter({has:drawer.getByRole('heading',{name:'Course attributes',exact:true})})
      await expect(attributes).toBeVisible()
      for(const label of REQUIRED_ATTRIBUTES)await expect(attributes.getByText(label,{exact:true}).first()).toBeVisible()
      await expect(drawer.getByText('English requirement',{exact:true}).first()).toBeVisible()
      await expect(drawer.getByText(/IELTS Academic/i).first()).toBeVisible()
      await expect(drawer.getByText(/Overall score 6/i).first()).toBeVisible()
      await milestoneScreenshot(page,testInfo,'course-attributes-v2-15-all-visible')

      const evidenceSection=drawer.locator('section.m-detail-section').filter({has:drawer.getByRole('heading',{name:'Evidence',exact:true})})
      const openEvidence=evidenceSection.getByText('Open Evidence',{exact:true}).first()
      await expect(openEvidence).toBeVisible()
      await openEvidence.click()
      await expect(page).toHaveURL(/#evidence\?evidence_id=/,{timeout:10_000})
      await expect(page.locator('aside.evidence-drawer')).toBeVisible({timeout:45_000})
      await expect(page.locator('.evidence-page')).toBeVisible()
    }finally{
      await finish(testInfo,runtime)
    }
  })

  test('Science Honours distinguishes not-attempted L2, failed L2 and direct L4 fields',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await page.goto(`${process.env.UAT_BASE_URL}/#courses?id=${SCIENCE_HONOURS_ID}`)
      const drawer=page.locator('aside.m-drawer')
      await expect(drawer).toBeVisible({timeout:45_000})
      await expect(drawer.getByRole('heading',{name:'Bachelor of Science (Honours)',exact:true})).toBeVisible()
      const attributes=drawer.locator('section.m-detail-section').filter({has:drawer.getByRole('heading',{name:'Course attributes',exact:true})})
      await expect(attributes).toBeVisible()
      for(const label of REQUIRED_ATTRIBUTES)await expect(attributes.getByText(label,{exact:true}).first()).toBeVisible()

      await expect(attributes.getByLabel('Layer 2 attempted and unresolved; awaiting Layer 3')).toHaveCount(2)
      await expect(attributes.getByText('Awaiting L3',{exact:true})).toHaveCount(2)
      await expect(attributes.getByText('Awaiting L2',{exact:true})).toHaveCount(2)
      await expect(attributes.getByLabel('Direct Layer 4 input')).toHaveCount(2)
      await expect(attributes.getByText('L4 input',{exact:true})).toHaveCount(2)
      await expect(attributes.getByText('English requirement',{exact:true})).toBeVisible()
      await expect(attributes.getByText('—',{exact:true}).first()).toBeVisible()
      await expect(attributes.getByRole('button',{name:/L4 edit/i})).toHaveCount(4)
      await expect(attributes.getByRole('button',{name:/L4 review/i})).toHaveCount(5)
      await milestoneScreenshot(page,testInfo,'science-honours-v2-15-layer-state-matrix')
    }finally{
      await finish(testInfo,runtime)
    }
  })
})
