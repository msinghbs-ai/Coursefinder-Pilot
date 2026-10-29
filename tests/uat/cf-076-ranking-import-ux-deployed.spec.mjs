// Guards: CF-076 compact ranking import UX
import fs from'node:fs/promises'
import{test,expect}from'@playwright/test'
import{loginAsUatUser,observeRuntime,attachRuntimeEvidence,assertNoServerErrors,DETERMINISTIC_UI_TIMEOUT,writeRunEnvironment}from'./support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CF-076 compact ranking import UX @deployed',()=>{
 test.beforeAll(async()=>{await writeRunEnvironment({suite:'cf-076-ranking-import-ux',change_control:'CF-CHG-20260902-076'})})

 test('nested Administration route shows breadcrumbs and compact file-first import',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page)
  // v2.15.301 (Platform Admin, 20 Oct 2026): Ranking imports moved to Rankings & statistics › Datasets; the old Administration address
  // (section=sources-imports) still lands there (LEGACY_ADMIN_SECTIONS in src/nav-map.js). The import is file-only, so the form is the
  // ranking system and edition year, filled from the file's content.
  await page.goto(new URL('/#administration?section=sources-imports',process.env.UAT_BASE_URL).toString())
  await expect(page).toHaveURL(/#statistics-rankings\?tab=datasets/,{timeout:DETERMINISTIC_UI_TIMEOUT})
  // CF-076 (2 Sep 2026, mature.css): breadcrumbs show from 681 px up and are hidden at phone width, where the page title carries it.
  const crumb=page.locator('nav.m-breadcrumbs')
  if((page.viewportSize()?.width||1440)>680){
   await expect(crumb).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
   await expect(crumb).toContainText('Home')
   await expect(crumb).toContainText('Rankings & statistics')
   await expect(crumb).toContainText('Datasets')
  }else await expect(crumb).toBeHidden()
  await expect(page.getByRole('heading',{name:'Register ranking publisher file'})).toBeVisible({timeout:20_000})
  await expect(page.getByRole('button',{name:'Advanced metadata'})).toBeVisible()
  await expect(page.locator('.m-ranking-advanced')).toHaveCount(0)
  const fileInput=page.locator('.m-ranking-import-form input[type="file"]')
  await fileInput.setInputFiles({name:'THE_year2016.txt',mimeType:'text/plain',buffer:Buffer.from('Year 2016\n'+JSON.stringify({status:'success',data:{data:[{name:'Example University',rank:'1',location:'Australia',scores_overall:'90'}]}}))})
  await expect(page.locator('.m-ranking-detected')).toContainText('Times Higher Education · 2016')
  const selects=page.locator('.m-ranking-essentials select')
  await expect(selects.nth(0)).toHaveValue('the_wur')
  await expect(selects.nth(1)).toHaveValue('2016')
  await expect(page.getByText(/txt_native_json_is_the_only/)).toHaveCount(0) // no alert is drawn when the file is accepted
  const box=await page.locator('.m-ranking-import-compact').boundingBox();expect(box?.height||9999).toBeLessThan(520)
 }finally{await finish(testInfo,runtime)}})

 test('existing uploaded ranking import can be parsed and records a governed job @live-acting',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page)
  await page.goto(new URL('/#administration?section=sources-imports',process.env.UAT_BASE_URL).toString())
  const row=page.locator('.m-ranking-import-row').filter({hasText:'THE 2015'}).first()
  await expect(row).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  const action=row.getByRole('button',{name:'Parse & validate'})
  if(await action.count()){await action.click();await expect(row).toContainText('Validated',{timeout:30000});await expect(row).toContainText(/parsed observations/i)}
  else await expect(row).toContainText(/Validated|Applied|Needs review/i)
  await page.getByRole('button',{name:'Jobs'}).click()
  await expect(page).toHaveURL(/#jobs/)
  await expect(page.locator('body')).toContainText(/ranking_import_validate|Ranking/i,{timeout:DETERMINISTIC_UI_TIMEOUT})
 }finally{await finish(testInfo,runtime)}})

 test('Layer 1 source settings recognises the selected retained ranking edition and can validate it @live-acting',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page)
  await page.goto(new URL('/#administration?section=layer1-sources&country=GLOBAL',process.env.UAT_BASE_URL).toString())
  const card=page.locator('.l1s-card').filter({hasText:'Times Higher Education World University Rankings'}).first()
  await expect(card).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  const edition=card.locator('.l1s-ranking-edition select');await edition.selectOption('2015')
  await expect(card.locator('.l1s-import-state')).toContainText(/Evidence: (Uploaded|Validated|Applied|Needs review)/i)
  await expect(card.locator('.l1s-import-state')).toContainText('THE_year2015.txt')
  await card.getByRole('button',{name:'Validate'}).click()
  await expect(card).toContainText(/Action completed|validated/i,{timeout:30000})
  await page.goto(new URL('/#jobs',process.env.UAT_BASE_URL).toString())
  await expect(page.locator('body')).toContainText(/ranking_import_validate|Ranking/i,{timeout:DETERMINISTIC_UI_TIMEOUT})
 }finally{await finish(testInfo,runtime)}})

 test('service source derives THE native JSON system/year from file content',async()=>{
  // CF-098 (3 Sep 2026) replaced the THE-only detector with detectRankingJson (QS, THE and ARWU shapes); the selected system and
  // year must match what the file content says, or the upload is refused.
  const src=await fs.readFile('supabase/functions/ranking-publisher-import/index.ts','utf8')
  expect(src).toContain('function detectRankingJson')
  expect(src).toContain('system="the_wur"')
  expect(src).toContain('ranking_system_mismatch')
  expect(src).toContain('edition_year_mismatch')
  expect(src).toContain('const detectedYear=headerYear||detected.year')
  const ctl=await fs.readFile('supabase/functions/ranking-publisher-control/index.ts','utf8')
  // CF-224 / v2.15.100: validate and apply run as governed ranking jobs through service RPCs (svc_ranking_job_*), not direct table writes
  expect(ctl).toContain('action==="validate"')
  expect(ctl).toContain('action==="apply"')
  expect(ctl).toContain('svc_ranking_job_start')
  expect(ctl).toContain('svc_ranking_job_finish')
  expect(ctl).toContain('svc_ranking_manual_import_mark_applied')
 })
})
