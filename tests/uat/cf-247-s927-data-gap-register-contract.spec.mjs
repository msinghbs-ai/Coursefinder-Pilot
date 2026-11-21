// Guards: the daily data gap register (Platform Admin 21 Nov 2026 12:19, answers 12:2x): one row per open gap (course × field) by country, all open gaps including "not published by the provider", the first day each gap was seen carried from the last register, a gap leaving the register the day its field is admitted (and listed as closed), institution × field files saying what is being worked on, a Google Sheet summary with the change as a formula, nothing for a country whose scope is not started, and files under the Drive upload limit.
// CF-247 S927. scripts/telemetry/data-gap-register.mjs; scripts/telemetry/course-field-readiness.sql (raw column); .github/workflows/course-field-readiness.yml
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { FIELDS, MAX_PART_BYTES } from '../../scripts/telemetry/course-field-readiness.mjs'
import { register, gapOf, GAP_NAMES, RAW_ATTR } from '../../scripts/telemetry/data-gap-register.mjs'

const admitted = Object.fromEntries(FIELDS.map((f) => [f, `value ${f}`]))
const course = (id, cc, provider, over = {}, raw = {}) => ({ course_id: id, country_code: cc, provider_id: `p-${provider}`, provider_name: `Uni ${provider}`,
  course_title: `Course ${id}`, cells: { ...admitted, ...over }, raw })
const lines = (files, cc) => files.filter((f) => f.country === cc).flatMap((f) => f.content.trim().split('\n').slice(1))

test('gap labels: the coverage state behind each readiness state', () => {
  expect(gapOf('official_url', 'TRYING', { official_url: 'in_review' })).toBe('Waiting for a person')
  expect(gapOf('official_url', 'TRYING', { official_url: 'page_found' })).toBe('Being checked')
  expect(gapOf('english_requirements', 'POSSIBLE_NEEDS_SOURCE', { english: 'no_website' })).toBe('No website on record')
  expect(gapOf('intake_dates', 'POSSIBLE_NEEDS_SOURCE', { intakes: 'blocked' })).toBe('Site blocked')
  expect(gapOf('aer_academic', 'POSSIBLE_NEEDS_SOURCE', { academic_entry: 'no_reader' })).toBe('No reader yet')
  expect(gapOf('description', 'POSSIBLE_NEEDS_SOURCE', { description: 'site_known' })).toBe('Page not found yet')
  expect(gapOf('scholarships', 'POSSIBLE_NEEDS_SOURCE', {})).toBe('No scholarship found yet')
  expect(gapOf('tuition_fee', 'NOT_POSSIBLE', {})).toBe('Not published by the provider')
  expect(gapOf('duration', 'ADMITTED', {})).toBeNull()
  expect(gapOf('career_outcomes', 'EMPTY_NOT_STARTED', {})).toBeNull()
  for (const f of Object.keys(RAW_ATTR)) expect(FIELDS).toContain(f)
})

test('one row per open gap by country; not-started scope has no rows; fee basis is only its own gap when the fee is held', () => {
  const rows = [
    course('a1', 'AU', 'A', { official_url: 'TRYING', english_requirements: 'NOT_POSSIBLE' }, { official_url: 'in_review' }),
    course('a2', 'AU', 'A', { tuition_fee: 'POSSIBLE_NEEDS_SOURCE', fee_basis: 'POSSIBLE_NEEDS_SOURCE' }),
    course('a3', 'AU', 'B', { fee_basis: 'NOT_POSSIBLE' }),
    course('c1', 'CA', 'C', { aer_academic: 'EMPTY_NOT_STARTED' }),
  ]
  const { files, tabs, totals } = register(rows, '2026-11-21', null)
  const au = lines(files, 'AU')
  expect(au).toHaveLength(4) // a1 url + english, a2 fee (not its basis), a3 basis
  expect(au.some((l) => l.includes(',a1,') && l.includes('official_url,Waiting for a person,2026-11-21,0,'))).toBe(true)
  expect(au.some((l) => l.includes(',a1,') && l.includes('Not published by the provider'))).toBe(true)
  expect(au.filter((l) => l.includes(',a2,')).map((l) => l.split(',')[4])).toEqual(['tuition_fee'])
  expect(au.some((l) => l.includes(',a3,') && l.includes('fee_basis'))).toBe(true)
  expect(lines(files, 'CA')).toHaveLength(0)
  expect(totals.open).toBe(4)
  expect(tabs.Summary.some((r) => r[0] === 'CA' && r[1] === 'aer_academic' && r[2] === 1)).toBe(true)
  const { instFiles } = register(rows, '2026-11-21', null)
  const inst = instFiles.find((f) => f.country === 'AU').content.trim().split('\n')
  expect(inst[0].split(',').slice(0, 5)).toEqual(['country_code', 'institution', 'field', 'open_gaps', 'worked_on_now'])
  expect(inst[0]).toContain('waiting_for_a_person')
  expect(inst.find((l) => l.startsWith('AU,Uni A,official_url,'))).toMatch(/^AU,Uni A,official_url,1,Yes,/)
  expect(inst.find((l) => l.startsWith('AU,Uni A,english_requirements,'))).toMatch(/^AU,Uni A,english_requirements,1,No,/)
  const top = tabs.Institutions_Top
  expect(top[1].slice(0, 4)).toEqual(['Country', 'Institution', 'Active courses', 'Open gaps'])
  expect(top.find((r) => r[0] === 'AU' && r[1] === 'Uni A').slice(2, 4)).toEqual([2, 3])
})

