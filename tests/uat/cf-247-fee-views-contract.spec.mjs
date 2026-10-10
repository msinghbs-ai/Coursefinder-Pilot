// CF-247 Decision 223 (v2.15.150): course-page fees follow the page's own domestic or international view; course
// totals and part-year fees are not annual fees; re-extraction reads each page in its country's currency; Layer 4
// reviews already answered by the recorded fee are closed; the retired pipeline's fee feed is paused.
import fs from 'node:fs/promises'
import { test, expect } from '@playwright/test'
import { build } from 'esbuild'

async function extractor() {
  const out = await build({ entryPoints: ['supabase/functions/coverage-sweep/extract.ts'], bundle: true, format: 'esm', write: false, platform: 'neutral', logLevel: 'silent' })
  return import('data:text/javascript;base64,' + Buffer.from(out.outputFiles[0].text).toString('base64'))
}

test('reader: view markers, totals and part-year fees', async () => {
  const { fee, viewBefore } = await extractor()
  expect(viewBefore('This content is for domestic students. If you are not a domestic student, please switch from domestic to international content.')).toBe('domestic')
  expect(viewBefore('Fees for overseas students')).toBe('international')
  // QIBT: a domestic-view fee is never an international one
  const qibt = fee('PROGRAM FEES DOMESTIC STUDENTS This content is for domestic students. If you are not a domestic student, please switch from domestic to international content . 2026 TUITION FEES: A$29,950 Non-Tuition fees apply.')
  expect(qibt.value).toBeNull(); expect(qibt.candidates[0].domestic).toBe(true); expect(qibt.candidates[0].international).toBe(false)
  // Collarts: "Local Student Fee Breakdown Switch to International Student"
  expect(fee('Fees & Scholarships Local Student Fee Breakdown Switch to International Student UNIT $3,211.00 TRIMESTER $12,844.00 (full-time study) DIPLOMA $25,688.00 (two trimesters)').candidates.every(c => c.domestic)).toBe(true)
  // AIM: per study period is part of a year; the course total is a total
  const aim = fee('International Indicative Annual Course Fees: Study Period 1: $11,484 Study Period 2: $11,484 Study Period 3: $7,656 Total Indicative Course Fees: $30,624 * Fees provided')
  expect(aim.basis).toBe('total'); expect(aim.candidates.filter(c => c.amount === 11484).every(c => c.partial)).toBe(true)
  // CCMT: "total" belongs to the first amount only
  const ccmt = fee('Estimated Total Course Cost A$20,550 Tuition Fee A$18,000 per year for international students')
  expect(ccmt.value).toBe(18000); expect(ccmt.basis).toBe('annual')
  // UQ: the international view's AUD amount is still chosen
  const uq = fee('Approximate yearly cost of tuition (16 units). $10,520 2026 Fee information for 2027 is not yet available. Fees A$60952 Duration 4 Years Approximate yearly cost of tuition (16 units). AUD $60,952 2027')
  expect(uq.value).toBe(60952)
  // an ordinary page is unchanged
  const plain = fee('International students: annual tuition fee A$42,000 (2026). Domestic students: $9,000 per year.')
  expect(plain.value).toBe(42000); expect(plain.basis).toBe('annual')
})

test('reader v0.5.6: amounts that are not tuition are left out; session and course columns; units', async () => {
  const { fee } = await extractor()
  for (const t of [
    'TAFE fees and charges AUD$5,000 Regional bursary AUD$5,000 WA Regional TAFE International Student Bursary',
    'who can demonstrate circumstances which impact their study; worth up to $5,000 . Andreas Florez Music Equity Scholarship',
    'through a VET Student Loan (VSL) 2026 VET Student Loan cap for Diploma of Business: $12858 2026 VET Student Loan cap for',
    'Single Overseas Student Health Cover $ 550 per Annum Approximately Family Overseas Student Health Cover $ 5000 per Annum',
    'Operations Manager Possible salary approximately A$73,000.00 /year',
    'would not accept payment of more than $1500 from each individual student prior to the commencement',
  ]) expect(fee(t).candidates).toHaveLength(0)
  const uow = fee('International Course fees table Campus Delivery method Session fee* Course fee* Wollongong On Campus $19488 (2026) $116928 (2026) * Session fees are for one session for the year shown.')
  expect(uow.candidates.find(c => c.amount === 19488).partial).toBe(true); expect(uow.candidates.find(c => c.amount === 116928).total).toBe(true)
  expect(fee('Fees International Annual Tuition Fee $21,936 Annual Service Fee $312 Estimated Annual Fee $22,248 Service & Amenity Fees').value).toBe(21936)
  expect(fee('Bachelor of Music International Fees Units x Costs ($AUD) 22 x $3,495 1 x $6,990 Annual Course Fee (Indicative)* (based on 1.0 EFTSL**) $27,960 AUD Plus Student Services').value).toBe(27960)
  expect(fee('International fee Fees are per 48 credit points which represents a standard full-time course load for a year. The fees for 2027 are: General education studies - D60020: A$45,340').value).toBe(45340)
  expect(fee('Fees for overseas students Tuition fee $28,000 Non tuition fee $3,000 (Includes uniform) Estimated total course cost $31,000').candidates.some(c => c.amount === 3000)).toBe(false)
})

test('worker and migrations', async () => {
  const ix = await fs.readFile('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(ix).toMatch(/const VERSION = "coverage-sweep-v0\.5\.[5-9]";/)
  expect(ix).toContain('fee: fee(text, currencyFor(r.country))')
  const a = await fs.readFile('supabase/migrations-archive/20261002182100_cf247_l4_stale_tuition_answered.sql', 'utf8')
  expect(a).toContain("set status = 'superseded'"); expect(a).toContain("(g.candidates->'fee'->>'value')::numeric = f.amount")
  const b = await fs.readFile('supabase/migrations-archive/20261002182200_cf247_old_tuition_feed_paused.sql', 'utf8')
  expect(b).toContain("j.jobname = 'layer3-tuition-enqueue'"); expect(b).toContain('active := false')
  const c = await fs.readFile('supabase/migrations-archive/20261002182300_cf247_reextract_country.sql', 'utf8')
  expect(c).toContain("'a9617910c957420c8c641b75fd0eec21'"); expect(c).toContain("'country',security.coverage_country(cp.provider_id)")
  const d = await fs.readFile('supabase/migrations-archive/20261002182400_cf247_reextract_reviews_first.sql', 'utf8')
  expect(d).toContain("'519ca7d0a304f4004a6300bcf662e668'")
  const e = await fs.readFile('supabase/migrations-archive/20261002182500_cf247_l4_tuition_settle.sql', 'utf8')
  expect(e).toContain("g.candidates->>'extractor' >= 'coverage-sweep-v0.5.6'")
  expect(e).toContain("s.tgt is distinct from s.asked and (s.tgt is not null or not s.intl_any)")
  expect(e).toContain("coalesce(r.claimed_at, '-infinity') < now() - interval '30 minutes'")
  expect(e).toContain("set l3_handoff_at = null, l3_work_item_id = null")
  expect(e).toContain("'layer4-tuition-settle', '3-59/10 * * * *'")
  for (const m of [a, b, c, d, e]) expect(m).not.toMatch(/\bdrop\s|delete\s+from|truncate/i)
})
