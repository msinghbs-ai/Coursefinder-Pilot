// Guards: Platform Admin 25 Nov 2026 08:16 AEDT (P0 AER preprocessing, Admin #1063: validate academic requirement recall, conditions and footnotes in the selected content against the source evidence before volume)
// s1130: lean-sections-v4 selects entry condition sentences that print neither "entry" nor "requirement" (the s1125 regression misses), and still leaves the rest of a course page out.
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
const overview = '<p>Our graduates work across hospitals, clinics and the community, learning in simulation labs with experienced teachers.</p>'.repeat(20)
const page = (body) => `<html><body><main><h1>Course</h1><h2>Overview</h2>${overview}<h2>Placements</h2>${body}<h2>Careers</h2><p>Nurse, carer, manager.</p></main></body></html>`

// the rows the s1125 regression found outside the v3 selection (earlier answers checked on their pages, and Layer 4 accepted rows)
const MISSED = [
  'Applicants will be required to hold a valid Working with Children Check (WWCC).',
  'Applicants will be required to hold a valid Police Check which is renewed annually.',
  'Prior to commencing a placement, students will be required to complete a National Disability Insurance Scheme (NDIS) Worker Screening Check.',
  'Applicants must demonstrate that they have been involved in some form of high-level music making for at least two years.',
  'The 12-month full-time GMBA is designed exclusively for professionals with 2+ years of work experience.',
  'Graduate with an AUSTRALIAN DEGREE (AQF Level 9)',
]

test('s1130: each missed entry condition is selected under a heading that names no entry requirement', async () => {
  const lean = await load('supabase/functions/coverage-sweep/lean-input.ts', 'li1130')
  const aer = await load('supabase/functions/coverage-sweep/aer-v2.ts', 'av1130')
  const sec = await load('supabase/functions/coverage-sweep/lean-sections.ts', 'ls1130')
  expect(['lean-sections-v4', 'lean-sections-v5']).toContain(sec.LEAN_SECTIONS)  // v5 (s1135) keeps v4's signals
  for (const q of MISSED) {
    const s = sec.selectSections(aer.aerV3Blocks(lean.leanText(page(`<p>${q}</p>`)), null), 'entry_requirements')
    expect(s.no_selection, q).toBe(false)
    expect(sec.holds(s.plain, [q]), q).toBe(true)
    expect(s.plain, q).not.toContain('simulation labs')  // the overview stays out
    expect(s.signal, q).toBe('likely')
  }
})

test('s1130: a page with no entry condition still selects nothing from its overview and careers', async () => {
  const lean = await load('supabase/functions/coverage-sweep/lean-input.ts', 'li1130b')
  const aer = await load('supabase/functions/coverage-sweep/aer-v2.ts', 'av1130b')
  const sec = await load('supabase/functions/coverage-sweep/lean-sections.ts', 'ls1130b')
  const s = sec.selectSections(aer.aerV3Blocks(lean.leanText(page('<p>Placements are arranged in your second and third year at partner hospitals.</p>')), null), 'entry_requirements')
  expect(s.plain).not.toContain('simulation labs')
  expect(s.plain).not.toContain('partner hospitals')
  // the other fields are unchanged by v4 (the new signal is the entry field's only)
  expect(sec.fieldHit('duration', 'Applicants will be required to hold a valid Police Check')).toBe('no_signal')
  expect(sec.fieldHit('entry_requirements', 'Applicants will be required to hold a valid Police Check')).toBe('likely')
})

test('s1130: the recall check is seeded again under v4 with the same labels and the accepted rows, no AI, nothing switched on', () => {
  const MIG = fs.readFileSync('supabase/migrations/20261126200000_cf247_s1130_selector_v4_entry_recall.sql', 'utf8')
  expect(MIG).toContain("v_run constant text := 's1130-entry-cohort-v4-2026-11-25'; v_from constant text := 's1125-entry-cohort-2026-11-25';")
  expect(MIG).toContain("where c.run_label = 's1125-entry-qualify-2026-11-25' and c.gold_source = 'aer_accepted'")
  expect(MIG.replace(/--.*$/gm, '')).not.toMatch(/lean_qualify_cases\s*\(|reading\.lean_qualify_on|ai_service_routes|ai_route_qualifications|cron\.alter_job|cron\.schedule|\bdelete from\b|truncate /i)
  expect(MIG.split('\n').filter((l) => /^(drop|delete|truncate)\b/i.test(l) || /^alter table .* drop /i.test(l))).toEqual([])
  for (const s of ['post-check: the consumer API moved', 'post-check: manual locks changed', 'post-check: the number of active cron jobs changed']) expect(MIG).toContain(s)
})
