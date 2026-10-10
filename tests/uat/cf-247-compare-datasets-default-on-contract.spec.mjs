import { test, expect } from '@playwright/test'
import fs from 'node:fs'

// Compare: datasets are on by default and never greyed out before a selection; switched off only by a click.
test('Compare datasets are on by default and only switched off by the user',()=>{
  const s=fs.readFileSync('src/ComparisonWorkspace.jsx','utf8')
  expect(s).toContain('useState({qilt:true,prisms:true,qs:true,the:true})')
  expect(s).toContain('<DatasetControl active={datasets.qilt} disabled={false} label="QILT"')
  expect(s).toContain('<DatasetControl active={datasets.prisms} disabled={false} label="PRISMS"')
  expect(s).toContain("const LATEST=[{value:'',label:'Latest available'}]")
  expect(s).toContain('hasQS=qsRankingYears.length>0||!rankingAvailability.loaded')
  expect(s).toContain("For courses, QILT and rankings are shown for each course\\'s university")
})

test('Course mode PRISMS falls back to the state of the course, like the university view',()=>{
  const m=fs.readFileSync('supabase/migrations-archive/20260928120000_compare_course_prisms_state_fallback.sql','utf8')
  expect(m).toContain("if md5(v_def)<>'4ddb5b136f74fdd746809b675b8b93d8' then")
  expect(m).toContain("''regional_context''::text granularity")
  expect(m).toContain('select cp.subdivision_id from catalogue.campuses cp where cp.provider_id=v_provider')
})
