import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { attachRuntimeEvidence, assertNoServerErrors, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}
const badName=/^(location|campus|city|state|region|country|australia|new zealand|canada)$/i

test.describe('CF-103 Provider logo UX and identity quality @targeted',()=>{
  test.beforeAll(async()=>{await writeRunEnvironment({suite:'cf-103-provider-logo-identity-quality-v2',change_control:'CF-CHG-20260904-103'})})

  test('source contract keeps logo replacement Provider-only, PIM-gated and supports managed URL import',async()=>{
    const logo=fs.readFileSync('src/ProviderLogo.jsx','utf8')
    const upload=fs.readFileSync('supabase/functions/provider-asset-upload/index.ts','utf8')
    const access=fs.readFileSync('supabase/functions/provider-asset-access/index.ts','utf8')
    const migration=fs.readFileSync('supabase/migrations/20260904084500_cf_093_provider_logo_manual_upload_and_identity_quality.sql','utf8')
    const reconcile=fs.readFileSync('supabase/migrations/20260904085200_cf_103_provider_logo_change_control_reconcile.sql','utf8')
    const urlImport=fs.readFileSync('supabase/migrations/20260904090500_cf_103_provider_logo_url_import.sql','utf8')
    const qualityV2=fs.readFileSync('supabase/migrations/20260904091200_cf_103_provider_identity_location_quality_v2.sql','utf8')
    expect(logo).toContain(".m-drawer-provider .cf-provider-logo[data-provider-id]")
    expect(logo).toContain("location.hash.startsWith('#providers')")
    expect(logo).toContain('Image URL')
    expect(logo).toContain("form.set('source_url',sourceUrl)")
    expect(logo).toContain('color:#0f172a!important')
    expect(logo).toContain('font-weight:850!important')
    expect(upload).toContain("role_rank||0)<5")
    expect(upload).toContain('pim_operator_role_required')
    expect(upload).toContain('unsafe_source_url')
    expect(upload).toContain('p_source_url:originalSourceUrl')
    expect(access).toContain('stable_keys')
    expect(migration).toContain('provider_identity_quality_summary')
    expect(migration).toContain("primary_city='Sydney'")
    expect(reconcile).toContain('CF-CHG-20260904-103')
    expect(urlImport).toContain('manual_admin_url_import')
    expect(qualityV2).toContain('generic_name_placeholder')
    expect(qualityV2).toContain('display_matches_city')
    expect(qualityV2).toContain('canonical_matches_country')
  })

  test('deployed Provider list renders logo and names use bold theme-black text',async({page},testInfo)=>{
    if(!process.env.UAT_BASE_URL||!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)test.skip(true,'deployed UAT environment not configured')
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await page.goto(new URL('/#providers',process.env.UAT_BASE_URL).toString())
      await expect(page.locator('.m-catalogue-panel')).toBeVisible({timeout:45000})
      const rows=page.locator('.m-catalogue-panel .m-table tbody tr')
      await expect(rows.first()).toBeVisible({timeout:45000})
      await expect(rows.first().locator('td').first().locator('.cf-provider-list-logo')).toBeVisible({timeout:45000})
      const count=Math.min(await rows.count(),50)
      for(let i=0;i<count;i++){
        const row=rows.nth(i),name=((await row.locator('td').nth(0).locator('strong').first().textContent())||'').trim()
        const state=((await row.locator('td').nth(2).textContent())||'').trim(),city=((await row.locator('td').nth(3).textContent())||'').trim()
        expect(name).not.toMatch(badName)
        if(state&&state!=='—')expect(name.toLowerCase()).not.toBe(state.toLowerCase())
        if(city&&city!=='—')expect(name.toLowerCase()).not.toBe(city.toLowerCase())
        const style=await row.locator('td').nth(0).locator('strong').first().evaluate(el=>({color:getComputedStyle(el).color,weight:parseInt(getComputedStyle(el).fontWeight,10)}))
        expect(style.color).toBe('rgb(15, 23, 42)')
        expect(style.weight).toBeGreaterThanOrEqual(700)
      }
      await milestoneScreenshot(page,testInfo,'cf-103-provider-list-logo-name-quality')
    }finally{await finish(testInfo,runtime)}
  })

  test('Provider-detail logo editor is Provider-only and offers Browse or Image URL to PIM/Admin',async({page},testInfo)=>{
    if(!process.env.UAT_BASE_URL||!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)test.skip(true,'deployed UAT environment not configured')
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await page.goto(new URL('/#providers',process.env.UAT_BASE_URL).toString())
      await expect(page.locator('.m-catalogue-panel .m-table tbody tr').first()).toBeVisible({timeout:45000})
      await page.locator('.m-catalogue-panel .m-table tbody tr').first().click()
      const drawer=page.locator('.m-drawer-provider');await expect(drawer).toBeVisible({timeout:45000})
      const name=drawer.locator('.cf-provider-brand-copy strong');const style=await name.evaluate(el=>({color:getComputedStyle(el).color,weight:parseInt(getComputedStyle(el).fontWeight,10)}))
      expect(style.color).toBe('rgb(15, 23, 42)');expect(style.weight).toBeGreaterThanOrEqual(700)
      const role=((await page.locator('.m-role-pill').textContent())||'').trim(),editable=drawer.locator('.cf-logo-editable')
      if(role==='PIM Operator'||role==='Platform Admin'){
        await expect(editable).toBeVisible({timeout:45000});await editable.click()
        await expect(page.getByRole('dialog',{name:'Replace Provider logo'})).toBeVisible()
        await expect(page.getByText('Browse image',{exact:true})).toBeVisible()
        await expect(page.getByText('Image URL',{exact:true})).toBeVisible()
        await page.getByRole('button',{name:'Cancel'}).click()
      }else await expect(editable).toHaveCount(0)
      await page.goto(new URL('/#courses',process.env.UAT_BASE_URL).toString())
      await expect(page.locator('.cf-logo-editor-backdrop')).toHaveCount(0)
      await expect(page.locator('.m-drawer-course .cf-logo-editable')).toHaveCount(0)
      await milestoneScreenshot(page,testInfo,'cf-103-provider-only-logo-editor')
    }finally{await finish(testInfo,runtime)}
  })

  test('deployed Provider location does not repeat institution name',async({page},testInfo)=>{
    if(!process.env.UAT_BASE_URL||!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)test.skip(true,'deployed UAT environment not configured')
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await page.goto(new URL('/#providers',process.env.UAT_BASE_URL).toString())
      const search=page.locator('.m-catalogue-panel .m-searchbox input');await expect(search).toBeVisible({timeout:45000});await search.fill('The University of Sydney')
      const row=page.locator('.m-catalogue-panel .m-table tbody tr').filter({hasText:'The University of Sydney'}).first();await expect(row).toBeVisible({timeout:45000})
      await expect(row.locator('td').nth(3)).toHaveText('Sydney');await expect(row.locator('td').first().locator('.m-cell-title strong')).toHaveText('The University of Sydney')
      await milestoneScreenshot(page,testInfo,'cf-103-provider-location-quality')
    }finally{await finish(testInfo,runtime)}
  })
})
