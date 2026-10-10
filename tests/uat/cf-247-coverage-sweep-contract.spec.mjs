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
  expect(identity(page, htmlToText(page), 'Bachelor of Science', '000000A', true)).toBeNull()
})

test('tuition, English and intake candidates', async () => {
  const { fee, english, intakes, intakeEvidence } = await load()
  const f = fee('International students: indicative annual fee A$42,500 (2027). Domestic CSP $8,948 per year.')
  expect(f.safe).toBe(true); expect(f.value).toBe(42500); expect(f.fee_year).toBe(2027)
  expect(f.basis).toBe('annual')
  expect(fee('Fee summary 2027 indicative fees International: Full-fee places: AU$31,680 (2027 total) Additional expenses').basis).toBe('total')
  expect(fee('International students: The total indicative fee for 2026 commencement is AU$25,250 . View tuition fees').basis).toBe('total')
  expect(fee('International student Fees A$109328 Duration 4 Years').basis).toBeNull()
  expect(fee('Application fee $150 only').value).toBeNull()
  expect(fee('Domestic students: $9,000 student contribution').safe).toBe(false)
  expect(english('IELTS Academic overall 6.5 with no band less than 6.0; PTE Academic 58; TOEFL iBT 79'))
    .toMatchObject({ ielts_overall: 6.5, ielts_min_band: 6, pte_overall: 58, toefl_overall: 79 })
  expect(english('Contact us on 1300 IELTS')).toEqual({ ielts_unclear: true })
  // pilot findings 29 Sep 2026
  expect(english('IELTS Academic (or equivalent) with a minimum 7.0 in Writing and no other band less than 6.5')).toEqual({ ielts_unclear: true })
  expect(english('IELTS Academic / One Skill Retake: 7.0 or better overall with no subscore below 6.5 PTE Academic: 66 or better')).toMatchObject({ ielts_overall: 7, ielts_min_band: 6.5, pte_overall: 66 })
  expect(english('IELTS overall band of 6.5 (Academic Module) with no individual band below 6.0')).toMatchObject({ ielts_overall: 6.5, ielts_min_band: 6 })
  expect(english('English Test Overall Score Reading Writing Listening Speaking IELTS Academic 6.5 6.0 6.0 6.0 6.0 UOW College')).toMatchObject({ ielts_overall: 6.5, ielts_min_band: 6 })
  expect(english('IELTS Academic: overall 6.5, writing 6.0 TOEFL iBT (0-120): overall 79, writing 21')).toMatchObject({ ielts_overall: 6.5, toefl_overall: 79 })
  expect(english('PTE Academic requirements vary; see the English requirements page for 41 courses').pte_overall).toBeUndefined()
  expect(english('Pearson PTE: overall 58, writing 50').pte_overall).toBe(58)
  expect(english('TOEFL iBT (0-120): overall 79, writing 21').toefl_overall).toBe(79)
  // v0.5.3: the number after "overall" only when no other words intervene; band score may come before "in each band"
  expect(english('Academic IELTS 6.0 overall, no less than 5.5 in each band, or upper intermediate')).toMatchObject({ ielts_overall: 6, ielts_min_band: 5.5 })
  expect(english('IELTS Listening 6.0 Reading 6.0 Writing 6.0 Speaking 6.0 Overall 6.5')).toMatchObject({ ielts_overall: 6.5 })
  expect(english('IELTS: overall score of 6.5 with a minimum of 6.0 in all bands')).toMatchObject({ ielts_overall: 6.5, ielts_min_band: 6 })
  expect(english('IELTS overall 7.0 (no band below 6.5)')).toMatchObject({ ielts_overall: 7, ielts_min_band: 6.5 })
  // v0.5.4: score before the test name; another test's overall never read as IELTS; several overalls -> unclear
  expect(english('A minimum overall band score of 6.5 on IELTS (Academic) with no sub-score of less than 6.0 OR an overall score of 79 in the TOEFL iBT (1-6): overall 4')).toMatchObject({ ielts_overall: 6.5, ielts_min_band: 6 })
  expect(english('IELTS Academic test Overall minimum: 6.0 No band below: 6.0 Overall minimum: 6.5 No band below 6.0').ielts_overall).toBeUndefined()
  expect(english('IELTS Academic: overall 6.5, writing 6.0 TOEFL iBT (0-120): overall 79')).toMatchObject({ ielts_overall: 6.5, toefl_overall: 79 })
  expect(intakes('Intakes: February and July each year. Semester starts in February.')).toEqual(['February', 'July'])
  expect(intakes('Semester dates may change; start dates may vary.')).toEqual([])
  // v0.5.3: money, visa and deadline windows are not intakes; evidence snippet kept for review
  expect(intakes('From May 2024, the 12-month living costs is: AUD 29,710')).toEqual([])
  expect(intakes('Applications close in November for semester 1 fees')).toEqual([])
  expect(intakeEvidence('Intakes: February and July each year.')[0]).toContain('February and July')
})

