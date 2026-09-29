import { test, expect } from '@playwright/test'
import os from 'node:os'
import path from 'node:path'
import fs from 'node:fs'
import { execFileSync } from 'node:child_process'

async function load() {
  const out = path.join(os.tmpdir(), `sch-${process.pid}.mjs`)
  execFileSync('node_modules/.bin/esbuild', ['supabase/functions/coverage-sweep/scholarship.ts', '--bundle', '--format=esm', `--outfile=${out}`])
  return import(out)
}

test('scholarship facts: value, levels, fields, deadline, main content only', async () => {
  const { scholarshipValue, scholarshipLevels, scholarshipFields, scholarshipDeadline, mainText, scholarshipFaculties, scholarshipFacts } = await load()
  expect(scholarshipValue('The scholarship provides a 25% reduction in tuition fees for the standard duration.')).toMatchObject({ type: 'percentage', percentage: 25 })
  expect(scholarshipValue('Recipients receive 20% off tuition fees each year.')).toMatchObject({ type: 'percentage', percentage: 20 })
  expect(scholarshipValue('This scholarship covers full tuition fees.')).toMatchObject({ type: 'percentage', percentage: 100 })
  expect(scholarshipValue('A one-off award of $10,000 paid in the first year.')).toMatchObject({ type: 'fixed_amount', amount: 10000 })
  expect(scholarshipValue('Tiered: 10% tuition fee reduction, 15% tuition fee reduction or 25% tuition fee reduction')).toMatchObject({ type: 'ambiguous' })
  expect(scholarshipValue('Living costs are about $29,710 a year.')).toBeNull()
  expect(scholarshipLevels('International Excellence Scholarship (Undergraduate)', '')).toEqual(['undergraduate'])
  expect(scholarshipLevels('Merit Scholarship', 'Open to students commencing a postgraduate coursework degree')).toEqual(['postgraduate_coursework'])
  expect(scholarshipLevels('Research Training Program', 'for a PhD or Master by Research')).toEqual(['research'])
  expect(scholarshipFields('Engineering International High Achievers Scholarship')).toEqual(['asced-03'])
  expect(scholarshipFields('Vice-Chancellor International Excellence Scholarship')).toEqual([])
  expect(scholarshipDeadline('Applications close on 31 October 2026 at 11:59pm.')).toMatchObject({ date: '2026-10-31' })
  expect(scholarshipDeadline('Applications close 31 October 2026. Round 2 closing date 15 March 2027')).toMatchObject({ ambiguous: true })
  // v0.2.0: tiers and faculty restrictions
  expect(scholarshipValue('Undergraduate 25% tuition fee reduction. ANU International Achievement Award – South East Asia 25% ANU International Achievement Award - Pacific 50%')).toMatchObject({ type: 'ambiguous' })
  expect(scholarshipFaculties('Offered by the Faculty of Law to international students.')).toMatchObject({ fields: ['asced-0909'], unmapped: false })
  expect(scholarshipFaculties('Offered by the Faculty of Pharmacy and Pharmaceutical Sciences.').fields).toEqual(['asced-06'])
  expect(scholarshipFaculties('Offered by the School of Wizardry.')).toMatchObject({ unmapped: true })
  const law = '<main>' + 'y '.repeat(800) + '<p>Faculty of Law International scholarship. Total scholarship value $10,000 for undergraduate students.</p></main>'
  expect(scholarshipFacts(law, 'Nicholas Auden International Study Scholarship', 'Nicholas Auden International Study Scholarship')).toMatchObject({ fields: ['asced-0909'] })
  // v0.3.0: levels from the eligibility section
  const phd = '<main>' + 'z '.repeat(800) + '<p>Study undergraduate or postgraduate at Monash.</p><p>Who is eligible? Intending to enrol in a graduate research or PhD degree at Monash.</p></main>'
  expect(scholarshipFacts(phd, 'Indonesian Women Impact Scholarship', 'Indonesian Women Impact Scholarship').levels).toEqual(['research'])
  const html = '<html><nav>Undergraduate Postgraduate Research PhD</nav><main>' + 'x '.repeat(900) + '<h1>Merit Award</h1><p>25% tuition fee reduction</p></main><footer>Engineering</footer></html>'
  expect(mainText(html)).not.toContain('PhD')
  expect(mainText(html)).toContain('25% tuition fee reduction')
})

