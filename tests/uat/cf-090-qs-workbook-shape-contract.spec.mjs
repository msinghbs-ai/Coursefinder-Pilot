import fs from 'node:fs'
import {test,expect} from '@playwright/test'

const read=p=>fs.readFileSync(p,'utf8')

test('CF-090 QS workbook retains full indicator/category detail while dataset stays overall-focused',()=>{
  const parser=read('supabase/functions/ranking-qs-official-etl/index.ts')
  for(const code of [
    'academic_reputation','employer_reputation','faculty_student_ratio','citations_per_faculty',
    'international_faculty_ratio','international_student_ratio','international_student_diversity',
    'international_research_network','employment_outcomes','sustainability'
  ]) expect(parser).toContain(`"${code}"`)
  expect(parser).toContain('source_row_payload:{...source')
  expect(parser).toContain('overall_score:score(r[overallI])')

  const ui=read('src/mature-main.jsx')
  const start=ui.indexOf('function RankingDatasetPanel(')
  expect(start).toBeGreaterThan(-1)
  const end=ui.indexOf('\nfunction ',start+30)
  const block=ui.slice(start,end>start?end:undefined)
  expect(block).toContain("sortHead('rank','Rank')")
  expect(block).toContain("sortHead('score','Overall score')")
  expect(block).not.toContain('Academic Reputation')
  expect(block).not.toContain('Employer Reputation')
  expect(block).not.toContain('Faculty Student Ratio')
  expect(block).not.toContain('Citations per Faculty')
  expect(block).not.toContain('International Faculty Ratio')
  expect(block).not.toContain('International Student Ratio')
  expect(block).not.toContain('International Research Network')
  expect(block).not.toContain('Employment Outcomes')
  expect(block).not.toContain('Sustainability')
})

test('CF-090 byte-identical re-upload repairs legacy inline Evidence rather than discarding the new private object',()=>{
  const migration=read('supabase/migrations/20260910162500_cf_qs_duplicate_upload_restores_missing_evidence.sql')
  expect(migration).toContain("v_existing.storage_path like 'inline://%'")
  expect(migration).toContain("'recovered_duplicate',true")
  expect(migration).toContain("'duplicate',false")
  expect(migration).toContain('publisher_file_restore_hash')
  expect(migration).toContain('to service_role')
  expect(migration).toContain('from public,anon,authenticated')
})
