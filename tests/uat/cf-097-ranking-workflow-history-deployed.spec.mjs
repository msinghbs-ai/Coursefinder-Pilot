import{test,expect}from'@playwright/test'
import{loginAsUatUser,observeRuntime,attachRuntimeEvidence,assertNoServerErrors,DETERMINISTIC_UI_TIMEOUT,writeRunEnvironment}from'./support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CF-097/226 ranking workflow, history and datasets @deployed',()=>{
 test.beforeAll(async()=>{await writeRunEnvironment({suite:'cf-097-cf-226-ranking-workflow-history-datasets',change_control:'CF-CHG-20260903-097 / CF-226 / CF-227'})})

 test('full THE history remains visible and applied editions no longer require manual review',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page)
  await page.goto(new URL('/#administration?section=sources-imports',process.env.UAT_BASE_URL).toString())
  await expect(page.getByRole('heading',{name:'Ranking import workflow'})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  const filter=page.locator('.m-compact-filter select')
  await filter.selectOption('the_wur')
  for(const year of ['2026','2025','2024','2023','2022','2021','2020','2019','2018','2017','2016','2015']){
    await expect(page.locator('.m-ranking-import-row').filter({hasText:'THE_WUR '+year}).first()).toBeVisible()
  }
  const y2024=page.locator('.m-ranking-import-row').filter({hasText:'THE_WUR 2024'}).first()
  await expect(y2024).toContainText('Validated')
  await expect(y2024.getByRole('button',{name:'Apply edition'})).toBeVisible()
  const y2025=page.locator('.m-ranking-import-row').filter({hasText:'THE_WUR 2025'}).first()
  await expect(y2025).toContainText(/Applied/i)
  await expect(y2025.getByRole('button',{name:'View module'})).toBeVisible()
 }finally{await finish(testInfo,runtime)}})

 test('ranking rows expose Layer 1 Ranking ETL jobs',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page)
  await page.goto(new URL('/#administration?section=sources-imports',process.env.UAT_BASE_URL).toString())
  const row=page.locator('.m-ranking-import-row').filter({hasText:'QS_WUR 2026'}).first()
  await expect(row).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  await expect(row).toContainText(/Latest Job:/)
  await expect(row).toContainText(/Layer1 Ranking Etl/i)
  await expect(row.getByRole('button',{name:/Jobs/})).toBeVisible()
 }finally{await finish(testInfo,runtime)}})

 test('Statistics exposes accepted QS and THE editions and opens imported observations',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page)
  await page.goto(new URL('/#statistics-rankings',process.env.UAT_BASE_URL).toString())
  await expect(page.locator('.m-release-pill')).toContainText('v2.15.74',{timeout:120000})
  const qs=page.locator('.m-stats-card').filter({hasText:'QS WORLD UNIVERSITY RANKINGS'}).first()
  await expect(qs).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  const qsEdition=qs.locator('.cf-ranking-card-picker select')
  await expect(qsEdition).toBeVisible()
  await expect(qsEdition.locator('option')).toContainText(['2025','2024','2023','2022','2021'])
  await qs.getByRole('button',{name:'Open dataset'}).click()
  const viewer=page.locator('.cf-ranking-viewer')
  await expect(viewer).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  await expect(viewer.getByRole('heading',{name:/Imported dataset — QS World University Rankings/i})).toBeVisible()
  await expect(viewer).toContainText(/1,503 observations/i)
  await expect(viewer.locator('tbody tr').first()).toBeVisible()
  await viewer.locator('[data-year]').selectOption('2024')
  await expect(viewer).toContainText(/1,498 observations/i,{timeout:DETERMINISTIC_UI_TIMEOUT})
  const the=page.locator('.m-stats-card').filter({hasText:'TIMES HIGHER EDUCATION'}).first()
  await expect(the.locator('.cf-ranking-card-picker select')).toBeVisible()
 }finally{await finish(testInfo,runtime)}})
})
