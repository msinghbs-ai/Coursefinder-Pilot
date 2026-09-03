import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { execFileSync } from 'node:child_process'
import { attachRuntimeEvidence, assertNoServerErrors, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CF-089 Scraper Config and Parse.bot qualification @targeted',()=>{
 test.beforeAll(async()=>{await writeRunEnvironment({suite:'cf-089-scraper-config-parsebot-v1',change_control:'CF-CHG-20260903-089'})})

 test('source contract keeps Parse.bot out of generic URL-proxy runtime and avoids eager profile load',async()=>{
  const ui=fs.readFileSync('src/layer2-provider-entry.jsx','utf8')
  const main=fs.readFileSync('src/mature-main.jsx','utf8')
  const acquire=fs.readFileSync('supabase/functions/layer2-acquire-v2/index.ts','utf8')
  const scheduled=fs.readFileSync('supabase/functions/layer2-scope-discover-scheduled/index.ts','utf8')
  expect(ui).not.toContain("adminRead('layer2_profiles')")
  expect(ui).toContain("control('profile_options'")
  expect(ui).toContain('Test Parse.bot connection')
  expect(main).toContain("label:'Extraction Profiles'")
  expect(main).toContain('Advanced Layer 2 workload defaults')
  expect(main).not.toContain('onChange={e=>setForm(x=>({...x,route_mode:e.target.value}))}')
  expect(acquire).toContain('parsebot_generated_api_route_not_qualified')
  expect(scheduled).toContain('parsebot_generated_api_route_not_qualified')
  execFileSync('npm',['run','build'],{stdio:'inherit'})
 })

 test('deployed Scraper Config loads progressively and Parse.bot API key/base URL connect',async({page},testInfo)=>{
  if(!process.env.UAT_BASE_URL||!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)test.skip(true,'deployed UAT environment not configured')
  const runtime=observeRuntime(page)
  try{
   await loginAsUatUser(page)
   await page.goto(new URL('/#administration?section=layer2-providers',process.env.UAT_BASE_URL).toString())
   await expect(page.locator('.m-release-pill')).toContainText('v2.15.46',{timeout:45000})
   await expect(page.getByRole('heading',{name:'Scraper Config',exact:true})).toBeVisible({timeout:45000})
   await expect(page.getByRole('button',{name:'Refresh',exact:true})).toBeVisible()
   await expect(page.getByRole('button',{name:'Manage routes',exact:true})).toBeVisible()
   await expect(page.getByLabel('Layer 2 provider source profile')).toHaveCount(0)

   const parse=page.locator('.l2p-provider-list > button').filter({hasText:'Parse.bot'}).first()
   await expect(parse).toBeVisible()
   await parse.click()
   const drawer=page.locator('.l2p-drawer')
   await expect(drawer.getByRole('heading',{name:'Parse.bot connection & qualification',exact:true})).toBeVisible()
   await drawer.getByRole('button',{name:'Test Parse.bot connection',exact:true}).click()
   await expect(drawer.locator('.l2p-probe.pass')).toContainText('Connected · HTTP 200',{timeout:45000})
   await expect(drawer.locator('.l2p-probe.pass')).toContainText('Execution qualification: pending generated API route.')

   await drawer.locator('.l2p-drawer-head button').click()
   await page.getByRole('button',{name:'Manage routes',exact:true}).click()
   await expect(page.getByLabel('Search extraction profiles')).toBeVisible()
   const select=page.getByLabel('Layer 2 provider source profile')
   await expect(select).toBeVisible({timeout:45000})
   expect(await select.locator('option').count()).toBeLessThanOrEqual(10)

   const advanced=page.locator('details.m-admin-advanced')
   await expect(advanced).not.toHaveAttribute('open','')
   await advanced.locator('summary').click()
   await expect(page.getByRole('heading',{name:'Layer 2 workload defaults',exact:true})).toBeVisible()
   await expect(page.getByText('Read-only here. Provider/profile routing is governed in Scraper Config.')).toBeVisible()
   await expect(page.getByRole('button',{name:'Save workload defaults',exact:true})).toBeVisible()
   await milestoneScreenshot(page,testInfo,'cf-089-scraper-config-parsebot-pass')
  }finally{await finish(testInfo,runtime)}
 })
})