test('the next register keeps the first-seen day, drops admitted gaps and lists them as closed', () => {
  const day1 = register([course('a1', 'AU', 'A', { official_url: 'POSSIBLE_NEEDS_SOURCE', intake_dates: 'TRYING' }), course('a2', 'AU', 'A', { duration: 'TRYING' })], '2026-11-21', null)
  const prev = JSON.parse(JSON.stringify(day1.state))
  const day2 = register([course('a1', 'AU', 'A', { official_url: 'POSSIBLE_NEEDS_SOURCE' })], '2026-11-23', prev)
  const au = lines(day2.files, 'AU')
  expect(au).toHaveLength(1)
  expect(au[0]).toContain('official_url,Page not found yet,2026-11-21,2,')
  const closed = day2.closedCsv.trim().split('\n').slice(1)
  expect(closed).toHaveLength(2)
  expect(closed.some((l) => l.includes(',a1,') && l.includes('intake_dates,Admitted,2026-11-21,2026-11-23'))).toBe(true)
  expect(closed.some((l) => l.includes('a2') && l.includes('duration,Course no longer active'))).toBe(true)
  expect(day2.tabs.Closed_Today.find((r) => r[0] === 'AU' && r[1] === 'intake_dates')[2]).toBe(1)
  const sumRows = day2.tabs.Summary
  const i = sumRows.findIndex((r) => r[0] === 'AU' && r[1] === 'intake_dates' && r[2] === 'Being checked')
  expect(sumRows[i].slice(3)).toEqual([0, 1, `=D${i + 1}-E${i + 1}`])
  expect(lines(day2.instFiles, 'AU').find((l) => l.startsWith('AU,Uni A,official_url,'))).toBeTruthy()
})

test('country files are split under the Drive upload limit, the header in every part, every gap once', () => {
  const rows = Array.from({ length: 40 }, (_, i) => course(`a${String(i).padStart(3, '0')}`, 'AU', 'A', { description: 'POSSIBLE_NEEDS_SOURCE', english_requirements: 'NOT_POSSIBLE' }))
  const { files } = register(rows, '2026-11-21', null, 2000)
  expect(files.length).toBeGreaterThan(1)
  files.forEach((f, i) => {
    expect(f.name).toBe(`Data_Gap_Register_AU_Part${i + 1}_2026-11-21.csv`)
    expect(f.bytes).toBeLessThanOrEqual(2000)
    expect(f.content.split('\n')[0]).toBe('country_code,institution,course_id,course_title,field,gap,first_seen,days_open,provider_id')
  })
  expect(lines(files, 'AU')).toHaveLength(80)
  expect(MAX_PART_BYTES).toBeLessThan(2_900_000)
})

test('the export carries the raw coverage states read only, and the daily workflow builds the register from yesterday\'s state', () => {
  const sql = fs.readFileSync('scripts/telemetry/course-field-readiness.sql', 'utf8')
  expect(sql).toContain("'english', x.m->'english'->>'s'))) r where r.value <> 'admitted') raw")
  expect(sql).toContain('begin transaction read only;')
  const wf = fs.readFileSync('.github/workflows/course-field-readiness.yml', 'utf8')
  expect(wf).toContain('git show FETCH_HEAD:monitoring/course-readiness/Data_Gap_State.json.gz')
  expect(wf).toContain('node scripts/telemetry/data-gap-register.mjs "$RUNNER_TEMP/out" "$DATE" "$prev" "$RUNNER_TEMP"/parts/*.json')
  expect(wf.indexOf('Data gap register (s927)')).toBeLessThan(wf.indexOf('Commit to the snapshot branch'))
})
