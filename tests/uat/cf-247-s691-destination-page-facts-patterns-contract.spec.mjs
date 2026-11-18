// Guards: destination page facts (Platform Admin 18 Nov 2026 17:55): the Home Affairs living-cost benchmark and the Post-Higher Education Work stream stay are read from the rendered pages with a verbatim quote; a table row keeps its label with its value; patterns are data.
// CF-247 S691. supabase/migrations/20261118224000_cf247_destination_page_facts_patterns.sql, layer1-destination-geo-loader v1.3.1.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { extractFact, htmlToText } from '../../supabase/functions/_shared/cf247-page-facts.js'

const M = fs.readFileSync('supabase/migrations/20261118224000_cf247_destination_page_facts_patterns.sql', 'utf8')
const fund = M.match(/set pattern = '([^']+)'/)[1]
const stay = M.match(/'(bachelor\[\^0-9\][^']+)'/)[1]

test('regression (third live run): a table row keeps its label with its value, and the living-cost amount is read across cells', () => {
  const t = htmlToText('<p>To see the minimum amount go to Gather Documents.</p><h3>12 months living costs</h3><table><tr><th>Applicant</th><th>Amount</th></tr>' +
    '<tr><td>Primary applicant</td><td>AUD29,710</td></tr><tr><td>Partner</td><td>AUD10,394</td></tr></table>')
  expect(t).toContain('Primary applicant | AUD29,710 .')
  const r = extractFact(t, { pattern: fund, kind: 'amount', min: 15000, max: 80000 })
  expect(r).toMatchObject({ found: true, value: 29710, quote: 'Primary applicant | AUD29,710 .' })
  expect(extractFact(htmlToText('<table><tr><td>Partner</td><td>AUD10,394</td></tr></table>'), { pattern: fund, kind: 'amount', min: 15000, max: 80000 }).found).toBe(false)
})

test('the stay is read from the stream page: a bachelor degree row and its years', () => {
  const t = htmlToText('<h2>Length of stay</h2><ul><li>Bachelor degree (including honours): 2 years</li><li>Masters (coursework): 2 years</li><li>Doctoral degree: 3 years</li></ul>')
  expect(extractFact(t, { pattern: stay, kind: 'number', min: 1, max: 6 })).toMatchObject({ found: true, value: 2, quote: 'Bachelor degree (including honours): 2 years .' })
})

test('the migration: data updates only, the overview fact retired not deleted, rendered reads kept', () => {
  expect(M).toContain("set status = 'retired', updated_at = now(),")
  expect(M).toContain("'https://immi.homeaffairs.gov.au/visas/getting-a-visa/visa-listing/temporary-graduate-485/post-higher-education-work',")
  expect(M).toContain("raise exception 'post-check: Home Affairs pages read rendered'")
  expect(M).not.toMatch(/^\s*(delete from|drop |truncate )/im)
})
