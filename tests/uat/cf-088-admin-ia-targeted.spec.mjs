import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { execFileSync } from 'node:child_process'
import { attachRuntimeEvidence, assertNoServerErrors, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CF-088 M2.4.5 Administration IA hardening @targeted',()=>{
  test.beforeAll(async()=>{await writeRunEnvironment({suite:'cf-088-admin-ia-v1',change_control:'CF-CHG-20260903-088'})})

  test('source contract keeps one Administration control plane and legacy deep links',async()=>{
    const main=fs.readFileSync('src/mature-main.jsx','utf8')
    const access=fs.readFileSync('src/access-roles-entry.jsx','utf8')
    const index=fs.readFileSync('index.html','utf8')
    expect(main).toContain("const UI_VERSION='2.15.45'")
    expect(main).toContain("const ADMIN_SECTIONS=[")
    expect(main).toContain("const LEGACY_ADMIN_ROUTES={'users-roles':'users-roles','attributes':'pim','settings':'platform'}")
    expect(main).toContain("<AccessRolesEmbedded actorId={actorId}/>")
    expect(main).not.toContain("if(key==='users-roles'){location.hash='#users-roles'")
    expect(access).toContain("export function AccessRolesEmbedded")
    expect(index).not.toContain('id="access-roles-root"')
    expect(index).not.toContain('src="/src/access-roles-entry.jsx"')
    execFileSync('npm',['run','build'],{stdio:'inherit'})
  })

  test('deployed Administration renders compact canonical configuration map and blocks legacy Users & Roles for non-rank-6 UAT',async({page},testInfo)=>{
    if(!process.env.UAT_BASE_URL||!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)test.skip(true,'deployed UAT environment not configured')
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await page.goto(new URL('/#administration',process.env.UAT_BASE_URL).toString())
      await expect(page.locator('.m-shell')).toBeVisible({timeout:45000})
      await expect(page.getByRole('heading',{name:'Administration overview',exact:true})).toBeVisible({timeout:45000})
      await expect(page.getByRole('tab',{name:'Scraper Config',exact:true})).toBeVisible()
      await expect(page.locator('.m-release-pill')).toContainText('v2.15.45')
      await expect(page.locator('.ar-overlay:not(.ar-embedded)')).toHaveCount(0)

      await page.goto(new URL('/#users-roles',process.env.UAT_BASE_URL).toString())
      await expect(page.locator('.m-shell')).toBeVisible({timeout:45000})
      await expect(page.locator('.ar-overlay:not(.ar-embedded)')).toHaveCount(0)
      const role=((await page.locator('.m-role-pill').textContent())||'').trim()
      if(role!=='Platform Admin'){
        await expect(page.getByRole('tab',{name:'Users & Roles',exact:true})).toHaveCount(0)
        await expect(page.getByRole('heading',{name:'Administration overview',exact:true})).toBeVisible()
      }
      await milestoneScreenshot(page,testInfo,'cf-088-admin-ia-standardised')
    }finally{await finish(testInfo,runtime)}
  })
})
