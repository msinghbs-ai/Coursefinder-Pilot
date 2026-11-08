// Guards: F-INT.04 (IQ-00313) the intake evidence view shows only what the server holds; missing fields read "Not held"
import { test, expect } from '@playwright/test'
import { summariseEvidence } from '../../src/intake-evidence-view.js'

test('shows the held fields in a fixed order', () => {
  const rows = summariseEvidence({ page_quote: ' Semester 1 begins in February ', planned: { year: 2027 }, reason: 'calendar', locked: false, actor: 'op1', next_attempt_at: '2026-11-09T00:00:00Z' })
  expect(rows.map(r => r.label)).toEqual(['Source quote', 'Evidence year', 'Reason', 'Locked', 'Decided by', 'Next scheduled attempt'])
  expect(rows.map(r => r.value)).toEqual(['Semester 1 begins in February', '2027', 'calendar', 'false', 'op1', '2026-11-09T00:00:00Z'])
})
test('evidence_year wins over planned year, decided_by over actor', () => {
  const r = summariseEvidence({ evidence_year: 2028, planned: { year: 2027 }, decided_by: 'a', actor: 'b' })
  expect(r[1].value).toBe('2028'); expect(r[4].value).toBe('a')
})
test('missing, empty or non-scalar values read Not held and are never guessed', () => {
  for (const input of [null, undefined, 'x', {}, { page_quote: '  ', reason: {}, locked: null }]) {
    expect(summariseEvidence(input).every(r => r.value === 'Not held' && r.held === false)).toBe(true)
  }
})
