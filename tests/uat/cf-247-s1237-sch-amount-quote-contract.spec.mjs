// Guards: Platform Admin 26 Nov 2026 15:15 AEDT (Global Autonomous PIM, CA Scholarships: "resolve reusable extraction defects involving monetary values"); F-SCH sch-extract-v3 (every field kept only when its passage is on the bundle)
// s1237: a benefit whose whole quote is a printed amount ("$165.00", "$4,000", "$1,000") is kept when that amount is on the bundle on its own; an amount that is not printed, or only inside a longer number, is still dropped.
import { test, expect } from '@playwright/test'
import { amountQuoteSource, checkScholarshipDetail, quoteSource } from '../../supabase/functions/coverage-sweep/sch-extract.ts'

const PAGE = { id: 'page', text: 'Agnes and Rudy Soucie Scholarship. Value: $165.00. Award amounts - $4,000 for entering students. Fees were $11,650 in 2026. Another award is worth 1,000 CAD.' }
const NAMES = { CA: ['Canada'] }
const empty = { award_code: null, sponsor: null, programme: null, identity_quote: '', award_type: 'not_stated', award_type_quote: '', residency: 'not_stated', residency_quote: '',
  nationality: { eligible: [], excluded: [], regions: [], quote: '' }, course_scope: 'not_stated', course_scope_quote: '', criteria: [], criteria_conjunction: 'not_stated', benefits: [],
  payment_basis: 'not_stated', payment_quote: '', application: { method: 'not_stated', url: null, rolling: null, quote: '' }, duration: { value: null, unit: 'not_stated', renewable: 'not_stated', quote: '' },
  availability: 'unknown', availability_quote: '', summary: '', missing: [] }
const b = (amount, quote) => ({ kind: 'fixed_amount', amount, currency: 'CAD', percentage: null, maximum: false, quote })

test('s1237: a bare printed amount is proven on its own; the old rule still refuses it', () => {
  expect(quoteSource('$165.00', [PAGE])).toBeNull()
  expect(amountQuoteSource('$165.00', [PAGE])).toBe('page')
  expect(amountQuoteSource('$4,000', [PAGE])).toBe('page')
  expect(amountQuoteSource('1,000 CAD', [PAGE])).toBe('page')
})

test('s1237: an amount that is not printed, or sits inside a longer number, is not proven; prose quotes are not touched', () => {
  expect(amountQuoteSource('$1,650', [PAGE])).toBeNull()
  expect(amountQuoteSource('$1,165', [PAGE])).toBeNull()
  expect(amountQuoteSource('$165', [PAGE])).toBeNull() // "$165.00" prints more digits after the point only as cents
  expect(amountQuoteSource('$650', [PAGE])).toBeNull()
  expect(amountQuoteSource('worth $4,000', [PAGE])).toBeNull()
})

test('s1237: checkScholarshipDetail keeps a bare-amount benefit only when printed and the number is in the quote', () => {
  const c = checkScholarshipDetail({ ...empty, benefits: [b(165, '$165.00'), b(4000, '$4,000'), b(9000, '$4,000'), b(7000, '$7,000')] }, [PAGE], NAMES)
  expect(c.benefits.map((x) => x.amount)).toEqual([165, 4000])
})
