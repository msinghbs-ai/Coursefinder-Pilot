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
async function clearCourseLayoutPreference(page){await page.evaluate(()=>{for(const k of Object.keys(localStorage))if(k.startsWith('coursefinder:pim:course-detail:section-order:'))localStorage.removeItem(k)})}

test.describe('CourseFinder deployed Course Detail PIM v2.15.4 standardised operator UX @deployed',()=>{
  test.beforeAll(async()=>{
    if(!process.env.UAT_BASE_URL)throw new Error('UAT_BASE_URL is required for deployed acceptance.')
    if(!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)throw new Error('UAT credentials are required for deployed acceptance.')
    await writeRunEnvironment({suite:'deployed-course-detail-v2.15.4-standardised-layout'})
  })

  test('Federation Bachelor of Arts renders standardised decision layout and Evidence remains responsive',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await page.goto(`${process.env.UAT_BASE_URL}/#courses?id=${ARTS_ID}`)
      const drawer=page.locator('aside.m-drawer')
      await expect(drawer).toBeVisible({timeout:45_000})
      await expect(drawer.getByRole('heading',{name:'Bachelor of Arts',exact:true})).toBeVisible()
      await expect(page.locator('#governed-runtime-marker')).toContainText('PIM Admin v2.15.4')
      await expect(drawer.getByRole('link',{name:/Open first-party page/i}).first()).toHaveAttribute('href',ARTS_URL)
      await expect(drawer.getByRole('heading',{name:'Fees & entry requirements',exact:true})).toBeVisible()
      await expect(drawer.getByText('Registered tuition',{exact:true})).toBeVisible()
      await expect(drawer.getByText('AUD 77,100',{exact:true})).toBeVisible()
      await expect(drawer.getByText('English requirement',{exact:true})).toBeVisible()
      await expect(drawer.getByText(/IELTS Academic/i)).toBeVisible()
      await expect(drawer.getByText(/Overall score 6/i)).toBeVisible()
      await expect(drawer.getByRole('heading',{name:'Locations',exact:true})).toBeVisible()
      await expect(drawer.getByRole('heading',{name:'Operational state',exact:true})).toBeVisible()
      await milestoneScreenshot(page,testInfo,'course-drawer-v2-15-4-standardised')

      // Evidence may be attached contextually to a fee/regulatory fact without needing a separate
      // generic Evidence blade. Either supported entry point must open the governed workspace.
      const contextual=drawer.getByRole('button',{name:'Evidence',exact:true}).first()
      const rowAction=drawer.getByText('Open Evidence',{exact:true}).first()
      if(await contextual.count()){
        await expect(contextual).toBeVisible()
        await contextual.click()
      }else{
        await expect(rowAction).toBeVisible()
        await rowAction.click()
      }
      await expect(page).toHaveURL(/#evidence\?evidence_id=/,{timeout:10_000})
      await expect(page.locator('aside.evidence-drawer')).toBeVisible({timeout:45_000})
      await expect(page.locator('.evidence-page')).toBeVisible()
    }finally{await finish(testInfo,runtime)}
  })

  test('Science Honours keeps required gaps visible and hides empty non-required sections',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await page.goto(`${process.env.UAT_BASE_URL}/#courses?id=${SCIENCE_HONOURS_ID}`)
      const drawer=page.locator('aside.m-drawer')
      await expect(drawer).toBeVisible({timeout:45_000})
      await expect(drawer.getByRole('heading',{name:'Bachelor of Science (Honours)',exact:true})).toBeVisible()
      await expect(page.locator('#governed-runtime-marker')).toContainText('PIM Admin v2.15.4')
      await expect(drawer.getByText('Current Provider tuition',{exact:true})).toBeVisible()
      await expect(drawer.getByText('English requirement',{exact:true})).toBeVisible()
      await expect(drawer.getByText('Delivery',{exact:true})).toBeVisible()
      await expect(drawer.getByLabel('Layer 2 attempted and unresolved; awaiting Layer 3')).toHaveCount(2)
      await expect(drawer.getByText('Awaiting L3',{exact:true})).toHaveCount(2)
      await expect(drawer.getByText('Awaiting L2',{exact:true})).toHaveCount(1)
      await expect(drawer.getByRole('heading',{name:'Academic options',exact:true})).toHaveCount(0)
      await expect(drawer.getByRole('heading',{name:'Categories',exact:true})).toHaveCount(0)
      await expect(drawer.getByRole('heading',{name:'Collections',exact:true})).toHaveCount(0)
      await expect(drawer.getByRole('heading',{name:'Locations',exact:true})).toBeVisible()
      await expect(drawer.getByRole('heading',{name:'Operational state',exact:true})).toBeVisible()
      await milestoneScreenshot(page,testInfo,'science-honours-v2-15-4-required-gaps-only')
    }finally{await finish(testInfo,runtime)}
  })

  test('Course decision-card order persists for the signed-in user and can be restored',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await clearCourseLayoutPreference(page)
      await page.goto(`${process.env.UAT_BASE_URL}/#courses?id=${ARTS_ID}`)
      const drawer=page.locator('aside.m-drawer')
      await expect(drawer).toBeVisible({timeout:45_000})
      await expect(drawer.locator('.cf-reorder-wrap section h3').first()).toHaveText('Fees & entry requirements')
      await drawer.getByRole('button',{name:'Arrange sections',exact:true}).click()
      await drawer.getByRole('button',{name:'Move Locations up',exact:true}).click()
      await drawer.getByRole('button',{name:'Done arranging',exact:true}).click()
      let headings=drawer.locator('.cf-reorder-wrap section h3')
      await expect(headings.first()).toHaveText('Locations')
      await page.reload()
      await expect(drawer).toBeVisible({timeout:45_000})
      headings=drawer.locator('.cf-reorder-wrap section h3')
      await expect(headings.first()).toHaveText('Locations')
      await clearCourseLayoutPreference(page)
      await page.reload()
      await expect(drawer).toBeVisible({timeout:45_000})
      await expect(drawer.locator('.cf-reorder-wrap section h3').first()).toHaveText('Fees & entry requirements')
    }finally{await clearCourseLayoutPreference(page).catch(()=>{});await finish(testInfo,runtime)}
  })
})
