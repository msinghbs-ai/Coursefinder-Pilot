// Guards: Platform Admin 25 Nov 2026 12:01 AEDT (P0 AER preprocessing qualification: recover the genuine missed pathway and conditional admission statements through the existing meaningful-content selector; exclude rows that are not academic requirements, with evidence)
// s1135: lean-sections-v5 selects pathway and conditional admission sentences; a course description sentence and cost notes stay out; the recall check is reseeded under v5.
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
// the four earlier answer rows outside v4 that are genuine pathway or conditional admission statements (run s1130-entry-cohort-v4-2026-11-25)
const GENUINE = [
  'You may also be considered if you have: Completed an Australian Diploma or Advanced Diploma (or equivalent) in a relevant field.',
  'Applicants may be admitted to the Graduate Diploma of Counselling if they have previously successfully completed a relevant bachelor degree.',
  'Applicants with non-relevant degrees will be considered on the basis of their work and life experience.',
  'Provided you meet the required academic and work-ready criteria.',
]
// the three that are not academic entry requirements (the earlier answer listed them wrongly): a course description and two cost notes
const NOT_REQUIREMENTS = [
  'The course features private tuition for voice and instrument studies and extensive performance and studio experiences.',
  'Students should allow approximately AUD$100 for a uniform, name badge and equipment.',
  'Clinical placements may incur accommodation and travel costs, and these will vary depending on the placement venue.',
]

test('s1135: each genuine pathway or conditional admission sentence is selected, likely, and the overview stays out', async () => {
  const lean = await load('supabase/functions/coverage-sweep/lean-input.ts', 'li1135')
  const aer = await load('supabase/functions/coverage-sweep/aer-v2.ts', 'av1135')
  const sec = await load('supabase/functions/coverage-sweep/lean-sections.ts', 'ls1135')
  expect(sec.LEAN_SECTIONS).toBe('lean-sections-v5')
  for (const q of GENUINE) {
    const s = sec.selectSections(aer.aerV3Blocks(lean.leanText(page(`<p>${q}</p>`)), null), 'entry_requirements')
    expect(sec.holds(s.plain, [q]), q).toBe(true)
    expect(s.signal, q).toBe('likely')
    expect(s.plain, q).not.toContain('experienced teachers')
  }
})

test('s1135: the sentences that are not entry requirements give no entry signal of their own', async () => {
  const sec = await load('supabase/functions/coverage-sweep/lean-sections.ts', 'ls1135b')
  for (const q of NOT_REQUIREMENTS) expect(sec.fieldHit('entry_requirements', q), q).not.toBe('likely')
})

test('s1135: the recall check is reseeded under v5 from the v4 labels, no AI, nothing switched on', () => {
  const MIG = fs.readFileSync('supabase/migrations/20261126210000_cf247_s1135_selector_v5_entry_recall.sql', 'utf8')
  expect(MIG).toContain("v_run constant text := 's1135-entry-cohort-v5-2026-11-25'; v_from constant text := 's1130-entry-cohort-v4-2026-11-25';")
  expect(MIG).toContain("and x.gold_source in ('ai_earlier', 'aer_accepted')")
  expect(MIG.replace(/--.*$/gm, '')).not.toMatch(/lean_qualify_cases\s*\(|reading\.lean_qualify_on|ai_service_routes|ai_route_qualifications|cron\.alter_job|cron\.schedule|\bdelete from\b|truncate /i)
  expect(MIG.split('\n').filter((l) => /^(drop|delete|truncate)\b/i.test(l) || /^alter table .* drop /i.test(l))).toEqual([])
  for (const s of ['post-check: the consumer API moved', 'post-check: manual locks changed', 'post-check: the number of active cron jobs changed']) expect(MIG).toContain(s)
})
