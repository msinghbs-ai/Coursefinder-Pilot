import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const source=()=>fs.readFileSync('src/ComparisonWorkspace.jsx','utf8')

test('CF-215 gives QS and THE independent ranking edition selectors', async()=>{
  const s=source()
  expect(s).toContain('aria-label="QS ranking edition"')
  expect(s).toContain('aria-label="THE ranking edition"')
  expect(s).toContain('<option value="multi">Multi-year</option>')
  expect(s).toContain("rankingSelection.qs==='multi'")
  expect(s).toContain("rankingSelection.the==='multi'")
})

test('CF-215 defaults each ranking selector to the latest retained edition', async()=>{
  const s=source()
  expect(s).toContain("qsRankingYears[0]||''")
  expect(s).toContain("theRankingYears[0]||''")
  expect(s).toContain("{i===0?' · latest':''}")
  expect(s).not.toContain('rankingYear')
})

test('CF-215 keeps enable disable controls independent from the selected ranking year', async()=>{
  const s=source()
  expect(s).toContain("datasets.qs?'active':''")
  expect(s).toContain("datasets.the?'active':''")
  expect(s).toContain("setDatasets(x=>({...x,qs:!x.qs}))")
  expect(s).toContain("setDatasets(x=>({...x,the:!x.the}))")
})
