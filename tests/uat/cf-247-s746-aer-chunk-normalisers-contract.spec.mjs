// Guards: S746 AER chunk normalisers (Platform Admin 19 Nov 2026 05:42 AEDT items 2 and 3, session S2-BOOST-AER; Decision 276): each row chunk and each cell names the qualification its label or column header prints, an international one from the platform's qualification list (IB Diploma, GCE A Levels) and a national one from the alias list passed in (ATAR, Gaokao, CBSE, ISC, STPM, UEC, HKDSE); the minimum each cell prints is parsed with the platform's cell parser; variant twins (Pass and Honours, Standard and Extended) stay separate rows; nothing is inferred that the page does not print.
// CF-247 S746. Module supabase/functions/coverage-sweep/entry-chunks.ts (chunkNationalQualification, cells[].qualification, cells[].minimum).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { entryChunksOfText, chunkNationalQualification } from '../../supabase/functions/coverage-sweep/entry-chunks.ts'

const quals = JSON.parse(fs.readFileSync('tests/fixtures/entry-cells/qualifications.json', 'utf8')).qualifications
const countries = JSON.parse(fs.readFileSync('tests/fixtures/entry-cells/country-refs.json', 'utf8'))
const national = JSON.parse(fs.readFileSync('tests/fixtures/aer-chunks/national-qualifications.json', 'utf8'))
const opt = { qualifications: quals, countries, national }
const T = (header, rows) => entryChunksOfText([header, ...rows].join('\n'), rows.map((r) => `${header}\n${r}`), [], opt).chunks.filter((c) => c.kind === 'table_row')

test('international qualifications come from the platform list; national ones from the alias list; the longest alias wins', () => {
  const r = T('Qualification | Undergraduate minimum', ['International Baccalaureate Diploma | 24 points', 'GCE A Levels | CCD', 'Australian ATAR | 65.00',
    'Gaokao (National College Entrance Examination) | 70%', 'CBSE All India Senior School Certificate | 65%', 'Indian School Certificate (ISC) | 65%',
    'STPM | CGPA 3.0', 'UEC (Unified Examination Certificate) | 5 B grades', 'HKDSE | 18 points'])
  expect(r.map((c) => c.qualification)).toEqual(['IB_DP', 'GCE_A', 'AU_ATAR', 'CN_GAOKAO', 'IN_CBSE', 'IN_ISC', 'MY_STPM', 'MY_UEC', 'HK_HKDSE'])
  expect(r.map((c) => c.country)).toEqual([null, null, 'AU', 'CN', 'IN', 'IN', 'MY', 'MY', 'HK'])
  // a national qualification of the list is named by whole words only: "satar" or "isca" never match
  expect(chunkNationalQualification('Satar region diploma', national)).toBeNull()
  expect(chunkNationalQualification('ISCA certificate', national)).toBeNull()
  // the longest alias decides ("Higher Secondary Certificate" is HSC, not SSC's "Secondary School Certificate")
  expect(chunkNationalQualification('Bangladesh Higher Secondary Certificate', national)?.code).toBe('BD_HSC')
})

test('a cell names the qualification of its column header; the minimum each cell prints is parsed, a range is kept as words with no single value', () => {
  const [r] = T('Level of study | Gao San (Senior Middle 3) | Gaokao | IB Diploma', ['Bachelor | Minimum average of 75% | 70% of the provincial maximum | 26 points'])
  expect(r.cells.map((c) => c.qualification)).toEqual([null, 'CN_GAOSAN', 'CN_GAOKAO', 'IB_DP'])
  expect(r.cells[1].minimum).toMatchObject({ value: 75, scale: 'percentage' })
  expect(r.cells[3].minimum).toMatchObject({ value: 26, scale: 'points' })
  const [x] = T('Country | Requirement', ['Vietnam | GPA of 6.5 to 7.0 overall'])
  expect(x.cells[1].minimum).toMatchObject({ value: null, scale: 'gpa' })
  expect(x.cells[1].minimum.grade).toBe('GPA of 6.5 to 7.0')
})

test('"successful completion of Year 12 or equivalent" is a row like any other: its words kept, no minimum invented', () => {
  const r = T('Country | Requirement', ['Argentina | Successful completion of Bachillerato (Year 12 equivalent)', 'Brazil | Completion of Certificado de Ensino Medio'])
  expect(r.length).toBe(2)
  expect(r.every((c) => c.cells[1].minimum === null)).toBe(true)
  expect(r.map((c) => c.country)).toEqual(['AR', 'BR'])
  expect(r[0].quote).toBe('Argentina | Successful completion of Bachillerato (Year 12 equivalent)')
})

test('variant twins stay separate rows: nothing is merged, nothing carried from a twin', () => {
  const r = T('Program | ATAR', ['Bachelor of Laws | 90.00', 'Bachelor of Laws (Honours) | 95.00', 'Foundation Program (Standard) | 60%', 'Foundation Program (Extended) | 50%'])
  expect(r.length).toBe(4)
  expect(r.map((c) => c.label)).toEqual(['Bachelor of Laws', 'Bachelor of Laws (Honours)', 'Foundation Program (Standard)', 'Foundation Program (Extended)'])
  expect(r.map((c) => c.cells[1].text)).toEqual(['90.00', '95.00', '60%', '50%'])
  expect(new Set(r.map((c) => c.quote)).size).toBe(4)
})
