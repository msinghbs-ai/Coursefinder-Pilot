// Guards: CF-247 decision W29 (course-level reading of long pages in bounded slices): a course page's entry requirements are read in contiguous slices that cover the whole stored text, every answer is limited by a setting and a cut answer is named, rows keep their quote on their slice and are joined in page order with a row read twice kept once, and a partial read (a slice failed or cut, or a page longer than its limit) is held whole, never proposed as complete
// No network and no AI: the worker's pure functions (course-entry.ts) run against a long-page fixture and a recorded cut answer.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { courseEntryAnswer, courseEntryCoverage, courseEntryMerge, courseEntryPlan, courseEntrySliceRows, courseEntrySlices, courseEntryUser, COURSE_ENTRY_SLICE_BASIS } from '../../supabase/functions/coverage-sweep/course-entry.ts'
import { htmlToText, pageDataItems } from '../../supabase/functions/coverage-sweep/extract.ts'

const FX = 'tests/fixtures/course-entry'
const html = fs.readFileSync(`${FX}/long-course-page.html`, 'utf8')
const quals = JSON.parse(fs.readFileSync(`${FX}/qualifications.json`, 'utf8'))
// the page text exactly as the worker builds it (entryRead: page data fields, then the page without navigation, header and footer)
const di = pageDataItems(html)
const page = (di ? `Page data fields:\n${di}\n\n` : '') + htmlToText(html.replace(/<(nav|header|footer)\b[\s\S]*?<\/\1>/gi, ' '))
const LIMITS = { pageChars: 100000, sliceChars: 12000, overlapChars: 600, maxSlices: 10 }
// a stand-in for the model: one row for every published minimum printed whole in the slice it is given, quoted as printed
const fakeModel = (sliceText) => ({ rows: quals.filter(([c, q, s]) => sliceText.includes(`${c} ${q} ${s}`)).map(([c, q, s]) => ({
  kind: 'minimum_grade', audience: 'international', description: `Minimum ${q} score`, min_entry_score: null, min_entry_score_basis: null, benchmark_band: null, min_grade: s, confidence: 0.9, quote: `${c} ${q} ${s}` })) })
const answer = (a, finish = 'stop') => ({ model: 'openai/gpt-4.1-mini', choices: [{ finish_reason: finish, message: { content: typeof a === 'string' ? a : JSON.stringify(a) } }], usage: { cost: 0.001 } })
const readAll = (slices, override = {}) => slices.map((s) => {
  const d = override[s.index] ?? answer(fakeModel(s.text))
  const ans = courseEntryAnswer(d, s.index, slices.length)
  return ans.ok ? { index: s.index, ok: true, ...courseEntrySliceRows(ans.a, s.text), cost: 0.001 } : { index: s.index, ok: false, error: ans.error, cost: 0.001 }
})

