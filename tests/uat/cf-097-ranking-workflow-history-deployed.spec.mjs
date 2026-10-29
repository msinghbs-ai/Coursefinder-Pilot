// Guards: CF-097/226 ranking workflow, history and datasets
import{test,expect}from'@playwright/test'
import{UI_VERSION}from'../../src/release-manifest.js'
import{loginAsUatUser,observeRuntime,attachRuntimeEvidence,assertNoServerErrors,DETERMINISTIC_UI_TIMEOUT,writeRunEnvironment}from'./support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CF-097/226 ranking workflow, history and datasets @deployed',()=>{
 test.beforeAll(async()=>{await writeRunEnvironment({suite:'cf-097-cf-226-ranking-workflow-history-datasets',change_control:'CF-CHG-20260903-097 / CF-226 / CF-227'})})

 test('full THE history remains visible and applied editions no longer require manual review',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page)
  await page.goto(new URL('/#administration?section=sources-imports',process.env.UAT_BASE_URL).toString())
  await expect(page.getByRole('heading',{name:'Imported files'})).toBeVisible({timeout:20_000})
  const filter=page.locator('.m-compact-filter select')
  await filter.selectOption('the_wur')
  // CF-224 (Layer 1 Ranking ETL applies editions automatically): every THE edition held is listed and applied, with its module, and none
  // waits on a manual Apply. The THE 2015 file was rejected at validation (live data, 29 Oct 2026), so the history runs 2016–2026.
  for(const year of ['2026','2025','2024','2023','2022','2021','2020','2019','2018','2017','2016']){
    const row=page.locator('.m-ranking-import-row').filter({hasText:'THE_WUR '+year}).first()
    await expect(row).toBeVisible()
    await expect(row).toContainText(/Applied/i)
    await expect(row.getByRole('button',{name:'View module'})).toBeVisible()
  }
  await expect(page.locator('.m-ranking-import-row').getByRole('button',{name:'Apply edition'})).toHaveCount(0)
 }finally{await finish(testInfo,runtime)}})

 test('ranking rows expose Layer 1 Ranking ETL jobs',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page)
  await page.goto(new URL('/#administration?section=sources-imports',process.env.UAT_BASE_URL).toString())
  const row=page.locator('.m-ranking-import-row').filter({hasText:'QS_WUR 2026'}).first()
  await expect(row).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  await expect(row).toContainText(/Latest job:/i) // UI audit Phase 1: sentence case, job name in words
  await expect(row).toContainText(/Ranking import/i)
  await expect(row.getByRole('button',{name:/Jobs/})).toBeVisible()
 }finally{await finish(testInfo,runtime)}})

 test('Statistics exposes accepted QS and THE editions and routes to imported observations',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page)
  await page.goto(new URL('/#statistics-rankings',process.env.UAT_BASE_URL).toString())
  await expect(page.locator('.m-release-pill')).toContainText('v'+UI_VERSION,{timeout:120000})
  const qs=page.locator('.m-stats-card').filter({hasText:'QS WORLD UNIVERSITY RANKINGS'}).first()
  await expect(qs).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  const qsEdition=qs.getByLabel('QS ranking edition')
  await expect(qsEdition).toBeVisible()
  await expect(qsEdition.locator('option')).toContainText(['2025','2024','2023','2022','2021'])
  await qsEdition.selectOption('2025')
  await qs.getByRole('button',{name:'Open dataset'}).click()
  const viewer=page.locator('[data-react-ranking-viewer="1"]')
  await expect(viewer).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  await expect(viewer.getByRole('heading',{name:'QS World University Rankings'})).toBeVisible()
  const year=viewer.getByLabel('QS World University Rankings dataset edition')
  await expect(year).toBeVisible()
  await expect(year.locator('option')).toContainText(['2025','2024','2023','2022','2021'])
  await expect(viewer).toContainText(/1,503 records/i)
  await expect(viewer.locator('tbody tr').first()).toBeVisible()
  await year.selectOption('2024')
  await expect(viewer).toContainText(/1,498 records/i,{timeout:DETERMINISTIC_UI_TIMEOUT})
  await page.goto(new URL('/#statistics-rankings',process.env.UAT_BASE_URL).toString())
  const the=page.locator('.m-stats-card').filter({hasText:'TIMES HIGHER EDUCATION'}).first()
  await expect(the).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  await expect(the.getByLabel('THE ranking edition')).toBeVisible()
  await expect(the.getByRole('button',{name:'Open dataset'})).toBeVisible()
 }finally{await finish(testInfo,runtime)}})
})