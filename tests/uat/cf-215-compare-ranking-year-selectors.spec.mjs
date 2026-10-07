import { test, expect } from '@playwright/test'
import fs from 'node:fs'

// 7 Oct 2026: rewritten to the current Compare screen. The separate QS and THE edition dropdowns became one dataset control per ranking
// (DatasetControl) with its own Edition selector, as checked in m245-ranking-ui-contract; the intent below is unchanged.
const source=()=>fs.readFileSync('src/ComparisonWorkspace.jsx','utf8')

test('CF-215 gives QS and THE independent ranking edition selectors', async()=>{
  const s=source()
  expect(s).toContain('selectorLabel="Edition" value={rankingSelection.qs} onChange={v=>setRankingSelection(x=>({...x,qs:v}))}')
  expect(s).toContain('selectorLabel="Edition" value={rankingSelection.the} onChange={v=>setRankingSelection(x=>({...x,the:v}))}')
  expect((s.match(/\{value:'multi',label:'Multi-year'\}/g)||[]).length).toBe(2)
  expect(s).toContain("rankingSelection.qs==='multi'")
  expect(s).toContain("rankingSelection.the==='multi'")
})

test('CF-215 defaults each ranking selector to the latest retained edition', async()=>{
  const s=source()
  expect(s).toContain("qsRankingYears[0]||''")
  expect(s).toContain("theRankingYears[0]||''")
  expect(s).toContain("{i===0?' · latest':''}")
  expect(s).not.toMatch(/\[rankingYear,setRankingYear\]/) // no single shared ranking year
})

test('CF-215 keeps enable disable controls independent from the selected ranking year', async()=>{
  const s=source()
  expect(s).toContain('<DatasetControl active={datasets.qs&&hasQS}')
  expect(s).toContain('<DatasetControl active={datasets.the&&hasTHE}')
  expect(s).toContain("setDatasets(x=>({...x,qs:!x.qs}))")
  expect(s).toContain("setDatasets(x=>({...x,the:!x.the}))")
})
