// Guards: Catalogue CSV export (Platform Admin 16 Nov 2026 22:12, Feature 2): one shared control on the catalogue table writes the whole filtered list (every page of the same governed read), "visible columns" with only the shown headings and cells in order, "all columns" with every field; RFC 4180 escaping (commas, quotes, newlines; null empty), UTF-8 with BOM, CRLF, file name <list>-<yyyy-mm-dd>.csv
// CF-247 S569. src/lib/csv-export.js, src/CsvExport.jsx, src/mature-main.jsx (Catalogue). No migration.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { csvCell, csvFilename, elementText, exportColumns, readAllPages, toCsv } from '../../src/lib/csv-export.js'

const PROVIDERS = [
  { id: 'p1', canonical_name: 'University of Sydney, Camperdown', country_code: 'AU', city: 'Sydney', course_count: 812, university_groups: ['Go8', 'WUN'], note: null },
  { id: 'p2', canonical_name: 'The "Best" Institute', country_code: 'NZ', city: 'Auckland\nCBD', course_count: 0, university_groups: [], note: '=HYPERLINK("x")' },
]
const COURSES = [
  { course_id: 'c1', canonical_title: 'Bachelor of Arts, Honours', provider_name: 'UNSW', intl_fee_amount: 45000, description: 'Line one\r\nLine two', last_verified_at: null },
  { course_id: 'c2', canonical_title: 'Master of "Data"', provider_name: null, intl_fee_amount: -5, description: '', last_verified_at: '2026-11-16' },
]
const PROVIDER_VISIBLE = [{ key: 'canonical_name', label: 'Provider' }, { key: 'city', label: 'City' }, { key: 'course_count', label: 'Courses' }, { key: 'university_groups', label: 'Group' }]
const COURSE_VISIBLE = [{ key: 'canonical_title', label: 'Course' }, { key: 'provider_name', label: 'Provider' }, { key: 'intl_fee_amount', label: 'International fee' }, { key: 'description', label: 'Course description' }]
const records = (csv) => csv.replace(/^﻿/, '').replace(/\r\n$/, '')

test('RFC 4180 cells: commas, quotes, CR/LF quoted with quotes doubled; null and undefined empty; numbers as numbers; formula text neutralised', () => {
  expect(csvCell('a,b')).toBe('"a,b"')
  expect(csvCell('say "hi"')).toBe('"say ""hi"""')
  expect(csvCell('x\ny')).toBe('"x\ny"')
  expect(csvCell(null)).toBe('')
  expect(csvCell(undefined)).toBe('')
  expect(csvCell(-5)).toBe('-5')
  expect(csvCell('-5')).toBe('-5')
  expect(csvCell('=SUM(A1)')).toBe("'=SUM(A1)")
  expect(csvCell(['Go8', 'WUN'])).toBe('Go8; WUN')
  expect(csvCell({ a: 1 })).toBe('"{""a"":1}"')
})

test('Providers, visible columns: only the shown headings and cells, in order; BOM and CRLF', () => {
  const csv = toCsv(PROVIDERS, exportColumns(PROVIDER_VISIBLE, 'visible', PROVIDERS))
  expect(csv.startsWith('﻿')).toBe(true)
  expect(csv.endsWith('\r\n')).toBe(true)
  expect(records(csv)).toBe([
    'Provider,City,Courses,Group',
    '"University of Sydney, Camperdown",Sydney,812,Go8; WUN',
    '"The ""Best"" Institute","Auckland\nCBD",0,',
  ].join('\r\n'))
})

test('Courses, visible columns, and all columns with every field in first-seen order', () => {
  const vis = toCsv(COURSES, exportColumns(COURSE_VISIBLE, 'visible', COURSES))
  expect(records(vis).split('\r\n')[0]).toBe('Course,Provider,International fee,Course description')
  expect(records(vis)).toContain('"Bachelor of Arts, Honours",UNSW,45000,"Line one\r\nLine two"')
  expect(records(vis)).toContain('"Master of ""Data""",,-5,')
  const all = exportColumns(COURSE_VISIBLE, 'all', COURSES)
  expect(all.map((c) => c.key)).toEqual(['course_id', 'canonical_title', 'provider_name', 'intl_fee_amount', 'description', 'last_verified_at'])
  const allCsv = records(toCsv(COURSES, all))
  expect(allCsv.split('\r\n')[0]).toBe('course_id,canonical_title,provider_name,intl_fee_amount,description,last_verified_at')
  expect(allCsv).toContain(',2026-11-16')
  const allProv = exportColumns(PROVIDER_VISIBLE, 'all', PROVIDERS).map((c) => c.key)
  expect(allProv).toEqual(['id', 'canonical_name', 'country_code', 'city', 'course_count', 'university_groups', 'note'])
  expect(records(toCsv(PROVIDERS, exportColumns([], 'all', PROVIDERS)))).toContain(`"'=HYPERLINK(""x"")"`)
})

test('a visible column worked out on screen exports the words of its cell', () => {
  const chip = { type: () => null, props: { label: 'Off · directory site' } }
  const cell = { type: 'span', props: { children: ['Admitted', { type: 'small', props: { children: ' 16 Nov' } }] } }
  expect(elementText(chip)).toBe('Off · directory site')
  expect(elementText(cell)).toBe('Admitted 16 Nov')
  const cols = exportColumns([{ key: '_sch_search', label: 'Scholarship search', render: () => chip }], 'visible', PROVIDERS)
  expect(records(toCsv(PROVIDERS.slice(0, 1), cols))).toBe('Scholarship search\r\nOff · directory site')
})

test('every filtered row, page by page, until the total; Cancel stops it', async () => {
  const all = Array.from({ length: 450 }, (_, i) => ({ id: i }))
  const asked = []
  const read = async (offset, limit) => { asked.push([offset, limit]); return { rows: all.slice(offset, offset + Math.min(limit, 200)), total: all.length } }
  const got = await readAllPages(read, { pageSize: 200 })
  expect(got.length).toBe(450)
  expect(asked).toEqual([[0, 200], [200, 200], [400, 200]])
  const ac = new AbortController(); ac.abort()
  await expect(readAllPages(read, { pageSize: 200, signal: ac.signal })).rejects.toThrow('export_cancelled')
})

test('file name, and the control on the shared catalogue table reading the same governed read', () => {
  expect(csvFilename('Providers', new Date(2026, 10, 17))).toBe('providers-2026-11-17.csv')
  expect(csvFilename('course-readiness', new Date(2026, 0, 5))).toBe('course-readiness-2026-01-05.csv')
  const shell = fs.readFileSync('src/mature-main.jsx', 'utf8')
  expect(shell).toContain("import{CsvExport}from'./CsvExport'")
  expect(shell).toContain('readPage={(off,lim)=>adminRead(cfg.operation,{...args,offset:off,limit:lim}).then(d=>({rows:rowsOf(d),total:d?.total}))}')
  expect(shell).toContain("const EXPORT_SCREEN={provider:'providers',course:'courses',campus:'locations',scholarship:'scholarships'}")
  const ctl = fs.readFileSync('src/CsvExport.jsx', 'utf8')
  for (const t of ['Export visible columns', 'Export all columns', 'data-csv-export-mode="visible"', 'data-csv-export-mode="all"', 'Cancel']) expect(ctl).toContain(t)
})
