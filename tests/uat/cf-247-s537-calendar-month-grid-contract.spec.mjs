// Guards: Platform Admin 12 Nov 2026 20:57 ("fix calendar readers"), reader calendar-v2.4: a month-grid start takes its month from the month-only heading above its row, only when the reader's month agrees, the row begins with the day, the quote is on the page once and no other month heading lies between; otherwise month_not_in_quote.
import { test, expect } from '@playwright/test'
import { CALENDAR_READER, calendarAiParsed, sectionMonth } from '../../supabase/functions/coverage-sweep/calendar.ts'

const grid = ['# 2027 Academic Calendar', '', 'February', '22–26 Trimester 1 orientation for commencing students (all campuses)', '',
  'March', '1 Commencement of Trimester 1', '', 'July', '5–9 Trimester 2 orientation for commencing students', '12 Commencement of Trimester 2', '',
  'NOVEMBER 2027', '1 Commencement of Trimester 3'].join('\n')
const start = (period, month, day, quote, year = null) => ({ period, start: { year, month, day, quote }, start_meaning: 'teaching_start', year_quote: '', end: null, application_deadlines: [] })
const read = (p, periods) => calendarAiParsed([{ scope: 'main_teaching', scope_quote: '', periods }], p, `ai:m:${CALENDAR_READER}`, false, '')
const st = (r) => r.periods.flatMap((p) => p.starts)

test('Griffith-style month grid: each trimester start takes its month from the heading and its year from the title', () => {
  expect(CALENDAR_READER).toBe('calendar-v2.4')
  const r = read(grid, [start('Trimester 1', 3, 1, '1 Commencement of Trimester 1'), start('Trimester 2', 7, 12, '12 Commencement of Trimester 2'), start('Trimester 3', 11, 1, '1 Commencement of Trimester 3')])
  expect(st(r).map((s) => s.date).sort()).toEqual(['2027-03-01', '2027-07-12', '2027-11-01'])
  expect(st(r).find((s) => s.date === '2027-03-01')).toMatchObject({ month_basis: 'heading', month_quote: 'March' })
  expect(r.findings.map((f) => f.code)).not.toContain('month_not_in_quote')
})

test('a month the heading does not give is refused (the reader said February, the heading says March)', () => {
  const r = read(grid, [start('Trimester 1', 2, 1, '1 Commencement of Trimester 1')])
  expect(st(r)).toHaveLength(0)
  expect(r.findings.map((f) => f.code)).toContain('month_not_in_quote')
})

test('no heading, a row that does not begin with the day, or a quote printed twice: refused', () => {
  expect(sectionMonth('1 Commencement of Trimester 1', '1 Commencement of Trimester 1', 3, 1)).toBeNull()
  expect(sectionMonth('March\nCommencement of Trimester 1 on the 1st', 'Commencement of Trimester 1 on the 1st', 3, 1)).toBeNull()
  expect(sectionMonth('March\n1 Commencement of Trimester 1\nApril\n1 Commencement of Trimester 1', '1 Commencement of Trimester 1', 3, 1)).toBeNull()
  expect(sectionMonth(grid, '12 Commencement of Trimester 2', 7, 12)).toBe('July')
  expect(sectionMonth(grid, '12 Commencement of Trimester 2', 7, 2)).toBeNull()
})

test('a month printed in the quote still decides as before (no heading needed)', () => {
  const r = read('# 2027 dates\nSemester 1 starts 22 February 2027', [start('Semester 1', 2, 22, 'Semester 1 starts 22 February 2027', 2027)])
  expect(st(r)[0]).toMatchObject({ date: '2027-02-22' })
  expect(st(r)[0].month_basis).toBeUndefined()
})
