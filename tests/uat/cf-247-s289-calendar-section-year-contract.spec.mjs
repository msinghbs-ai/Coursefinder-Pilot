// Guards: Platform Admin final intake recovery mandate 5 Nov 2026 12:44, R1 and §11 (year from the enclosing heading, table or section; wrong-section year rejected; missing year never assumed; UNSW Term 1 = 15 Feb 2027, Term 2 = 31 May 2027, Term 3 = 13 Sep 2027).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { CALENDAR_PROMPT, CALENDAR_READER, calendarAiParsed, periodName, sectionYear } from '../../supabase/functions/coverage-sweep/calendar.ts'

const page = (f) => fs.readFileSync(`tests/fixtures/intake-calendar-v2/pages/${f}`, 'utf8')
const unsw = page('unsw-academic-calendar.md')
const start = (period, year, month, day, quote, extra = {}) => ({ period, start: { year, month, day, quote }, start_meaning: 'teaching_start', year_quote: '', end: null, application_deadlines: [], ...extra })
const read = (p, periods) => calendarAiParsed([{ scope: 'main_teaching', scope_quote: '', periods }], p, `ai:m:${CALENDAR_READER}`)

test('UNSW: the year comes from the year tabs and the repeated term blocks; 2027 terms start 15 Feb, 31 May and 13 Sep', () => {
  expect(CALENDAR_READER).toBe('calendar-v2.2')
  const r = read(unsw, [
    start('Term 1', 2027, 2, 15, 'Teaching period T1 | 15 Feb - 23 Apr'), start('Term 2', 2027, 5, 31, 'Teaching period T2 | 31 May - 6 Aug'),
    start('Term 3 2027', 2027, 9, 13, 'Teaching period T3 | 13 Sep - 19 Nov'), start('Term 1', null, 2, 16, 'Teaching period T1 | 16 Feb - 24 Apr')])
  const t = Object.fromEntries(r.periods.map((p) => [p.period, p.starts.map((s) => s.date)]))
  expect(t['term 1'].sort()).toEqual(['2026-02-16', '2027-02-15'])
  expect(t['term 2']).toEqual(['2027-05-31'])
  expect(t['term 3']).toEqual(['2027-09-13'])          // the period name loses its printed year
  const t1 = r.periods.find((p) => p.period === 'term 1').starts.find((s) => s.year === 2027)
  expect(t1).toMatchObject({ year_basis: 'tabs', year_quote: 'year tabs 2026 | 2027: block 2 of "### Term 1" is 2027' })
  expect(r.findings.map((f) => f.code)).not.toContain('year_not_printed')
})

test('UNSW: a year from the wrong section is rejected (the 2028 note, the 2026 block); Summer Term 2028 keeps its own heading', () => {
  const r = read(unsw, [
    start('Term 1', 2028, 2, 15, 'Teaching period T1 | 15 Feb - 23 Apr', { year_quote: '### Our academic calendar model is changing in 2028' }),
    start('Term 2', 2027, 6, 1, 'Teaching period T2 | 1 Jun - 7 Aug'),
    start('Summer Term', 2028, 1, 4, 'Summer teaching period U1 | 4 Jan - 11 Feb')])
  expect(r.periods.find((p) => p.period === 'term 1').starts[0]).toMatchObject({ year: null, date: null })
  expect(r.periods.find((p) => p.period === 'term 2').starts[0]).toMatchObject({ year: null, date: null })
  expect(r.periods.find((p) => p.period === 'summer term').starts[0]).toMatchObject({ year: 2028, date: '2028-01-04', year_basis: 'heading', year_quote: '### Summer Term 2028' })
  expect(r.findings.filter((f) => f.code === 'year_from_wrong_section')).toHaveLength(2)
})

test('a quote found in sections of different years is ambiguous; a page with no section year leaves the year unproven', () => {
  expect(sectionYear(unsw, 'Teaching period T1')).toEqual({ year: null, basis: null, quote: '', reason: 'year_ambiguous' })
  const r = read('# Key dates\n| 6 September | Spring session begins |', [start('Spring session', 2027, 9, 6, '6 September | Spring session begins')])
  expect(r.periods[0].starts[0]).toMatchObject({ year: null, date: null })
  expect(r.findings.map((f) => f.code)).toContain('year_not_printed')
})

test('title and ancestor headings: RMIT, Swinburne and Newcastle 2027 editions; the Sydney 2026 edition stays 2026', () => {
  expect(sectionYear(page('rmit-2027-he.md'), '1 March | Semester 1 classes begin (Monday)')).toMatchObject({ year: 2027, basis: 'heading', quote: '# 2027 higher education important dates' })
  expect(sectionYear(page('swinburne-2027-summary.md'), 'Semester 1 | 9 - 21 | Yes | 01 Mar')).toMatchObject({ year: 2027, basis: 'heading', quote: '# 2027 Summary Calendar' })
  expect(sectionYear(page('newcastle-2027.md'), 'Teaching starts | 22 Feb')).toMatchObject({ year: 2027, basis: 'title', quote: '**2027 ACADEMIC CALENDAR**' })
  expect(sectionYear(page('sydney-wall-2026.md'), '23 Feb | Semester 1 classes begin')).toMatchObject({ year: 2026, basis: 'heading' })
  // an old edition: a 2027 claim on the 2026 wall calendar is rejected, never moved to the next year
  const r = read(page('sydney-wall-2026.md'), [start('Semester 1', 2027, 2, 23, '23 Feb | Semester 1 classes begin')])
  expect(r.periods[0].starts[0]).toMatchObject({ year: null, date: null })
  expect(r.findings.map((f) => f.code)).toContain('year_from_wrong_section')
})

test('a deadline is a date only when its own row prints the year; a quote across a heading and its row takes the year under that heading', () => {
  const p = ['  - 2026', '  - 2027', '### Term 1', '| Applications close | 30 Nov |', '### Term 1', '| Applications close | 29 Nov |', '| Teaching period T1 | 15 Feb |'].join('\n')
  const r = read(p, [{ ...start('Term 1', 2027, 2, 15, 'Teaching period T1 | 15 Feb'), application_deadlines: [{ year: 2026, month: 11, day: 29, quote: 'Applications close | 29 Nov', applies_to: 'all' }] }])
  expect(r.periods[0].starts[0]).toMatchObject({ date: '2027-02-15', year_basis: 'tabs' })
  expect(r.periods[0].deadlines[0]).toMatchObject({ year: null, date: null })          // never given the section's year (it may be the year before)
  expect(sectionYear('# Dates\n## 2026\n| a | 1 Feb |\n## 2027\n| Semester 1 begins | 1 March |', '2027 Semester 1 begins')).toMatchObject({ year: 2027 })
})

test('the prompt asks for the enclosing section year and the period name without its year', () => {
  expect(CALENDAR_PROMPT).toContain('Never take a year from a neighbouring section')
  expect(periodName('Term 1 (2027)')).toBe('term 1')
})
