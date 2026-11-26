// Guards: Atlas brief 26 Nov 2026 15:18 AEDT, Platform Admin authority for S2-Build to wire the s1216 fields into portal/ while S1-API-Frontend-Delivery is busy (s1220): the Course details panel shows the provider website (new tab) and the provider's country-by-country entry matrix (for the student's country when chosen, a count note when capped, Not recorded when empty); Entry Requirements cards show location, length and annual tuition (Not recorded when null); phone layout keeps 44px tap targets.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const read = p => fs.readFileSync(p, 'utf8')
const SRC = 'portal/src'

test('Course details: provider website through ExtLink, Not recorded when missing', () => {
  const p = read(`${SRC}/components/CourseDetails.jsx`)
  expect(p).toMatch(/<ExtLink className="btn" href=\{body\.provider_website\}>Open the provider website<\/ExtLink>/)
  expect(p).toContain('{!body.provider_website && <None what="Provider website: Not recorded" />}')
})

test('Course details: the entry matrix section, narrowed to the student’s country, with a count note and Not recorded', () => {
  const p = read(`${SRC}/components/CourseDetails.jsx`)
  expect(p).toContain('<MatrixSection body={body} market={market} marketName={marketName} />')
  expect(p).toContain('title="Entry requirements by country (provider)"')
  expect(p).toContain('const rows = body.entry_matrix || []')
  expect(p).toContain('const total = Number(body.entry_matrix_total) || rows.length')
  expect(p).toContain('{total > rows.length && <p className="muted small">Showing {rows.length} of {total} rows recorded for this provider.')
  expect(p).toContain('{rows.length === 0 ? <None /> :')
  expect(p).toContain('<ExtLink className="textlink" href={m.url}>Source</ExtLink>')
  expect(p).toContain('(all ? rows : matrixForMarket(rows, market)).map(matrixLine)')
})

test('Entry Requirements cards: location, length (durationText) and annual tuition, Not recorded when null', () => {
  const s = read(`${SRC}/screens/EntryRequirements.jsx`)
  expect(s).toContain('<dl className="er-facts">')
  expect(s).toContain("[c.city, stateShort(c.state_code)].filter(Boolean).join(', ') || NOT_RECORDED")
  expect(s).toContain('durationText(c.duration_value, c.duration_unit)')
  expect(s).toContain('(c.annual_tuition_fee && money(c.annual_tuition_fee.amount, c.annual_tuition_fee.currency)) || NOT_RECORDED')
})

test('phone layout: the facts fold to two columns and panel buttons keep 44px', () => {
  const css = read(`${SRC}/styles.css`)
  const block = css.slice(css.lastIndexOf('/* s1220'))
  expect(block).toMatch(/\.er-facts \{ display:grid; grid-template-columns:repeat\(3,minmax\(0,1fr\)\)/)
  expect(block).toMatch(/@media \(max-width:640px\) \{\s*\.er-facts \{ grid-template-columns:1fr 1fr \}\s*\.details \.actions \.btn \{ min-height:44px \}/)
  expect(block).toContain('overflow-wrap:anywhere')
})

test('the matrix formatting reads recorded values only', async () => {
  const f = await import('../../portal/src/lib/courseDetailFormat.js')
  const m = f.matrixLine({ country_name: 'India', country_code: 'IN', qualification: 'HSC', min_grade: '60% overall', min_value: 60, grade_scale: 'percent', benchmark_band: 'band_b', level_label: 'Diploma', course_label: 'Diploma of Business', for_this_course: true, conditions: { best_n: 4, subject_minimums: [{ subject: 'English', min_grade: '50%' }], alternatives: ['STPM'] }, as_at: '2026-11-20', source_url: 'https://x.example/e' })
  expect(m).toEqual({ country: 'India', countryCode: 'IN', qualification: 'HSC', grade: '60% overall', scale: '', band: 'Band b', level: 'Diploma of Business · Diploma', forCourse: true, conditions: 'Best 4 subjects · Subject minimums: English 50% · Alternatives: STPM', asAt: '2026-11-20', url: 'https://x.example/e' })
  expect(f.matrixLine({ country_code: null, min_value: 2.4, grade_scale: 'gpa_4' })).toMatchObject({ country: 'Every country', grade: '2.4', scale: 'GPA 4', conditions: '' })
  const rows = [{ country_code: null }, { country_code: 'IN' }, { country_code: 'NP' }]
  expect(f.matrixForMarket(rows, '').length).toBe(3)
  expect(f.matrixForMarket(rows, 'IN').map(r => r.country_code)).toEqual([null, 'IN'])
  expect(f.conditionsText(null)).toBe('')
})
