import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFileSync } from 'node:child_process'

// CF-247 complete coverage sweep: page functions (identity, candidates, map filter, robots.txt) and the worker contract.
async function load() {
  const out = path.join(os.tmpdir(), `cov-${process.pid}.mjs`)
  execFileSync('node_modules/.bin/esbuild', ['supabase/functions/coverage-sweep/extract.ts', '--format=esm', `--outfile=${out}`])
  return import(out)
}

test('identity needs the CRICOS course code on the page or the exact course title', async () => {
  const { identity, htmlToText } = await load()
  const page = '<html><head><title>Bachelor of Science | Example University</title></head><body><h1>Bachelor of Science</h1><p>CRICOS code: 058837J</p></body></html>'
  expect(identity(page, htmlToText(page), 'Bachelor of Science', '058837J')).toBe('cricos_code')
  expect(identity(page, htmlToText(page), 'Bachelor of Science', '000000A')).toBe('exact_title')
  expect(identity(page, htmlToText(page), 'Bachelor of Science (Physics)', '000000A')).toBeNull()
  const other = '<title>Master of Science | Example</title><h1>Master of Science</h1>'
  expect(identity(other, htmlToText(other), 'Bachelor of Science', '058837J')).toBeNull()
})

test('tuition, English and intake candidates', async () => {
  const { fee, english, intakes } = await load()
  const f = fee('International students: indicative annual fee A$42,500 (2027). Domestic CSP $8,948 per year.')
  expect(f.safe).toBe(true); expect(f.value).toBe(42500); expect(f.fee_year).toBe(2027)
  expect(fee('Application fee $150 only').value).toBeNull()
  expect(fee('Domestic students: $9,000 student contribution').safe).toBe(false)
  expect(english('IELTS Academic overall 6.5 with no band less than 6.0; PTE Academic 58; TOEFL iBT 79'))
    .toMatchObject({ ielts_overall: 6.5, ielts_min_band: 6, pte_overall: 58, toefl_overall: 79 })
  expect(english('Contact us on 1300 IELTS')).toEqual({})
  expect(intakes('Intakes: February and July each year. Semester starts in February.')).toEqual(['February', 'July'])
})

test('map filter keeps same-site course pages and drops the rest', async () => {
  const { keepUrl } = await load()
  expect(keepUrl({ url: 'https://www.example.edu.au/study/courses/bachelor-of-science' }, 'www.example.edu.au')).toBe(true)
  expect(keepUrl({ url: 'https://handbook.example.edu.au/2027/courses/B123' }, 'www.example.edu.au')).toBe(true)
  expect(keepUrl({ url: 'https://www.example.edu.au/news/bachelor-of-science-launch' }, 'www.example.edu.au')).toBe(false)
  expect(keepUrl({ url: 'https://www.other.com.au/courses/bachelor' }, 'www.example.edu.au')).toBe(false)
  expect(keepUrl({ url: 'https://www.example.edu.au/files/diploma.pdf' }, 'www.example.edu.au')).toBe(false)
})

test('robots.txt is respected', async () => {
  const { robotsAllows } = await load()
  const r = 'User-agent: *\nDisallow: /private/\nAllow: /private/courses/\nDisallow: /*?search='
  expect(robotsAllows(r, '/courses/bachelor')).toBe(true)
  expect(robotsAllows(r, '/private/x')).toBe(false)
  expect(robotsAllows(r, '/private/courses/x')).toBe(true)
  expect(robotsAllows(r, '/find?search=law')).toBe(false)
  expect(robotsAllows('', '/anything')).toBe(true)
})

test('worker and database contract: nothing written to the catalogue, budget guard counts sweep usage', () => {
  const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(w).toContain('const VERSION = "coverage-sweep-v0.2.0";')
  expect(w).not.toContain('svc_coursefacts_apply_record')
  expect(w).toContain('robotsAllows(')
  const m = fs.readFileSync('supabase/migrations/20260929120000_cf247_coverage_sweep.sql', 'utf8')
  expect(m).toContain('v_used:=v_used+coalesce((select sum(u.units) from pipeline.coverage_vendor_usage u')
  expect(m).toContain("case when by_code or (sc>=0.8 and sc-nxt>=0.1) then 'bound' else 'ambiguous' end")
  expect(m).not.toContain('insert into catalogue.')
})
