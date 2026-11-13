// Guards: F-INT calendar qualification (Platform Admin decision 13 Nov 2026 13:03, Massey): a main teaching calendar that also lists exam periods is read for its explicitly labelled teaching starts only; a year printed in a heading that names the same period proves the year; every other refusal stays.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFileSync } from 'node:child_process'

async function parser() {
  const out = path.join(os.tmpdir(), `s541-policy-${process.pid}.mjs`)
  execFileSync('node_modules/.bin/esbuild', ['supabase/functions/coverage-sweep/policy.ts', '--bundle', '--format=esm', '--platform=node', `--outfile=${out}`, '--log-level=error'])
  return import(out)
}

const MASSEY = `# Key dates for semesters, exam periods and other events
## Semester One 2027
| Event | Date |
|---|---|
| Semester and lectures start | 22 February |
| Applications close | 1 December |
| Exam period start | 7 June |
## Semester Two 2027
| Event | Date |
|---|---|
| Semester and lectures start | 12 July |
| Exam period start | 25 October |
## Trimester dates 2027
- Trimester 2 begins Monday 5 July
`

test('parser: a start under a heading that names the same period keeps that heading as year_quote; exam, deadline and other headings give no start proof', async () => {
  const { calendarStarts } = await parser()
  const per = Object.fromEntries(calendarStarts(MASSEY).periods.map((p) => [p.period, p]))
  expect(per['semester 1'].starts).toEqual([{ year: 2027, month: 2, day: 22, date: '2027-02-22', quote: 'Semester and lectures start | 22 February', year_quote: 'Semester One 2027', year_basis: 'heading' }])
  expect(per['semester 2'].starts).toEqual([{ year: 2027, month: 7, day: 12, date: '2027-07-12', quote: 'Semester and lectures start | 12 July', year_quote: 'Semester Two 2027', year_basis: 'heading' }])
  // exam rows are never starts (their month stays in the reader's months, as before)
  expect(per['semester 1'].starts.some((s) => s.month === 6)).toBe(false)
  expect(per['semester 2'].starts.some((s) => s.month === 10)).toBe(false)
  // a deadline row gets no heading proof (its year usually falls before the heading's)
  expect(per['semester 1'].deadlines[0]).not.toHaveProperty('year_quote')
  // a heading that does not name the period ("Trimester dates 2027") is no proof
  expect(per['trimester 2'].starts[0]).not.toHaveProperty('year_quote')
})

test('parser: the intake-dates fixture reads exactly as before (no heading proof appears where the heading names no period)', async () => {
  const { calendarStarts } = await parser()
  const Y = new Date().getFullYear()
  const md = fs.readFileSync('tests/fixtures/intake-dates/calendar.md', 'utf8').replaceAll('{N}', String(Y + 1)).replaceAll('{Y}', String(Y))
  expect(JSON.stringify(calendarStarts(md))).not.toContain('year_quote')
})

const mig = fs.readFileSync('supabase/migrations/20261113313000_cf247_calendar_qualify_exam_periods.sql', 'utf8')

test('qualifier: shared event words and teaching-start wording are settings; a shared word lets a page through only when every start in the window is quoted as a teaching start', () => {
  expect(mig).toContain("'central.calendar_qualify_shared_event_words', '[\"exam\"]'::jsonb")
  expect(mig).toContain("'central.calendar_qualify_teaching_start_words'")
  expect(mig).toContain('"semester and lectures start"')
  expect(mig).toContain("and not (w = any (cfg.shared) and exists (select 1 from win)")
  expect(mig).toContain("and not exists (select 1 from win w2 where not exists (select 1 from unnest(cfg.tstart) t where position(t in lower(coalesce(w2.quote, ''))) > 0)))")
  // the approved calendars used for contradiction keep a page whose address has only a shared word
  expect(mig).toContain('position(w in lower(x.url)) > 0 and not (w = any (cfg.shared)))),')
})

test('qualifier: md5-guarded edit, post-checked, nothing dropped, housekeeping lines present', () => {
  expect(mig).toContain("pg_temp.edit_all('security.calendar_qualify_check_v1(uuid)', '045d505668295345f8063e4e0dc65feb', 'accbbc5395c85e537d45eaaba25a2196'")
  expect(mig).toContain("if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)'")
  expect(mig).toMatch(/<> 'accbbc5395c85e537d45eaaba25a2196' then\s+raise exception 'post-check/)
  expect(mig).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(mig).toMatch(/^-- Replaces: security\.calendar_qualify_check_v1/m)
  expect(mig).toMatch(/^-- Retires: nothing\./m)
})