test('Decision 139 international check: domestic-only provider pages are not publishable', async () => {
  const { scholarshipFacts } = await load()
  const dom = '<main>' + 'w '.repeat(800) + '<p>Arts Equity Travel Grant. Eligibility: Australian citizens and permanent residents enrolled in Arts.</p></main>'
  expect(scholarshipFacts(dom, 'Arts Equity Travel Grant', 'Arts Equity Travel Grant').international).toBe(false)
  const intl = '<main>' + 'v '.repeat(800) + '<p>Open to international students commencing an undergraduate degree.</p></main>'
  expect(scholarshipFacts(intl, 'Merit Award', 'Merit Award').international).toBe(true)
  const sql = fs.readFileSync('supabase/migrations/20260929184000_cf247_d139_international_page_check.sql', 'utf8')
  expect(sql).toContain('provider page limits it to citizens and residents')
  expect(sql).toContain('provider page does not mention international students')
  expect(fs.readFileSync('supabase/migrations/20260929180000_cf247_scholarship_sweep.sql', 'utf8')).not.toContain("cron.schedule('scholarship-publish-batch'")
})

test('v0.4.0 scholarship discovery: names, page matching and the reader name check', async () => {
  const { nameTokens, nameOnPage, providerTokens, matchScholarshipPage, keepScholarshipUrl, pageHeadings, slugTokens } = await load()
  expect(nameTokens("Vice-Chancellor's International Scholarships 2026")).toEqual(['vice', 'chancellor', 'international', 'scholarship'])
  expect(nameTokens('Vice-Chancellor&#039;s High Achievers Scholarship')).toEqual(nameTokens("Vice Chancellor's High Achievers Scholarship"))
  const uc = providerTokens(['University of Canberra'])
  // the page must name the scholarship: heading contains the name (a provider prefix may be missing)
  expect(nameOnPage('Scientia Scholarship', ['UNSW Scientia Scholarship | UNSW Sydney']).ok).toBe(true)
  expect(nameOnPage('UC - Southeast Asia Excellence Scholarships', ['Southeast Asia Excellence Scholarship'], uc).ok).toBe(true)
  expect(nameOnPage('Federation Global Merit Scholarship', ['2027 Global Merit Scholarship'], providerTokens(['Federation University Australia'])).ok).toBe(true)
  // a different scholarship, or a generic heading, is a mismatch
  expect(nameOnPage('Academic Scholarship', ['Academic Excellence Scholarship']).ok).toBe(false)
  expect(nameOnPage('International Merit Scholarship', ['International Scholarships', 'Scholarships']).ok).toBe(false)
  // secondary headings (first <h2>s) confirm only with the whole name
  expect(nameOnPage('Global Leaders Scholarship', ['Scholarships'], new Set(), ['Global Leaders Scholarship']).ok).toBe(true)
  expect(nameOnPage('Global Leaders Scholarship', ['Scholarships'], new Set(), ['Leaders Scholarship']).ok).toBe(false)
  const hd = pageHeadings('<html><head><title>Merit Award | Uni</title><meta property="og:title" content="Merit Award"></head><body><svg><title>Home icon</title></svg><h1>Merit Award</h1><h2>Eligibility</h2></body></html>')
  expect(hd.primary).toContain('Merit Award | Uni')
  expect(hd.primary).not.toContain('Home icon')
  // page matching: exact name in the address (reference number dropped) or title; strong matches only
  expect(slugTokens('https://www.monash.edu/x/monash-thailand-award-6307')).toContainEqual(['monash', 'thailand', 'award'])
  expect(matchScholarshipPage('Monash Thailand Award', [{ url: 'https://www.monash.edu/x/monash-thailand-award-6307' }], providerTokens(['Monash University']))).toMatchObject({ basis: 'url_slug' })
  expect(matchScholarshipPage('UC - Southeast Asia Excellence Scholarships', [{ url: 'https://www.canberra.edu.au/scholarships/southeast-asia-excellence-scholarship' }], uc)).toMatchObject({ basis: 'url_slug_without_provider' })
  expect(matchScholarshipPage('Academic Scholarship', [{ url: 'https://school.edu.au/academic-excellence-scholarship' }], new Set())).toBeNull()
  expect(matchScholarshipPage('Regional Scholarship', [{ url: 'https://a.edu.au/s/regional-scholarship' }, { url: 'https://a.edu.au/t/regional-scholarship-2' }], new Set())).toBeNull()
  expect(keepScholarshipUrl('https://scholarships.unsw.edu.au/scientia', 'www.unsw.edu.au')).toBe(true)
  expect(keepScholarshipUrl('https://www.unsw.edu.au/news/2024/scholarship-win', 'www.unsw.edu.au')).toBe(false)
  expect(keepScholarshipUrl('https://www.unsw.edu.au/study/scholarships', 'unsw.edu.au')).toBe(false)
  expect(keepScholarshipUrl('https://www.other.edu.au/scholarships/x', 'unsw.edu.au')).toBe(false)
})

