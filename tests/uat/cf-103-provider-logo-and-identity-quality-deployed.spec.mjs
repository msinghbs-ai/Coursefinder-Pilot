import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { attachRuntimeEvidence, assertNoServerErrors, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}
const badName=/^(location|campus|city|state|region|country|australia|new zealand|canada)$/i

test.describe('CF-103 Provider logo UX and identity quality @targeted',()=>{
  test.beforeAll(async()=>{await writeRunEnvironment({suite:'cf-103-provider-logo-identity-quality-v3',change_control:'CF-CHG-20260904-103'})})

  test('source contract keeps Provider detail bold while list uses stable cached logo slots',async()=>{
    const logo=fs.readFileSync('src/ProviderLogo.jsx','utf8')
    const upload=fs.readFileSync('supabase/functions/provider-asset-upload/index.ts','utf8')
    const access=fs.readFileSync('supabase/functions/provider-asset-access/index.ts','utf8')
    expect(logo).toContain('.m-drawer-provider .cf-provider-brand-copy strong')
    expect(logo).toContain('font-weight:850!important')
    expect(logo).toContain('.cf-provider-list-cell>.m-cell-title strong{font-weight:500!important')
    expect(logo).toContain("const listCache=new Map()")
    expect(logo).toContain('sessionStorage')
    expect(logo).toContain('flex:0 0 34px!important')
    expect(logo).toContain('const misses=targets.filter(x=>!x.cached)')
    expect(logo).toContain("img.loading='eager'")
    expect(logo).toContain('Image URL')
    expect(upload).toContain("role_rank||0)<5")
    expect(upload).toContain('unsafe_source_url')
    expect(access).toContain('stable_keys')
  })

  test('deployed Provider list reserves logo space immediately and names are not bold',async({page},testInfo)=>{
    if(!process.env.UAT_BASE_URL||!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)test.skip(true,'deployed UAT environment not configured')
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await page.goto(new URL('/#providers',process.env.UAT_BASE_URL).toString())
      const rows=page.locator('.m-catalogue-panel .m-table tbody tr');await expect(rows.first()).toBeVisible({timeout:45000})
      const firstName=rows.first().locator('td').first().locator('.m-cell-title strong').first();await expect(firstName).toBeVisible()
      const before=await firstName.boundingBox();await expect(rows.first().locator('.cf-provider-list-logo')).toBeVisible({timeout:5000});await page.waitForTimeout(1200);const after=await firstName.boundingBox()
      expect(Math.abs((after?.x||0)-(before?.x||0))).toBeLessThan(2)
      const count=Math.min(await rows.count(),50)
      for(let i=0;i<count;i++){
        const row=rows.nth(i),name=((await row.locator('td').nth(0).locator('strong').first().textContent())||'').trim()
        const state=((await row.locator('td').nth(2).textContent())||'').trim(),city=((await row.locator('td').nth(3).textContent())||'').trim()
        expect(name).not.toMatch(badName);if(state&&state!=='—')expect(name.toLowerCase()).not.toBe(state.toLowerCase());if(city&&city!=='—')expect(name.toLowerCase()).not.toBe(city.toLowerCase())
        const weight=await row.locator('td').nth(0).locator('strong').first().evaluate(el=>parseInt(getComputedStyle(el).fontWeight,10));expect(weight).toBeLessThan(700)
      }
      await milestoneScreenshot(page,testInfo,'cf-103-provider-list-stable-logo-slot')
    }finally{await finish(testInfo,runtime)}
  })

  test('Provider-detail name remains bold theme-black and logo editor remains Provider-only',async({page},testInfo)=>{
    if(!process.env.UAT_BASE_URL||!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)test.skip(true,'deployed UAT environment not configured')
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page);await page.goto(new URL('/#providers',process.env.UAT_BASE_URL).toString());await page.locator('.m-catalogue-panel .m-table tbody tr').first().click()
      const drawer=page.locator('.m-drawer-provider');await expect(drawer).toBeVisible({timeout:45000});const name=drawer.locator('.cf-provider-brand-copy strong');const style=await name.evaluate(el=>({color:getComputedStyle(el).color,weight:parseInt(getComputedStyle(el).fontWeight,10)}));expect(style.color).toBe('rgb(15, 23, 42)');expect(style.weight).toBeGreaterThanOrEqual(700)
      const role=((await page.locator('.m-role-pill').textContent())||'').trim(),editable=drawer.locator('.cf-logo-editable')
      if(role==='PIM Operator'||role==='Platform Admin'){await expect(editable).toBeVisible({timeout:45000});await editable.click();await expect(page.getByRole('dialog',{name:'Replace Provider logo'})).toBeVisible();await expect(page.getByText('Browse image',{exact:true})).toBeVisible();await expect(page.getByText('Image URL',{exact:true})).toBeVisible();await page.getByRole('button',{name:'Cancel'}).click()}else await expect(editable).toHaveCount(0)
      await page.goto(new URL('/#courses',process.env.UAT_BASE_URL).toString());await expect(page.locator('.m-drawer-course .cf-logo-editable')).toHaveCount(0)
      await milestoneScreenshot(page,testInfo,'cf-103-provider-detail-bold-logo-editor')
    }finally{await finish(testInfo,runtime)}
  })
})