test('map filter keeps same-site course pages and drops the rest', async () => {
  const { keepUrl } = await load()
  expect(keepUrl({ url: 'https://www.example.edu.au/study/courses/bachelor-of-science' }, 'www.example.edu.au')).toBe(true)
  expect(keepUrl({ url: 'https://handbook.example.edu.au/2027/courses/B123' }, 'www.example.edu.au')).toBe(true)
  expect(keepUrl({ url: 'https://www.example.edu.au/news/bachelor-of-science-launch' }, 'www.example.edu.au')).toBe(false)
  expect(keepUrl({ url: 'https://www.other.com.au/courses/bachelor' }, 'www.example.edu.au')).toBe(false)
  expect(keepUrl({ url: 'https://www.example.edu.au/files/diploma.pdf' }, 'www.example.edu.au')).toBe(false)
  expect(keepUrl({ url: 'https://www.rmit.edu.au/study-with-us/applying-to-rmit/local-student-applications/entry-requirements/inherent-requirements/bachelor-of-photography' }, 'www.rmit.edu.au')).toBe(false)
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
  expect(w).toMatch(/const VERSION = "coverage-sweep-v0\.5\.[4-9]";/) // v0.5.5 (Decision 223) re-reads every saved page
  expect(w).toContain('identity(html, text, it.title, it.code, it.status === "ambiguous", it.country || "")') // Decision 235 passes the country
  expect(w).not.toContain('svc_coursefacts_apply_record')
  expect(w).toContain('robotsAllows(')
  expect(w).toContain('status = "needs_render"')
  expect(w).toContain('const found = codeRe.test(htmlToText(html));')
  expect(w).toContain('const ok = found && (home || fits) && !SKIP.test(finalHost);')
  expect(w).toContain('const units = /search$/.test(purpose) ? 2 : /^fcx_/.test(purpose) ? 5 : 1;') // v0.13.0 counts a JSON-format scrape at 5 credits
  expect(w).toContain('(it.status === "bound" || it.priority === true) && (http === null')
  const m = fs.readFileSync('supabase/migrations-archive/20260929120000_cf247_coverage_sweep.sql', 'utf8')
  expect(m).toContain('v_used:=v_used+coalesce((select sum(u.units) from pipeline.coverage_vendor_usage u')
  expect(m).toContain("case when by_code or (sc>=0.8 and sc-nxt>=0.1) then 'bound' else 'ambiguous' end")
  expect(m).not.toContain('insert into catalogue.')
})

// v0.13.0 (3 Oct 2026, Platform Admin "Yes, qualify now"): Firecrawl's own AI extraction is run against the frozen
// holdouts and recorded only. It must not write a value, change a cascade tier, or run without a q-fcx- run label.
test('Firecrawl AI extraction mode is qualification only: records outcomes, admits nothing', () => {
  const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  const start = w.indexOf('if (mode === "fc_extract_qualify") {'), end = w.indexOf('if (mode === "openrouter_key") {')
  expect(start).toBeGreaterThan(0); expect(end).toBeGreaterThan(start)
  const block = w.slice(start, end)
  expect(block).toContain('/^q-fcx-[a-z0-9.-]{3,60}$/.test(runLabel)')
  expect(block).toContain('await rpc("svc_fc_extract_cases"')
  expect(block).toContain('await rpc("svc_fc_extract_result"')
  expect(block).toContain('useFc("fcx_qualify"')
  expect(block).toContain('quoteIn === true') // a value counts as stated only when its quote is on the rendered page
  for (const forbidden of ['svc_coverage_apply', 'coverage_apply_course', 'layer3_route_tiers', 'layer3_model_profiles', 'svc_coursefacts', 'svc_layer3_'])
    expect(block).not.toContain(forbidden)
  const m = fs.readFileSync('supabase/migrations-archive/20261003000800_cf247_firecrawl_extract_qualify.sql', 'utf8')
  expect(m).toContain("check (outcome in ('exact', 'exact_not_stated', 'wrong_admitted', 'missed', 'error'))")
  expect(m).toContain("'pass_80_rule', (n >= 30 and ok::numeric / n >= 0.80 and wrong = 0)")
  expect(m).not.toContain('layer3_route_tiers'); expect(m).not.toContain('insert into catalogue.')
  for (const word of ['drop', 'delete from', 'truncate', 'on delete cascade']) expect(m.toLowerCase()).not.toContain(word)
})
