import{test,expect}from'@playwright/test'
import{loginAsUatUser,observeRuntime,attachRuntimeEvidence,assertNoServerErrors,DETERMINISTIC_UI_TIMEOUT,writeRunEnvironment}from'./support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CF-097 ranking workflow and history @deployed',()=>{
 test.beforeAll(async()=>{await writeRunEnvironment({suite:'cf-097-ranking-workflow-history',change_control:'CF-CHG-20260903-097'})})

 test('full THE history remains visible and validated years expose Apply edition',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
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
  await expect(y2025).toContainText('Needs review')
  await expect(y2025.getByRole('button',{name:'Apply edition'})).toHaveCount(0)
  await expect(y2025.getByRole('button',{name:'Review edition'})).toBeVisible()
 }finally{await finish(testInfo,runtime)}})

 test('ranking rows expose linked Jobs',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page)
  await page.goto(new URL('/#administration?section=sources-imports',process.env.UAT_BASE_URL).toString())
  const row=page.locator('.m-ranking-import-row').filter({hasText:'QS_WUR 2026'}).first()
  await expect(row).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  await expect(row).toContainText(/Latest Job:/)
  await expect(row).toContainText(/ranking import/i)
  await expect(row.getByRole('button',{name:/Jobs/})).toBeVisible()
 }finally{await finish(testInfo,runtime)}})
})
