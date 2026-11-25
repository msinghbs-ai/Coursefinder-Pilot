// Guards: StudySearch Portal lane (Platform Admin 25 Nov 2026 16:44, S1-API-Frontend-Delivery): Scholarships show a value built only from the structured award fields, dates with their precision, and "Not recorded" or "Not published" instead of a guess.
// CF-247 S1146. The free-text value often holds page text, so it is never shown.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { awardValue, dateText, money, NOT_RECORDED, NOT_PUBLISHED } from '../../portal/src/lib/format.js'

const read = (p) => fs.readFileSync(p, 'utf8')

test('the value is built from the structured award fields', () => {
  expect(awardValue({ award_value_type: 'percentage', award_percentage: 10, award_applies_to_fee_type: 'tuition_fee' })).toBe('10% of tuition')
  expect(awardValue({ award_value_type: 'percentage', award_percentage: 20, award_value_is_maximum: true, award_applies_to_fee_type: 'tuition' })).toBe('Up to 20% of tuition')
  expect(awardValue({ award_value_type: 'fixed_amount', award_amount: 3000, award_currency_code: 'AUD' })).toBe('A$3,000')
  expect(awardValue({ award_value_type: 'fixed_amount', award_amount: 5000, award_currency_code: 'NZD', award_applies_to_fee_type: 'tuition_fee' })).toBe('NZ$5,000 towards tuition')
  expect(awardValue({ award_value_type: null })).toBe(NOT_RECORDED)
  expect(awardValue({ award_value_type: 'percentage', award_percentage: null })).toBe(NOT_RECORDED)
  expect(awardValue({ award_value_type: 'fixed_amount', award_amount: 0, award_currency_code: 'AUD' })).toBe(NOT_RECORDED)
  expect(money(null, 'AUD')).toBeNull()
})

test('the free-text value is never shown', () => {
  const screen = read('portal/src/screens/Scholarships.jsx')
  expect(screen).not.toMatch(/award_value_text/)
  expect(screen).toMatch(/awardValue\(s\)/)
})

test('dates keep the precision the provider gave, and a missing date is "Not published"', () => {
  expect(dateText('2026-11-30', 'day')).toBe('30 Nov 2026')
  expect(dateText('2026-11-30', 'month')).toBe('Nov 2026')
  expect(dateText('2026-11-30', 'year')).toBe('2026')
  expect(dateText(null, 'day')).toBeNull()
  const screen = read('portal/src/screens/Scholarships.jsx')
  expect(screen).toMatch(/opens \|\| NOT_PUBLISHED/)
  expect(screen).toMatch(/closes \|\| NOT_PUBLISHED/)
  expect(NOT_PUBLISHED).not.toBe(NOT_RECORDED)
})

test('status pills, intakes and paging come from the server', () => {
  const screen = read('portal/src/screens/Scholarships.jsx')
  expect(screen).toContain("usePagedList('portal_scholarships_v1'")
  for (const w of ['Open now', 'Opens later', 'Closed', 'Dates not published']) expect(screen).toContain(w)
  expect(screen).toMatch(/f\.intakes \|\| \[\]/)
  expect(screen).toMatch(/<ShowMore/)
})
