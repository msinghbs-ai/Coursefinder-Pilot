import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { attachRuntimeEvidence, assertNoServerErrors, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}
const badName=/^(location|campus|city|state|region|country|australia|new zealand|canada)$/i

test.describe('CF-103 Provider logo and display-name quality @targeted',()=>{
  test.beforeAll(async()=>{await writeRunEnvironment({suite:'cf-103-provider-logo-name-quality-v1',change_control:'CF-CHG-20260904-103'})})

  test('source contract keeps logo replacement Provider-only and supports managed URL import',async()=>{
    const logo=fs.readFileSync('src/ProviderLogo.jsx','utf8')
    const worker=fs.readFileSync('supabase/functions/provider-asset-upload/index.ts','utf8')
    const migration=fs.readFileSync('supabase/migrations/20260904090500_cf_103_provider_logo_url_import.sql','utf8')
    expect(logo).toContain("location.hash.startsWith('#providers')")
    expect(logo).toContain('Image URL')
    expect(logo).toContain("form.set('source_url',sourceUrl)")
    expect(logo).toContain('cf-provider-list-logo')
    expect(logo).toContain('color:#0f172a!important')
    expect(logo).toContain('font-weight:850!important')
    expect(worker).toContain('p_source_url:originalSourceUrl')
    expect(worker).toContain('unsafe_source_url')
    expect(migration).toContain('manual_admin_url_import')
    expect(migration).toContain("'managed_storage',true")
  })

  test('Provider catalogue renders a logo/fallback and a non-geographic bold dark Provider name',async({page},testInfo)=>{
    if(!process.env.UAT_BASE_URL||!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)test.skip(true,'deployed UAT environment not configured')
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await page.goto(new URL('/#providers',process.env.UAT_BASE_URL).toString())
      await expect(page.locator('.m-catalogue-panel .m-table tbody tr').first()).toBeVisible({timeout:45000})
      await expect(page.locator('.m-catalogue-panel .cf-provider-list-logo').first()).toBeVisible({timeout:45000})
      const rows=page.locator('.m-catalogue-panel .m-table tbody tr')
      const count=Math.min(await rows.count(),50)
      for(let i=0;i<count;i++){
        const row=rows.nth(i),name=((await row.locator('td').nth(0).locator('strong').first().textContent())||'').trim()
        const state=((await row.locator('td').nth(2).textContent())||'').trim(),city=((await row.locator('td').nth(3).textContent())||'').trim()
        expect(name).not.toMatch(badName)
        if(state&&state!=='—')expect(name.toLowerCase()).not.toBe(state.toLowerCase())
        if(city&&city!=='—')expect(name.toLowerCase()).not.toBe(city.toLowerCase())
        const css=await row.locator('td').nth(0).locator('strong').first().evaluate(el=>{const s=getComputedStyle(el);return{color:s.color,weight:Number(s.fontWeight)||0}})
        expect(css.color).toBe('rgb(15, 23, 42)')
        expect(css.weight).toBeGreaterThanOrEqual(700)
      }
      await milestoneScreenshot(page,testInfo,'cf-103-provider-list-logo-name-quality')
    }finally{await finish(testInfo,runtime)}
  })

  test('logo replacement control is only exposed from Provider detail and offers Browse or Image URL for PIM/Admin',async({page},testInfo)=>{
    if(!process.env.UAT_BASE_URL||!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)test.skip(true,'deployed UAT environment not configured')
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await page.goto(new URL('/#providers',process.env.UAT_BASE_URL).toString())
      await expect(page.locator('.m-catalogue-panel .m-table tbody tr').first()).toBeVisible({timeout:45000})
      await page.locator('.m-catalogue-panel .m-table tbody tr').first().click()
      await expect(page.locator('.m-drawer-provider')).toBeVisible({timeout:45000})
      const role=((await page.locator('.m-role-pill').textContent())||'').trim()
      const editable=page.locator('.m-drawer-provider .cf-logo-editable')
      if(/PIM Operator|Platform Admin/i.test(role)){
        await expect(editable).toBeVisible({timeout:45000});await editable.click()
        await expect(page.getByRole('dialog',{name:'Replace Provider logo'})).toBeVisible()
        await expect(page.getByText('Browse image',{exact:true})).toBeVisible()
        await expect(page.getByText('Image URL',{exact:true})).toBeVisible()
        await page.getByRole('button',{name:'Cancel'}).click()
      }else await expect(editable).toHaveCount(0)
      await page.goto(new URL('/#courses',process.env.UAT_BASE_URL).toString())
      await expect(page.locator('.cf-logo-editor-backdrop')).toHaveCount(0)
      await expect(page.locator('.m-drawer-course .cf-logo-editable')).toHaveCount(0)
      await milestoneScreenshot(page,testInfo,'cf-103-provider-only-logo-edit')
    }finally{await finish(testInfo,runtime)}
  })
})
