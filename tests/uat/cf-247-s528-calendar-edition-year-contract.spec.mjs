// Guards: Decisions 270 and 270a (Platform Admin 10 Nov 2026): a year-less calendar start takes its year only from the page's own edition (table column, range heading over unlabelled columns with weekday and academic-period evidence, enclosing section, address); a printed weekday must agree; a competing year gives no start; a year is never guessed.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { CALENDAR_PROMPT, CALENDAR_READER, addressYear, calendarAiParsed, columnYear, printedWeekdays } from '../../supabase/functions/coverage-sweep/calendar.ts'

const page = (f) => fs.readFileSync(`tests/fixtures/intake-calendar-v2/pages/${f}`, 'utf8')
const start = (period, year, month, day, quote) => ({ period, start: { year, month, day, quote }, start_meaning: 'teaching_start', year_quote: '', end: null, application_deadlines: [] })
const read = (p, periods, url = '') => calendarAiParsed([{ scope: 'main_teaching', scope_quote: '', periods }], p, `ai:m:${CALENDAR_READER}`, false, url)
const first = (r) => r.periods[0].starts[0]

const monash = page('monash-summary-dates.md')
const s1 = 'Semester one<br>teaching period | **2 Mar – 26 Jun** | **1 Mar – 25 Jun** | **28 Feb – 23 Jun**'
const s2 = 'Semester two<br>teaching period | **27 Jul – 18 Nov** | **26 Jul – 19 Nov** | **24 Jul – 17 Nov**'

test('Monash summary-dates: each start takes the year of its own column (Semester 1 = 1 Mar 2027, Semester 2 = 26 Jul 2027)', () => {
  expect(CALENDAR_READER).toBe('calendar-v2.3')
  const r = read(monash, [start('Semester one', null, 3, 1, s1), start('Semester one', null, 2, 28, s1), start('Semester two', null, 7, 26, s2)])
  const one = r.periods.find((p) => p.period === 'semester one').starts
  expect(one.map((s) => s.date).sort()).toEqual(['2026-03-02', '2027-03-01', '2028-02-28'])   // v2.3: the whole row
  expect(one.find((s) => s.date === '2027-03-01')).toMatchObject({ year_basis: 'column', year_quote: '|  | 2026 | 2027 | 2028 |' })
  expect(r.periods.find((p) => p.period === 'semester two').starts[0].date).toBe('2027-07-26')
  // the range heading alone is never an edition year, and a claimed year that is not the column's is refused
  expect(first(read(monash, [start('Semester one', 2026, 3, 1, s1)])).date).toBeNull()
})

test('v2.3: a start resolved by its column stands for its whole row (the model reported only the 2026 column of Monash live)', () => {
  const r = read(monash, [start('Semester one', null, 3, 2, s1), start('Semester two', null, 7, 27, s2)])
  expect(r.periods.find((p) => p.period === 'semester one').starts.map((s) => s.date).sort()).toEqual(['2026-03-02', '2027-03-01', '2028-02-28'])
  expect(r.periods.find((p) => p.period === 'semester two').starts.map((s) => s.date).sort()).toEqual(['2026-07-27', '2027-07-26', '2028-07-24'])
  expect(r.periods[0].starts.every((s) => s.year_basis === 'column' && s.quote === s1)).toBe(true)
  // an orientation row is never expanded into teaching starts (it is not a teaching start)
  const o = read(monash, [{ ...start('Orientation', null, 2, 19, 'Orientation | 19–27 Feb | 18–26 Feb | 17–25 Feb'), start_meaning: 'orientation' }])
  expect(o.periods.flatMap((p) => p.starts)).toHaveLength(0)
})

