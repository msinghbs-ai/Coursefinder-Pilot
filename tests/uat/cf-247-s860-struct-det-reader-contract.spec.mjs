// Guards: S860 deterministic course structure reader (Platform Admin 20 Nov 2026 15:19 AEDT, S1-Structure-Outcomes, $0): a pure reader with no model, fetch or write; every reading's quote is a line of the page word for word; a range, a maximum, a part-time-only length, a non-catalogue unit, an audience line and a collapsed multi-course table line are never offered as a value.
// CF-247 S860. Module supabase/functions/coverage-sweep/struct-det-reader.ts, worker mode struct_det_read (coverage-sweep index.ts).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { structRead, structDecide, structLines, structCollapsed, STRUCT_DET_VERSION } from '../../supabase/functions/coverage-sweep/struct-det-reader.ts'

const SRC = fs.readFileSync('supabase/functions/coverage-sweep/struct-det-reader.ts', 'utf8')
const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const dec = (p) => structDecide(structRead(p))
const val = (p, k) => { const d = dec(p)[k]; return d.state === 'one' ? d.value : d.state }

test('the module is pure: no model, fetch, storage, database or environment access', () => {
  expect(SRC).not.toMatch(/\bfetch\s*\(|openrouter|firecrawl|Deno\.|supabase|\.rpc\(|\.storage\b|XMLHttpRequest/i)
  expect(STRUCT_DET_VERSION).toBe('struct-det-v1.0')
})

test('the worker mode reads stored pages only and returns the reader version the sweep checks', () => {
  const m = IX.slice(IX.indexOf('if (mode === "struct_det_read")'), IX.indexOf('if (mode === "entry_inspect")'))
  expect(m).toContain('c.storage.from("evidence").download(it.storage_path)')
  expect(m).toContain('extractor: STRUCT_DET_VERSION')
  expect(m).toContain('.slice(0, 40)')
  expect(m).not.toMatch(/firecrawl|openrouter|\.from\("[a-z_]+"\)\.(insert|update|upsert|delete)|rpc\(/i)
})

test('labelled duration, study load and delivery mode, on one line or under a label of their own', () => {
  const p = '<dl><dt>Duration</dt><dd>3 years full-time or 6 years part-time</dd><dt>Study mode</dt><dd>On campus</dd></dl>'
  expect(val(p, 'duration')).toEqual({ value: 3, unit: 'years' })
  expect(val(p, 'study_load')).toEqual({ load: 'both' })
  expect(val(p, 'delivery_mode')).toEqual({ mode: 'on_campus' })
  expect(val('<p><strong>Program length:</strong> 2 years (4 semesters)</p><p>Delivery: Online</p>', 'duration')).toEqual({ value: 2, unit: 'years' })
  expect(val('<p>Attendance: Full-time, Part-time</p>', 'study_load')).toEqual({ load: 'both' })
  expect(val('<p>Study mode: Full-time</p>', 'study_load')).toEqual({ load: 'full_time' })
  expect(val('<p>Delivery mode</p><p>Blended</p>', 'delivery_mode')).toEqual({ mode: 'blended' })
  expect(val('<p>Delivery: On campus and online</p>', 'delivery_mode')).toEqual({ mode: 'on_campus_and_online' })
  expect(val('<p>Course duration: 18 months</p>', 'duration')).toEqual({ value: 18, unit: 'months' })
  expect(val('<p>Duration: 2 semesters</p>', 'duration')).toEqual({ value: 2, unit: 'semesters' })
})

test('display items of an APEX catalogue page (University of Auckland) read as labelled lines', () => {
  const p = '<span id="P5_DURATION_FULL_TIME" class="display_only">1 Year</span><span id="P5_DELIVERY_MODE" class="display_only">Campus Experience</span>'
  expect(val(p, 'duration')).toEqual({ value: 1, unit: 'years' })
  expect(val(p, 'delivery_mode')).toEqual({ mode: 'on_campus' })
})

test('a sentence that ties a length to full-time study is a stated reading; other sentences are not read', () => {
  const r = structRead('<p>The Bachelor of Science is a 3 year full-time degree.</p>')
  expect(r.find((x) => x.key === 'duration')).toMatchObject({ value: { value: 3, unit: 'years' }, strength: 'stated' })
  expect(dec('<p>Students complete 3 years of study in the sciences.</p>').duration.state).toBe('none')
})

test('never guessed: ranges, maxima, part-time-only lengths, trimesters, credits and audience lines', () => {
  expect(dec('<p>Duration: 1-2 years</p>').duration.state).toBe('none')
  expect(dec('<p>Duration: up to 6 years</p>').duration.state).toBe('none')
  expect(dec('<p>Duration: 6 years part-time</p>').duration.state).toBe('none')
  expect(dec('<p>Duration: 6 trimesters</p>').duration.state).toBe('none')
  expect(dec('<p>Duration</p><p>360 credits</p>').duration.state).toBe('none')
  expect(dec('<p>Study mode: International students must study full-time</p>').study_load.state).toBe('none')
  expect(dec('<p>Delivery: Flexible</p>').delivery_mode.state).toBe('none')
  const notes = structRead('<p>Duration: 1-2 years</p>').filter((x) => x.key === 'other')
  expect(notes[0]?.value).toEqual({ field: 'duration', note: 'range' })
})

test('collapsed multi-course tables are never offered as a value, and two lengths on one page are a conflict', () => {
  expect(structCollapsed('Bachelor of Arts 3 years Master of Arts 2 years')).toBe(true)
  expect(structCollapsed('Duration | 3 years | 2 years')).toBe(true)
  expect(dec('<table><tr><td>Bachelor of Arts | 3 years</td></tr><tr><td>Master of Arts | 2 years</td></tr></table>').duration.state).toBe('none')
  expect(dec('<p>Duration: 4 years</p><p>Duration: 3 years</p>').duration.state).toBe('conflict')
})

test('every quote is a line of the page text, word for word', () => {
  const p = '<div><h2>Key facts</h2><p>Duration: 3 years full-time</p><p>Delivery: On campus</p><p>Study mode: Full-time or part-time</p></div>'
  const lines = structLines(p)
  for (const r of structRead(p)) expect(lines).toContain(r.quote)
})
