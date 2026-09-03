import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { attachRuntimeEvidence, assertNoServerErrors, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CF-103 Provider logo UX and identity quality @targeted',()=>{
  test.beforeAll(async()=>{await writeRunEnvironment({suite:'cf-103-provider-logo-identity-quality-v1',change_control:'CF-CHG-20260904-103'})})

  test('source contract keeps logo replacement Provider-only and PIM-operator gated',async()=>{
    const logo=fs.readFileSync('src/ProviderLogo.jsx','utf8')
    const upload=fs.readFileSync('supabase/functions/provider-asset-upload/index.ts','utf8')
    const access=fs.readFileSync('supabase/functions/provider-asset-access/index.ts','utf8')
    const migration=fs.readFileSync('supabase/migrations/20260904084500_cf_093_provider_logo_manual_upload_and_identity_quality.sql','utf8')
    const reconcile=fs.readFileSync('supabase/migrations/20260904085200_cf_103_provider_logo_change_control_reconcile.sql','utf8')
    expect(logo).toContain(".m-drawer-provider .cf-provider-logo[data-provider-id]")
    expect(logo).toContain("location.hash.startsWith('#providers')")
    expect(logo).toContain("fontWeight:850")
    expect(upload).toContain("role_rank||0)<5")
    expect(upload).toContain('pim_operator_role_required')
    expect(access).toContain('stable_keys')
    expect(migration).toContain('provider_identity_quality_summary')
    expect(migration).toContain("primary_city='Sydney'")
    expect(reconcile).toContain('CF-CHG-20260904-103')
  })

  test('deployed Provider list renders logo and detail name uses theme text',async({page},testInfo)=>{
    if(!process.env.UAT_BASE_URL||!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)test.skip(true,'deployed UAT environment not configured')
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await page.goto(new URL('/#providers',process.env.UAT_BASE_URL).toString())
      await expect(page.locator('.m-catalogue-panel')).toBeVisible({timeout:45000})
      const search=page.locator('.m-catalogue-panel .m-searchbox input')
      await search.fill('Central Queensland University')
      const row=page.locator('.m-catalogue-panel .m-table tbody tr').filter({hasText:'Central Queensland University'}).first()
      await expect(row).toBeVisible({timeout:45000})
      await expect(row.locator('td').first().locator('.cf-provider-list-logo')).toBeVisible({timeout:45000})
      await expect(row.locator('td').first().locator('.cf-provider-list-logo img')).toBeVisible({timeout:45000})
      await row.click()
      const drawer=page.locator('.m-drawer-provider')
      await expect(drawer).toBeVisible({timeout:45000})
      const name=drawer.locator('.cf-provider-brand-copy strong')
      await expect(name).toContainText('Central Queensland University')
      const style=await name.evaluate(el=>({color:getComputedStyle(el).color,weight:parseInt(getComputedStyle(el).fontWeight,10)}))
      expect(style.color).toBe('rgb(15, 23, 42)')
      expect(style.weight).toBeGreaterThanOrEqual(700)
      const role=((await page.locator('.m-role-pill').textContent())||'').trim()
      const logo=drawer.locator('.cf-provider-logo').first()
      if(role==='PIM Operator'||role==='Platform Admin')await expect(logo).toHaveAttribute('title',/upload or replace Provider logo/i)
      else await expect(logo).not.toHaveClass(/cf-logo-editable/)
      await milestoneScreenshot(page,testInfo,'cf-103-provider-logo-list-and-detail')
    }finally{await finish(testInfo,runtime)}
  })

  test('deployed Provider location does not repeat institution name',async({page},testInfo)=>{
    if(!process.env.UAT_BASE_URL||!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)test.skip(true,'deployed UAT environment not configured')
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await page.goto(new URL('/#providers',process.env.UAT_BASE_URL).toString())
      const search=page.locator('.m-catalogue-panel .m-searchbox input')
      await expect(search).toBeVisible({timeout:45000})
      await search.fill('The University of Sydney')
      const row=page.locator('.m-catalogue-panel .m-table tbody tr').filter({hasText:'The University of Sydney'}).first()
      await expect(row).toBeVisible({timeout:45000})
      await expect(row.locator('td').nth(3)).toHaveText('Sydney')
      await expect(row.locator('td').first().locator('.m-cell-title strong')).toHaveText('The University of Sydney')
      await milestoneScreenshot(page,testInfo,'cf-103-provider-location-quality')
    }finally{await finish(testInfo,runtime)}
  })
})