test('Decision 270a: unlabelled columns under a range heading map only with weekday and academic-period evidence', () => {
  const unlabelled = monash.replace('|  | 2026 | 2027 | 2028 |', '|  |  |  |  |')
  expect(first(read(unlabelled, [start('Semester one', null, 3, 1, s1)]))).toMatchObject({ date: '2027-03-01', year_basis: 'range_columns' })
  // a start on a different weekday in one column: no mapping
  const broken = unlabelled.replace('**28 Feb – 23 Jun**', '**29 Feb – 23 Jun**')
  expect(first(read(broken, [start('Semester one', null, 3, 1, s1.replace('28 Feb', '29 Feb'))])).date).toBeNull()
  // the column count differs from the years of the range: no mapping
  expect(first(read(unlabelled.replace('2026–2028', '2026–2029'), [start('Semester one', null, 3, 1, s1)])).date).toBeNull()
  // starts that are not Mondays need another row printing one year per column in step
  const term = '## Dates 2026–2028\n|  |  |  |  |\n| --- | --- | --- | --- |\n| Term A | 4 Mar | 3 Mar | 1 Mar |'
  expect(first(read(term, [start('Term A', null, 3, 3, 'Term A | 4 Mar | 3 Mar | 1 Mar')])).date).toBeNull()
  const stepped = term + '\n| Supplementary | 1 Jan (2027) | 1 Jan (2028) | 1 Jan (2029) |'
  expect(first(read(stepped, [start('Term A', null, 3, 3, 'Term A | 4 Mar | 3 Mar | 1 Mar')])).date).toBe('2027-03-03')
  expect(columnYear(term, 'Term A | 4 Mar | 3 Mar | 1 Mar', 3, 3)).toMatchObject({ year: null, reason: 'range_columns_unproved' })
})

test('Flinders semester-dates: a year printed in the row must be in the date\'s own cell; the printed weekday agrees', () => {
  const p = page('flinders-semester-dates.md'), row = '1 | 2 March 2026 | 1 March 2027 | 28 February 2028'
  expect(first(read(p, [start('Semester one', 2027, 3, 1, row)])).date).toBe('2027-03-01')
  const wrong = read(p, [start('Semester one', 2026, 3, 1, row)])
  expect(first(wrong).date).toBeNull()
  expect(wrong.findings.map((f) => f.code)).toContain('year_from_wrong_section')
  expect(first(read(p, [start('Summer', 2027, 1, 4, '1 | Monday 5 January 2026 | Monday 4 January 2027 | Monday 3 January 2028')])).date).toBe('2027-01-04')
  expect(CALENDAR_PROMPT).toContain('its week 1 row')
})

test('Deakin 2027 trimester dates: the heading year stands and its weekdays agree; the same rows under a 2026 heading are refused', () => {
  const p = page('deakin-2027-trimester.md')
  expect(first(read(p, [start('Trimester 1', null, 3, 1, 'Monday 1 March | Teaching period begins')]))).toMatchObject({ date: '2027-03-01', year_basis: 'heading' })
  const r = read(p.replace(/2027/g, '2026'), [start('Trimester 1', null, 3, 1, 'Monday 1 March | Teaching period begins')])
  expect(first(r).date).toBeNull()
  expect(r.findings.map((f) => f.code)).toContain('weekday_mismatch')
  expect(printedWeekdays('Tue, Sep 8 and Mon 4 Oct', 9, 8)).toEqual([2])
})

test('the address gives the edition only when no section does and nothing on the page names another year', () => {
  const p = '# Trimester dates\n| Date | Event |\n| --- | --- |\n| Monday 1 March | Teaching period begins |'
  const q = 'Monday 1 March | Teaching period begins'
  expect(first(read(p, [start('Trimester 1', null, 3, 1, q)], 'https://u.edu.au/handbooks/2027-handbook/trimester-dates'))).toMatchObject({ date: '2027-03-01', year_basis: 'address' })
  expect(first(read('# 2026 Trimester dates\n' + p, [start('Trimester 1', null, 3, 1, q)], 'https://u.edu.au/2027-handbook/x')).date).toBeNull()
  expect(first(read(p + '\nUpdated for 2030.', [start('Trimester 1', null, 3, 1, q)], 'https://u.edu.au/2027-handbook/x')).date).toBeNull()
  expect(addressYear('https://u.edu.au/2026/2027/x', p)).toBeNull()
  expect(first(read(p, [start('Trimester 1', null, 3, 1, q)], 'https://u.edu.au/2026-handbook/x')).date).toBeNull()   // Monday 1 March is not 2026
  expect(first(read(p, [start('Trimester 1', null, 3, 1, q)])).date).toBeNull()                                     // no address, no year
})

test('worker v0.66.0 (reader v2.3) passes the document address to the calendar reader', () => {
  const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(IX).toContain('const WORKER = "coverage-sweep-worker-v0.66.0";')
  expect(IX).toContain('calendarAiParsed(answers, md, `ai:${it.model_code}:${CALENDAR_READER}`, cut, String(it.url || ""))')
})

test('QUT teaching periods: years printed in the quote stand as before', () => {
  expect(first(read(page('qut-teaching-periods.md'), [start('Semester 1', 2027, 2, 22, 'Monday 22 February 2027 - Saturday 19 June 2027')]))).toMatchObject({ date: '2027-02-22', year_basis: 'quote' })
})
