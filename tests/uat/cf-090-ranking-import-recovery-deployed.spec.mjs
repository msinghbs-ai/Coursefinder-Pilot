import{test,expect}from'@playwright/test'
import{loginAsUatUser,observeRuntime,attachRuntimeEvidence,assertNoServerErrors,DETERMINISTIC_UI_TIMEOUT,writeRunEnvironment}from'./support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CF-090/231 ranking import recovery @deployed',()=>{
 test.beforeAll(async()=>{await writeRunEnvironment({suite:'cf-090-cf-231-ranking-import-recovery',change_control:'CF-CHG-20260903-090 / CF-CHG-20260907-231'})})

 test('recovers uploaded THE 2026 import, validates and applies accepted edition',async({page},testInfo)=>{test.setTimeout(180000);const runtime=observeRuntime(page);try{
  await loginAsUatUser(page)
  await page.goto(new URL('/#administration?section=sources-imports',process.env.UAT_BASE_URL).toString())
  const row=page.locator('.m-ranking-import-row').filter({hasText:'THE_year2026.txt'}).first()
  await expect(row).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  const parse=row.getByRole('button',{name:'Parse & validate'})
  if(await parse.count()){await parse.click();await expect(row).toContainText('Validated',{timeout:90000})}
  await expect(row).toContainText(/Validated|parsed observations/i,{timeout:DETERMINISTIC_UI_TIMEOUT})
  const apply=row.getByRole('button',{name:'Apply edition'})
  if(await apply.count()){await apply.click();await expect(row).toContainText(/Applied|Needs review/i,{timeout:90000})}
  else await expect(row).toContainText(/Applied|Needs review/i)
  await page.goto(new URL('/#statistics-rankings',process.env.UAT_BASE_URL).toString())
  const the=page.locator('.m-stats-card').filter({hasText:'Times Higher Education'}).first()
  await expect(the).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  await expect(the).toContainText(/2026/)
  await expect(the).toContainText(/observations/)
  await expect(the).not.toHaveClass(/pending/)
 }finally{await finish(testInfo,runtime)}})

 test('CF-231 applies retained validated THE 2024 through 2016 via the governed operator path',async({page},testInfo)=>{test.setTimeout(720000);const runtime=observeRuntime(page);try{
  await loginAsUatUser(page)
  await page.goto(new URL('/#administration?section=sources-imports',process.env.UAT_BASE_URL).toString())
  await expect(page.getByRole('heading',{name:'Ranking import workflow'})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  const filter=page.locator('.m-compact-filter select')
  await filter.selectOption('the_wur')
  for(const year of ['2024','2023','2022','2021','2020','2019','2018','2017','2016']){
    const row=page.locator('.m-ranking-import-row').filter({hasText:`THE_WUR ${year}`}).first()
    await expect(row).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    if(!/Applied/i.test(await row.innerText())){
      await expect(row).toContainText(/Validated/i)
      const apply=row.getByRole('button',{name:'Apply edition'})
      await expect(apply).toBeVisible()
      await apply.click()
      await expect(row).toContainText(/Applied/i,{timeout:120000})
    }
    await expect(row.getByRole('button',{name:'View module'})).toBeVisible()
  }
  await page.goto(new URL('/#statistics-rankings',process.env.UAT_BASE_URL).toString())
  const the=page.locator('.m-stats-card').filter({hasText:'TIMES HIGHER EDUCATION'}).first()
  await expect(the).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  const picker=the.locator('.cf-ranking-card-picker select')
  await expect(picker).toBeVisible()
  for(const year of ['2026','2025','2024','2023','2022','2021','2020','2019','2018','2017','2016','2015'])await expect(picker.locator('option')).toContainText(year)
 }finally{await finish(testInfo,runtime)}})
})
