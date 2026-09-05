import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const read = path => fs.readFileSync(path, 'utf8')

test('CF-214 THE URL acquisition is publisher-allowlisted, Evidence-first and fail-closed', async () => {
  const src = read('supabase/functions/ranking-the-url-import/index.ts')
  expect(src).toContain('www.timeshighereducation.com')
  expect(src).toContain('world-university-rankings')
  expect(src).toContain('a250cfd9-0c7d-421b-87a3-80a0d7d392be')
  expect(src).toContain('ranking_type=world_university_rankings')
  expect(src).toContain('the_completeness_gate_failed_')
  expect(src).toContain('publisher_total')
  expect(src).toContain('ranking_publisher_raw')
  expect(src).toContain('storage.from("evidence").upload')
  expect(src).toContain('CourseFinder Evidence.xlsx')
  expect(src).toContain('Raw Source')
  expect(src).toContain('Evidence Metadata')
})

test('CF-214 THE workbook/parser preserves historical and current pillar semantics from 2011 onward', async () => {
  const src = read('supabase/functions/ranking-the-official-etl/index.ts')
  expect(src).toContain('year<2011')
  expect(src).toContain('Teaching')
  expect(src).toContain('Research')
  expect(src).toContain('Citations')
  expect(src).toContain('Industry Income')
  expect(src).toContain('Research Environment')
  expect(src).toContain('Research Quality')
  expect(src).toContain('International Outlook')
  expect(src).toContain('rank_display')
  expect(src).toContain('rank_exact')
  expect(src).toContain('rank_low')
  expect(src).toContain('rank_high')
  expect(src).toContain('svc_ranking_ingest_apply')
})

test('CF-214 controls route THE through the dedicated URL and XLSX Evidence workers', async () => {
  const urlControl = read('supabase/functions/ranking-publisher-url-import/index.ts')
  const control = read('supabase/functions/ranking-publisher-control/index.ts')
  expect(urlControl).toContain('ranking-the-url-import')
  expect(urlControl).toContain('timeshighereducation')
  expect(control).toContain('ranking-the-official-etl')
})

test('CF-214 Administration exposes THE publisher URL mode, 2011 onward and XLSX export remains available', async () => {
  const src = read('src/mature-main.jsx')
  expect(src).toContain("system==='the_wur'?Array.from({length:16}")
  expect(src).toContain('THE publisher URL')
  expect(src).toContain('Publisher URL → Evidence XLSX')
  expect(src).toContain('Export XLSX')
  expect(src).toContain('ranking-evidence-export')
})
