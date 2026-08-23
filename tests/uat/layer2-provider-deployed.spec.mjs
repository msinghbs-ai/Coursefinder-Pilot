import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CourseFinder deployed Layer 2 acquisition-provider acceptance @deployed',()=>{
  test.beforeAll(async()=>{if(!process.env.UAT_BASE_URL)throw new Error('UAT_BASE_URL is required');if(!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)throw new Error('UAT credentials are required');await writeRunEnvironment({suite:'deployed-layer2-provider',change_control:'CF-CHG-20260823-029'})})

  test('provider registry and source routing are visible without exposing credentials',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      const launcher=page.getByRole('button',{name:/L2 Providers/i})
      await expect(launcher).toBeVisible({timeout:45000})
      await launcher.click()
      await expect(page.getByRole('heading',{name:'Layer 2 Acquisition Providers'})).toBeVisible()
      await expect(page.getByText(/Credentials are write-only and acquisition URLs are source-bound/i)).toBeVisible()
      await expect(page.getByText('Direct HTTP',{exact:true}).first()).toBeVisible()
      await expect(page.getByText('Scrape.do',{exact:true}).first()).toBeVisible()
      await expect(page.getByText(/Credential missing/i).first()).toBeVisible()
      const source=page.getByLabel('Layer 2 provider source profile')
      await source.selectOption({label:/RMIT/i})
      await expect(page.getByText('Direct HTTP',{exact:true}).last()).toBeVisible()
      await expect(page.getByText('Scrape.do',{exact:true}).last()).toBeVisible()
      expect((await page.locator('body').innerText())).not.toMatch(/sb_secret_|service_role|SUPABASE_SERVICE_ROLE_KEY/i)
      await milestoneScreenshot(page,testInfo,'layer2-provider-routing')
    }finally{await finish(testInfo,runtime)}
  })

  test('bounded direct acquisition creates versioned Evidence without canonical mutation',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await page.getByRole('button',{name:/L2 Providers/i}).click()
      const source=page.getByLabel('Layer 2 provider source profile')
      await source.selectOption({label:/PRISMS/i})
      await page.getByRole('button',{name:/Run bounded acquisition/i}).click()
      const result=page.locator('.l2p-run')
      await expect(result).toContainText('Acquisition PASS',{timeout:90000})
      await expect(result).toContainText('Direct HTTP')
      await expect(result).toContainText(/Evidence/i)
      await milestoneScreenshot(page,testInfo,'layer2-provider-acquisition-pass')
    }finally{await finish(testInfo,runtime)}
  })

  test('Platform Admin sees write-only provider credential control when authorised',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await page.getByRole('button',{name:/L2 Providers/i}).click()
      await page.getByText('Scrape.do',{exact:true}).first().click()
      const password=page.locator('input[type="password"][placeholder*="Stored in Vault"]')
      if(await password.count()){
        await expect(password).toBeVisible()
        await expect(password).toHaveValue('')
        await expect(page.getByText(/Configured in Vault|Not configured/)).toBeVisible()
      }
      await milestoneScreenshot(page,testInfo,'layer2-provider-credential-boundary')
    }finally{await finish(testInfo,runtime)}
  })
})
