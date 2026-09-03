import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { attachRuntimeEvidence, assertNoServerErrors, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CF-091 H11 Provider Assets coverage @targeted',()=>{
  test.beforeAll(async()=>{await writeRunEnvironment({suite:'cf-091-h11-provider-assets-v1',change_control:'CF-CHG-20260903-091'})})

  test('source contract exposes governed Provider Assets read surface',async()=>{
    const main=fs.readFileSync('src/mature-main.jsx','utf8')
    const api=fs.readFileSync('src/lib/supabase.js','utf8')
    expect(main).toContain("key:'provider-assets',label:'Provider Assets'")
    expect(main).toContain('function ProviderAssetsWorkspace')
    expect(main).toContain("const UI_VERSION='2.15.48'")
    expect(api).toContain("providerAssetSummary:")
    expect(api).toContain("providerAssetCoverage:")
  })

  test('deployed Provider Assets shows measurable H11 coverage and scope warning',async({page},testInfo)=>{
    if(!process.env.UAT_BASE_URL||!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)test.skip(true,'deployed UAT environment not configured')
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await page.goto(new URL('/#administration?section=provider-assets',process.env.UAT_BASE_URL).toString())
      await expect(page.locator('.m-shell')).toBeVisible({timeout:45000})
      await expect(page.getByRole('heading',{name:'Provider Assets',exact:true})).toBeVisible({timeout:45000})
      await expect(page.getByRole('heading',{name:'Coverage matrix',exact:true})).toBeVisible()
      await expect(page.getByText('Expected',{exact:true}).first()).toBeVisible()
      await expect(page.getByText('Approved',{exact:true}).first()).toBeVisible()
      await expect(page.getByText('Missing',{exact:true}).first()).toBeVisible()
      await expect(page.getByText(/not yet a university-only denominator/i)).toBeVisible({timeout:45000})
      await expect(page.locator('tbody tr').first()).toBeVisible({timeout:45000})
      await milestoneScreenshot(page,testInfo,'cf-091-h11-provider-assets')
    }finally{await finish(testInfo,runtime)}
  })
})