test('v0.4.0 new scholarships: single named page, international, currently offered', async () => {
  const { admissionCheck, currentlyOffered, internationalEligibility } = await load()
  const page = (h1, body, links = '') => `<html><head><title>${h1} | Uni</title></head><body><main><h1>${h1}</h1>${'<p>' + 'Lorem ipsum dolor sit amet. '.repeat(20) + '</p>'}<p>${body}</p>${links}</main></body></html>`
  const ok = admissionCheck(page('Global Excellence Scholarship', 'Open to international students commencing an undergraduate degree in 2027. 20% tuition fee reduction.'), 'https://www.uni.edu.au/scholarships/global-excellence', 'www.uni.edu.au')
  expect(ok).toMatchObject({ admit: true, name: 'Global Excellence Scholarship' })
  expect(admissionCheck(page('Community Scholarship', 'Eligibility: Australian citizens or permanent residents only. $5,000.'), 'https://www.uni.edu.au/s/c', 'www.uni.edu.au').reasons).toContain('domestic_only')
  expect(admissionCheck(page('Scholarships', 'International students welcome.'), 'https://www.uni.edu.au/s', 'www.uni.edu.au').reasons).toContain('no_named_title')
  const many = Array.from({ length: 14 }, (_, i) => `<a href="/scholarships/award-${i}">Award ${i}</a>`).join('')
  expect(admissionCheck(page('International Scholarships and Awards Scholarship', 'For international students.', many), 'https://www.uni.edu.au/scholarships/all', 'www.uni.edu.au').reasons).toContain('listing_page')
  expect(admissionCheck(page('Merit Scholarship', 'For international students.'), 'https://www.elsewhere.com/merit', 'www.uni.edu.au').reasons).toContain('not_provider_domain')
  expect(currentlyOffered('Applications for 2024 closed on 1 March 2024.', new Date('2026-09-29')).reason).toBe('past_year_only')
  expect(currentlyOffered('This scholarship is no longer offered.').reason).toBe('not_offered')
  expect(currentlyOffered('Applications open for 2027 intake.', new Date('2026-09-29')).ok).toBe(true)
  expect(internationalEligibility('International students are not eligible for this award.').explicit).toBe(false)
})

test('v0.4.0 governance: nothing published, guarded replacements, cron list', async () => {
  const sql = fs.readFileSync('supabase/migrations/20260929200000_cf247_scholarship_discovery.sql', 'utf8')
  expect(sql).toContain("'active','unpublished'")
  expect(sql).not.toMatch(/publication_status\s*=\s*'published'/)
  expect(sql).not.toContain('scholarship_publish_batch_v1(')
  expect(sql).not.toMatch(/cron\.schedule\('scholarship-publish/)
  for (const f of ['svc_scholarship_read_next', 'svc_scholarship_read_record', 'scholarship_sweep_apply_v1']) expect(sql).toMatch(new RegExp(`md5\\(prosrc\\)[^;]*${f}[\\s\\S]{0,200}changed since review`))
  expect(sql).toContain("cron.schedule('scholarship-discover','*/10 * * * *'")
  expect(sql).not.toMatch(/website_edge_|zoho|wix-|coverage_admission|layer3/i)
  const idx = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(idx).toContain('const SCH_FC_CAP = 3000')
  expect(idx).toContain('"name_mismatch"')
  expect(idx).toContain('scholarship-sweep-v0.4.0')
})
