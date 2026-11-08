// Guards: Feature Completion contract F-INT.04 (university and course drill-down: canonical vs Website vs Zoho), Course Intake Run & Validate honesty rule (a side not read is never a match); consumer API untouched (G3 guard stays s57).
import { test, expect } from '@playwright/test'
import { compareSide, intakeParity, parityByProvider } from '../../src/intake-parity.js'

const rows = (...y) => y.map(year => ({ year }))

test('equal values match, in any order', () => {
  expect(compareSide([{ year: 2027, start_date: '2027-02-28' }, { year: 2027, start_date: '2027-07-25' }], [{ year: 2027, start_date: '2027-07-25' }, { year: 2027, start_date: '2027-02-28' }]).state).toBe('match')
})
test('different or missing values differ', () => {
  expect(compareSide(rows(2027), rows(2028)).state).toBe('differs')
  expect(compareSide(rows(2027, 2028), rows(2027)).state).toBe('differs')
  expect(compareSide(rows(2027), []).state).toBe('differs')
})
test('null, undefined or an error object is not read, never a match', () => {
  expect(compareSide(rows(2027), null).state).toBe('not_read')
  expect(compareSide(rows(2027), undefined).state).toBe('not_read')
  const z = compareSide(rows(2027), { error: 'Unsupported read-back' })
  expect(z.state).toBe('not_read'); expect(z.note).toContain('error')
  expect(compareSide(null, rows(2027)).state).toBe('not_read')
})
test('rows with nothing comparable cannot be compared', () => {
  expect(compareSide([{ foo: 1 }], [{ foo: 1 }]).state).toBe('cannot_compare')
})
test('0 courses and a course with no readings are handled', () => {
  expect(parityByProvider([])).toEqual([])
  expect(intakeParity({}).website.state).toBe('not_read')
})
test('roll-up counts every course once per side and keeps not-read visible', () => {
  const r = parityByProvider([
    { provider_id: 'a', provider_name: 'Uni A', now: rows(2027), website_intakes: rows(2027), zoho_intakes: { error: 'x' } },
    { provider_id: 'a', provider_name: 'Uni A', now: rows(2027), website_intakes: rows(2028), zoho_intakes: rows(2027) },
    { provider_id: 'b', provider_name: 'Uni B', now: rows(2027) },
  ])
  expect(r).toHaveLength(2)
  const a = r.find(x => x.provider === 'Uni A'), b = r.find(x => x.provider === 'Uni B')
  expect(a.courses).toBe(2); expect(a.website).toMatchObject({ match: 1, differs: 1 }); expect(a.zoho).toMatchObject({ match: 1, not_read: 1 })
  expect(b.website.not_read).toBe(1); expect(b.zoho.not_read).toBe(1)
})
