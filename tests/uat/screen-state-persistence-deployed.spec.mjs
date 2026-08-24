import { test, expect } from '@playwright/test'
import {
  attachRuntimeEvidence,
  assertNoServerErrors,
  loginAsUatUser,
  milestoneScreenshot,
  observeRuntime,
  writeRunEnvironment,
} from './support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}
async function clearSavedScreenState(page){await page.evaluate(()=>{for(const k of Object.keys(localStorage))if(k.startsWith('coursefinder:pim:screen-state:v1:'))localStorage.removeItem(k)})}
function filterButton(page,label){return page.locator('.m-catalogue-panel .m-filter-button').filter({has:page.getByText(label,{exact:true})}).first()}

test.describe('CourseFinder PIM v2.15.3 per-user screen state @deployed',()=>{
  test.beforeAll(async()=>{
    if(!process.env.UAT_BASE_URL)throw new Error('UAT_BASE_URL is required for deployed acceptance.')
    if(!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)throw new Error('UAT credentials are required for deployed acceptance.')
    await writeRunEnvironment({suite:'deployed-pim-v2.15.3-screen-state'})
  })

  test('Course search and filters survive reload and logout/login until Clear',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await clearSavedScreenState(page)
      await page.goto(`${process.env.UAT_BASE_URL}/#courses`)
      const panel=page.locator('.m-catalogue-panel')
      await expect(panel).toBeVisible({timeout:45_000})

      const search=panel.locator('.m-searchbox input')
      await expect(search).toHaveValue('')
      await search.fill('088661B')
      const country=filterButton(page,'Country')
      await expect(country.locator('strong')).toHaveText('All')
      await country.click()
      const countryPopover=country.locator('xpath=..').locator('.m-filter-popover')
      await countryPopover.getByRole('button',{name:/Australia/i}).click()
      await expect(search).toHaveValue('088661B')
      await expect(country.locator('strong')).toHaveText('Australia')
      await page.waitForTimeout(500)

      await page.reload()
      await expect(panel).toBeVisible({timeout:45_000})
      await expect(search).toHaveValue('088661B',{timeout:10_000})
      await expect(country.locator('strong')).toHaveText('Australia',{timeout:10_000})

      await page.getByTitle('Sign out').click()
      await expect(page.locator('input[type="email"]').first()).toBeVisible({timeout:20_000})
      await loginAsUatUser(page)
      await page.goto(`${process.env.UAT_BASE_URL}/#courses`)
      await expect(panel).toBeVisible({timeout:45_000})
      await expect(search).toHaveValue('088661B',{timeout:10_000})
      await expect(country.locator('strong')).toHaveText('Australia',{timeout:10_000})
      await milestoneScreenshot(page,testInfo,'course-screen-state-restored-after-login')

      const clear=panel.getByRole('button',{name:/^Clear$/i})
      await expect(clear).toBeEnabled()
      await clear.click()
      await page.waitForTimeout(400)
      await page.reload()
      await expect(panel).toBeVisible({timeout:45_000})
      await expect(search).toHaveValue('')
      await expect(country.locator('strong')).toHaveText('All')
    }finally{await clearSavedScreenState(page).catch(()=>{});await finish(testInfo,runtime)}
  })
})
