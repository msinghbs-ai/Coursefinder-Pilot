// Guards: F-SCH redesign detail-fill audit (12 Nov 2026 20:05): a nationality is written only from a passage that states nationality, citizenship, residence, origin or students from a country, and no description repeats a placeholder award; unsupported claims stay protected (directive 12 Nov 2026 16:12 §5)
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261113066000_cf247_sch_detail_guards.sql', 'utf8')
const pg = (re) => new RegExp(re.replace(/\\m|\\M/g, '\\b').replace(/''/g, "'"), 'i')
const CUE = pg("(citizen|nationals?\\M|nationality|passport|residen|descent|origin|born in|(students?|applicants?|candidates?|people|those) (from|of)\\M|eligible countr|following countr)")
const NEG = pg("(\\mI am\\M|\\mI''m\\M|awardee|alumn)")
const keeps = (q) => CUE.test(q) && !NEG.test(q)

test('the audit\'s wrong nationality passages are refused; the sampled true ones are kept', () => {
  for (const q of ['China (中国) +86', 'I am Rahman, an Indonesian awardee of the Australia Awards Scholarship',
    'a parent is an alumnus of an RRU program delivered overseas in Bangladesh, China, Hong Kong, Indonesia, Malaysia, or Taiwan',
    'Must have completed Senior Secondary School (Gao San) in China and undertaken the Gaokao']) expect(keeps(q), q).toBe(false)
  for (const q of ['For students from India, Sri Lanka, Bangladesh, Bhutan, Nepal or Pakistan', 'a citizen or permanent resident of Pakistan at the time of your application',
    'Be an International student with Japanese citizenship.', 'This Bursary is only for new international students from Cambodia, Indonesia, Kazakhstan',
    'holds residential status in one of the following Countries or Regions: China (including Taiwan, Hong Kong SAR and Macau SAR) Japan Mongolia']) expect(keeps(q), q).toBe(true)
})

test('migration 20261113066000: md5-guarded, placeholder floor, superseded not deleted, hand-written descriptions untouched', () => {
  expect(m).toContain("'259d6ec98211c8ca2152aae8bc0105fc'")
  expect(m).toContain("and not (s.award_value_type = 'fixed_amount' and s.award_amount < 50)")
  expect(m).toContain("update scholarship.criteria set status = 'superseded'")
  expect(m).toContain("and s.description = sc.after_value->>'text'")
  expect(m).toContain("k.field = 'description'")
  expect(m).not.toMatch(/^\s*delete\b/im)
})
