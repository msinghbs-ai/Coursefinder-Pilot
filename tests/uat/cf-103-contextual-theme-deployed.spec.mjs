// Guards: CF-103 contextual insights theme alignment
import{test,expect}from'@playwright/test'
import fs from'node:fs'
import{attachRuntimeEvidence,assertNoServerErrors,loginAsUatUser,milestoneScreenshot,observeRuntime,writeRunEnvironment,DETERMINISTIC_UI_TIMEOUT}from'./support/runtime-evidence.mjs'
async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CF-103 contextual insights theme alignment @targeted',()=>{
 test.beforeAll(async()=>{await writeRunEnvironment({suite:'cf-103-contextual-theme-v1',change_control:'CF-CHG-20260904-103'})})
 test('source uses shared CourseFinder contextual theme tokens',async()=>{
  const css=fs.readFileSync('src/contextual-theme.css','utf8'),logo=fs.readFileSync('src/ProviderLogo.jsx','utf8')
  expect(logo).toContain("import'./contextual-theme.css'")
  // B2 (v2.15.106): the contextual theme tokens are aliases in the one token set (tokens.css).
  const tokens=fs.readFileSync('src/tokens.css','utf8')
  expect(tokens).toContain('--cf-insight-navy:var(--cf-slate-750)')
  expect(tokens).toContain('--cf-insight-accent:var(--cf-brand)')
  expect(css).toContain('var(--cf-insight-navy)')
  expect(css).toContain('.ci-outcome-value')
  expect(css).toContain('.cf-compare-value>strong')
  expect(css).toContain('.cf-flow-compare')
 })
})
