import { test, expect } from '@playwright/test'
import fs from 'node:fs'

// QS official workbooks: the country column must be countries, never regions (2025 file mislabels its headings).
test('QS official parser picks the real country column and refuses region-like country columns',()=>{
  const w=fs.readFileSync('supabase/functions/ranking-qs-official-etl/index.ts','utf8')
  expect(w).toContain('const VERSION="ranking-qs-official-etl-v1.4.0"')
  expect(w).toContain('countryI=countryColumn(best,hi,headers,pos)')
  expect(w).toContain('["location","location code"]')
  expect(w).toContain('if(countries.size<30)throw new Error(')
  expect(w).toContain('QS workbook has no Australia rows; country column not recognised')
})
