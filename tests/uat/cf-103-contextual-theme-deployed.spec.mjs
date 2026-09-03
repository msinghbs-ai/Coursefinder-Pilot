import{test,expect}from'@playwright/test'
import fs from'node:fs'
import{attachRuntimeEvidence,assertNoServerErrors,loginAsUatUser,milestoneScreenshot,observeRuntime,writeRunEnvironment,DETERMINISTIC_UI_TIMEOUT}from'./support/runtime-evidence.mjs'
async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CF-103 contextual insights theme alignment @targeted',()=>{
 test.beforeAll(async()=>{await writeRunEnvironment({suite:'cf-103-contextual-theme-v1',change_control:'CF-CHG-20260904-103'})})
 test('source uses shared CourseFinder contextual theme tokens',async()=>{
  const css=fs.readFileSync('src/contextual-theme.css','utf8'),logo=fs.readFileSync('src/ProviderLogo.jsx','utf8')
  expect(logo).toContain("import'./contextual-theme.css'")
  expect(css).toContain('--cf-insight-navy:#25324a')
  expect(css).toContain('--cf-insight-accent:#5b5ce2')
  expect(css).toContain('.ci-outcome-value')
  expect(css).toContain('.cf-compare-value>strong')
  expect(css).toContain('.cf-flow-compare')
 })
 test('Provider insight cards and Compare metrics render the shared navy theme',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page)
  await page.goto(new URL('/#providers',process.env.UAT_BASE_URL).toString())
  const search=page.locator('.m-searchbox input').first();await expect(search).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT});await search.fill('Charles Darwin University')
  const row=page.locator('.m-table tbody tr').filter({hasText:'Charles Darwin University'}).first();await expect(row).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT});await row.click()
  const insight=page.locator('.ci-outcome-value').first();await expect(insight).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  expect(await insight.evaluate(el=>getComputedStyle(el).color)).toBe('rgb(37, 50, 74)')
  const compare=page.getByTitle('Compare this provider');await compare.click();await expect(page.getByRole('heading',{name:'Compare providers',exact:true})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  const value=page.locator('.cf-compare-value>strong').first();await expect(value).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT});expect(await value.evaluate(el=>getComputedStyle(el).color)).toBe('rgb(37, 50, 74)')
  await milestoneScreenshot(page,testInfo,'cf-103-contextual-theme')
 }finally{await finish(testInfo,runtime)}})
})
