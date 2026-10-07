import{test,expect}from'@playwright/test'
import{readFile}from'node:fs/promises'

test('M2.4.5 ranking dataset and compare-period UI contract',async()=>{
 const compare=await readFile(new URL('../../src/ComparisonWorkspace.jsx',import.meta.url),'utf8')
 const index=await readFile(new URL('../../index.html',import.meta.url),'utf8')

 expect(compare).toContain('cf-dataset-toggles cf-dataset-toggles-with-years')
 expect(compare).toContain('label="QILT"')
 expect(compare).toContain('label="PRISMS"')
 expect(compare).toContain('label="QS"')
 expect(compare).toContain('label="THE"')
 expect(compare).toContain('selectorLabel="Year" value={year}')
 expect(compare).toContain('selectorLabel="Year" value={prismsYear}')
 expect(compare).toContain('selectorLabel="Edition" value={rankingSelection.qs}')
 expect(compare).toContain('selectorLabel="Edition" value={rankingSelection.the}')
 expect(compare).not.toContain('aria-label="QS ranking edition"')
 expect(compare).not.toContain('aria-label="THE ranking edition"')
 expect(compare).toContain("filter(z=>!prismsYear||flowYear(z)===prismsYear)")
 expect(compare).toContain("{value:'multi',label:'Multi-year'}")

 // 7 Oct 2026: ranking-page-presentation.js (the old ranking page decorator) was removed; ranking pages are React screens now.
 expect(index).not.toContain('/src/ranking-page-presentation.js')
})