test('the live fault: a one-call answer cut at its length limit is named output_truncated, not parsed (it was "Unterminated string in JSON")', () => {
  const cut = JSON.parse(fs.readFileSync(`${FX}/single-call-truncated-response.json`, 'utf8'))
  // what the v0.52.0 course read did with it: JSON.parse of the cut answer (the three Monash items failed three times each with this message, at positions 8,061 to 8,598)
  expect(() => JSON.parse(cut.choices[0].message.content)).toThrow('Unterminated string in JSON at position 8100')
  const r = courseEntryAnswer(cut, 0, 1)
  expect(r.ok).toBe(false)
  expect(r.error).toBe('output_truncated: the page reached enrich.course_entry_max_tokens')
  expect(courseEntryAnswer(cut, 2, 4).error).toBe('output_truncated: slice 3 of 4 reached enrich.course_entry_max_tokens')
  // a cut answer whose finish reason is not given is still not taken: it is unreadable, named
  expect(courseEntryAnswer({ ...cut, choices: [{ ...cut.choices[0], finish_reason: 'stop' }] }, 0, 1).error).toMatch(/^unreadable_answer: the page \(Unterminated string in JSON/)
  expect(courseEntryAnswer({ choices: [{ finish_reason: 'error', error: { message: 'upstream' }, message: { content: '' } }] }, 1, 3).error).toBe('no_answer: slice 2 of 3 (upstream)')
})

test('coverage: the slices are the page\'s own characters, contiguous, overlapping, each within the slice size, covering the whole text', () => {
  expect(page.length).toBeGreaterThan(24000)
  const plan = courseEntryPlan(page, LIMITS)
  expect(plan.ok).toBe(true)
  const { slices } = plan
  expect(slices.length).toBe(3)
  expect(slices[0].start).toBe(0)
  expect(slices[slices.length - 1].end).toBe(page.length)
  for (const s of slices) {
    expect(s.text).toBe(page.slice(s.start, s.end))
    expect(s.text.length).toBeLessThanOrEqual(LIMITS.sliceChars)
  }
  for (let i = 1; i < slices.length; i++) {
    const ov = slices[i - 1].end - slices[i].start
    expect(ov).toBeGreaterThanOrEqual(LIMITS.overlapChars / 2)
    expect(ov).toBeLessThanOrEqual(LIMITS.overlapChars)
  }
  expect(courseEntryCoverage(slices, page.length)).toEqual({ complete: true, gaps: [] })
  // a gap is found and named
  expect(courseEntryCoverage([slices[0], slices[2]], page.length).complete).toBe(false)
  // without overlap the slices meet end to start
  const flat = courseEntrySlices(page, 12000, 0)
  for (let i = 1; i < flat.length; i++) expect(flat[i].start).toBe(flat[i - 1].end)
  expect(flat.map((s) => s.text).join('')).toBe(page)
})

test('a page read in one slice is asked exactly as before v0.53.0', () => {
  const short = page.slice(0, 5000)
  const plan = courseEntryPlan(short, LIMITS)
  expect(plan.ok && plan.slices.length).toBe(1)
  expect(courseEntryUser('Example University', 'Bachelor of Example Studies', plan.slices[0], 1, short.length))
    .toBe(`University: Example University\nCourse: Bachelor of Example Studies\n\nPage text:\n${short}`)
  const long = courseEntryPlan(page, LIMITS)
  expect(courseEntryUser('Example University', 'Bachelor of Example Studies', long.slices[1], 3, page.length))
    .toContain(`Part of the page: 2 of 3 (characters ${long.slices[1].start + 1} to ${long.slices[1].end} of ${page.length}); list only the requirements this part states\n\nPage text:\n${long.slices[1].text}`)
})

test('held before any AI call: a page longer than entry.course_page_chars, or one needing more slices than allowed, is never read in part', () => {
  const tooLong = courseEntryPlan(page, { ...LIMITS, pageChars: 20000 })
  expect(tooLong.ok).toBe(false)
  expect(tooLong.reason).toBe(`page text is ${page.length} characters, longer than entry.course_page_chars (20000); a cut page is never read as complete`)
  const tooMany = courseEntryPlan(page, { ...LIMITS, sliceChars: 4000, maxSlices: 5 })
  expect(tooMany.ok).toBe(false)
  expect(tooMany.reason).toMatch(/^page text needs \d+ slices of 4000 characters, more than enrich\.course_entry_max_slices \(5\)$/)
})

test('complete read: every published minimum once, in page order, the rows read twice in an overlap kept once, quotes on the page', () => {
  const { slices } = courseEntryPlan(page, LIMITS)
  // the minimum table runs across the first slice boundary (the case a single cut answer lost)
  const table = [page.indexOf(`${quals[0][0]} ${quals[0][1]}`), page.indexOf(quals[quals.length - 1][1])]
  expect(table[0]).toBeLessThan(slices[0].end)
  expect(table[1]).toBeGreaterThan(slices[1].start)
  const m = courseEntryMerge(slices, readAll(slices), page.length)
  expect(m.complete).toBe(true)
  expect(m.reason).toBe(null)
  expect(m.rows.map((r) => r.quote)).toEqual(quals.map(([c, q, s]) => `${c} ${q} ${s}`))
  expect(m.coverage.duplicates).toBeGreaterThan(0)
  expect(m.coverage).toMatchObject({ basis: COURSE_ENTRY_SLICE_BASIS, page_chars: page.length, slices: 3, answered: 3, complete: true })
  expect(m.coverage.ranges).toEqual(slices.map((s) => [s.start, s.end]))
  for (const r of m.rows) expect(page).toContain(r.quote)
  expect(m.cost).toBeCloseTo(0.003, 6)
  // de-duplication compares as the quote gate does (case and spacing ignored); the same quote with another grade is another row
  const two = [{ index: 0, start: 0, end: 30, text: '' }, { index: 1, start: 20, end: 50, text: '' }]
  const g = (quote, min_grade) => ({ kind: 'minimum_grade', audience: 'all', quote, min_grade })
  const d = courseEntryMerge(two, [{ index: 0, ok: true, rows: [g('China Gaokao 65%', '65%')], dropped: [], cost: 0 },
    { index: 1, ok: true, rows: [g('china  Gaokao 65%', '65 %'), g('China Gaokao 65%', '60%')], dropped: [], cost: 0 }], 50)
  expect(d.complete).toBe(true)
  expect(d.rows.map((r) => r.min_grade)).toEqual(['65%', '60%'])
  expect(d.coverage.duplicates).toBe(1)
  // two slices that do not reach the page's end are not the whole page
  expect(courseEntryMerge(two, [{ index: 0, ok: true, rows: [], dropped: [], cost: 0 }, { index: 1, ok: true, rows: [], dropped: [], cost: 0 }], 60).reason).toBe('1 of 2 slice(s) not read whole: slices leave 1 part(s) of the page unread')
})

test('partial read: a cut, empty or unreadable slice, or a slice not read, holds the whole read with the slices named', () => {
  const { slices } = courseEntryPlan(page, LIMITS)
  const cut = answer(JSON.stringify(fakeModel(slices[1].text)).slice(0, 300), 'length')
  const m = courseEntryMerge(slices, readAll(slices, { 1: cut }), page.length)
  expect(m.complete).toBe(false)
  expect(m.rows).toEqual([])
  expect(m.reason).toBe('1 of 3 slice(s) not read whole: output_truncated: slice 2 of 3 reached enrich.course_entry_max_tokens')
  expect(m.coverage.complete).toBe(false)
  expect(m.coverage.answered).toBe(2)
  expect(m.cost).toBeCloseTo(0.003, 6)  // the cost of every call made is kept on a held read
  const outcomes = readAll(slices)
  outcomes[2] = undefined
  expect(courseEntryMerge(slices, outcomes, page.length).reason).toBe('1 of 3 slice(s) not read whole: slice 3 of 3 not read')
  const bad = courseEntryMerge(slices, readAll(slices, { 0: answer('{"rows": [') , 2: answer('') }), page.length)
  expect(bad.complete).toBe(false)
  expect(bad.reason).toMatch(/^2 of 3 slice\(s\) not read whole: unreadable_answer: slice 1 of 3 .*; no_answer: slice 3 of 3/)
})

test('quote gate per slice: a quote not printed on the slice it was read from is dropped, as an invented one is', () => {
  const { slices } = courseEntryPlan(page, LIMITS)
  const last = `${quals[quals.length - 1][0]} ${quals[quals.length - 1][1]} ${quals[quals.length - 1][2]}`
  expect(page).toContain(last)
  expect(slices[0].text).not.toContain(last)
  const r = courseEntrySliceRows({ rows: [{ kind: 'minimum_grade', quote: last }, { kind: 'minimum_grade', quote: 'Australia ATAR 99.95' }, { kind: 'minimum_grade', quote: 'China Gaokao 65%' }] }, slices[0].text)
  expect(r.rows.map((x) => x.quote)).toEqual(['China Gaokao 65%'])
  expect(r.dropped.map((x) => x.reason)).toEqual(['quote_not_on_page', 'quote_not_on_page'])
})

test('worker and settings: the course read uses the plan, the merge and the five slice settings, and records the cost of a held read', () => {
  const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(w).toMatch(/(const WORKER = "coverage-sweep-worker-v0\.53\.0"; |\/\/ was v0\.53\.0 )\/\/ v0\.53\.0 \(29 Oct 2026, CF-247 AER decision W29/)  // W32 (v0.54.0) keeps the W29 line as "was v0.53.0"
  const read = w.slice(w.indexOf('const entryRead = async'), w.indexOf('const fail = (ids: number[], e: unknown)'))
  for (const k of ['enrich.course_entry_slice_chars', 'enrich.course_entry_max_slices', 'enrich.course_entry_slice_overlap_chars', 'enrich.course_entry_max_tokens', 'enrich.course_entry_slice_concurrency']) expect(read).toContain(k)
  expect(read).toContain('courseEntryPlan(text,')
  expect(read).toContain('courseEntryMerge(plan.slices, outcomes, plan.page_chars)')
  expect(read).toContain('error: `held_partial: ${m.reason}`.slice(0, 300), cost: m.cost / items.length')
  expect(read).not.toContain('.slice(0, chars)')  // the page is never cut to its limit
  const [mig] = fs.readdirSync('supabase/migrations').filter((f) => f.endsWith('_cf247_aer_course_sliced_read.sql'))
  const sql = fs.readFileSync(`supabase/migrations/${mig}`, 'utf8')
  for (const k of ['enrich.course_entry_slice_chars', 'enrich.course_entry_slice_overlap_chars', 'enrich.course_entry_max_slices', 'enrich.course_entry_max_tokens', 'enrich.course_entry_slice_concurrency']) expect(sql).toContain(`('pipeline', '${k}', 'Course entry requirements: `)
  expect(sql).toContain("select pg_temp.edit_n('security.enrich_entry_record_v1(bigint,jsonb)', '0f4d8f90b006f84f4523b110dfa5eaa2'")
})
