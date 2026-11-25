// Guards: Platform Admin 25 Nov 2026 12:01 AEDT (P0 AER preprocessing qualification: recall of requirements, conditions and thresholds in the selected content; report the exact failure and the smallest corrective action)
// s1140: lean-sections-v6 selects the rows the s1125 qualification and the s1135 recall check still lost: an entry condition printed as a heading, minimum ages, marks, approvals, "you must" lines and portfolios.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFileSync } from 'node:child_process'

async function load(file, name) {
  const out = path.join(os.tmpdir(), `${name}-${process.pid}.mjs`)
  execFileSync('node_modules/.bin/esbuild', [file, '--bundle', '--format=esm', '--platform=node', `--outfile=${out}`, '--log-level=error'])
  return import(out)
}
const overview = '<p>Our graduates work across studios, hospitals and the community, learning with experienced teachers.</p>'.repeat(20)
const page = (body) => `<html><body><main><h1>Course</h1><h2>Overview</h2>${overview}<h2>More</h2>${body}<h2>Careers</h2><p>Counsellor, performer, manager.</p></main></body></html>`
const CASES = [
  ['<h3>Graduate with an AUSTRALIAN DEGREE (AQF Level 9)</h3><p>Study in Sydney with industry projects.</p>', 'Graduate with an AUSTRALIAN DEGREE (AQF Level 9)'],
  ['<h3>You may also be considered if you have:</h3><ul><li>Completed an Australian Diploma or Advanced Diploma (or equivalent) in a relevant field</li></ul>', 'Completed an Australian Diploma or Advanced Diploma (or equivalent) in a relevant field'],
  ['<p>Be a minimum of 18 years old.</p>', 'Be a minimum of 18 years old.'],
  ['<p>Students must be over 18 years of age at the time of course commencement.</p>', 'Students must be over 18 years of age at the time of course commencement.'],
  ['<p>A current course weighted average mark of at least 60.</p>', 'A current course weighted average mark of at least 60.'],
  ['<p>You will also need approval of the Academic Program Coordinator for Health Science.</p>', 'You will also need approval of the Academic Program Coordinator for Health Science.'],
  ['<p>You must: demonstrate a high level of literacy and numeracy skills</p>', 'You must: demonstrate a high level of literacy and numeracy skills'],
  ['<p>A creative submission or portfolio relevant to your chosen course.</p>', 'A creative submission or portfolio relevant to your chosen course.'],
  ['<p>Previous completion of a Diploma of Information Technology (equivalent or higher) qualification.</p>', 'Previous completion of a Diploma of Information Technology (equivalent or higher) qualification.'],
]

test('s1140: every row the qualification and the v5 recall check still lost is selected, likely, and the overview stays out', async () => {
  const lean = await load('supabase/functions/coverage-sweep/lean-input.ts', 'li1140')
  const aer = await load('supabase/functions/coverage-sweep/aer-v2.ts', 'av1140')
  const sec = await load('supabase/functions/coverage-sweep/lean-sections.ts', 'ls1140')
  expect(sec.LEAN_SECTIONS).toBe('lean-sections-v6')
  for (const [html, q] of CASES) {
    const s = sec.selectSections(aer.aerV3Blocks(lean.leanText(page(html)), null), 'entry_requirements')
    expect(sec.holds(s.plain, [q]), q).toBe(true)
    expect(s.signal, q).toBe('likely')
    expect(s.plain, q).not.toContain('experienced teachers')
  }
})

test('s1140: the recall check is reseeded under v6 with the same labels and the cohort pages; no AI, nothing switched on', () => {
  const MIG = fs.readFileSync('supabase/migrations/20261126220000_cf247_s1140_selector_v6_entry_recall.sql', 'utf8')
  expect(MIG).toContain("v_run constant text := 's1140-entry-cohort-v6-2026-11-25'; v_from constant text := 's1130-entry-cohort-v4-2026-11-25';")
  expect(MIG.replace(/--.*$/gm, '')).not.toMatch(/lean_qualify_cases\s*\(|reading\.lean_qualify_on|ai_service_routes|ai_route_qualifications|cron\.alter_job|cron\.schedule|\bdelete from\b|truncate /i)
  expect(MIG.split('\n').filter((l) => /^(drop|delete|truncate)\b/i.test(l) || /^alter table .* drop /i.test(l))).toEqual([])
  for (const s of ['post-check: the consumer API moved', 'post-check: manual locks changed', 'post-check: the number of active cron jobs changed']) expect(MIG).toContain(s)
})
