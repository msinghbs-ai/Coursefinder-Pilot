// Guards: CF-247 s1037 label-and-tier award sections (Platform Admin 24 Nov 2026 13:09 and 13:12, S2-Scholarship-Readers): a listing page whose awards carry no code is split by heading,
// by bold label under a group heading (Charles Darwin) or by tier block (Lincoln); a group is never an award; a page with fewer than two valued awards gives nothing; coded pages are unchanged.
// The fixtures are reconstructions of the live pages' structure (the real pages' stored copies are in Storage, not readable here); the live read-back after deploy is the real check.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { execFileSync } from 'node:child_process'

const dir = fs.mkdtempSync('/tmp/s1037-')
const out = `${dir}/b.mjs`
execFileSync('node_modules/.bin/esbuild', ['supabase/functions/coverage-sweep/catalogue.ts', '--bundle', '--format=esm', `--outfile=${out}`, '--log-level=error'])
const { awardSections, sectionHtml, sectionCode } = await import(out)
const fx = (f) => fs.readFileSync(`tests/fixtures/scholarship-readers/${f}`, 'utf8')
const CDU = fx('cdu-international-scholarships.html')
const LIN = fx('lincoln-international-scholarships.html')
const worker = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const sql = fs.readFileSync('supabase/migrations/20261124160000_cf247_s1037_label_tier_award_sections.sql', 'utf8')
const CDU_URL = 'https://www.cdu.edu.au/international/how-apply/scholarships'
const LIN_URL = 'https://www.lincoln.ac.nz/study/scholarships/international-scholarships'

test('s1037: Charles Darwin: eight awards from bold labels, never the two group headings; the s1035 split is the setting-off fallback', () => {
  const off = awardSections(CDU, CDU_URL)
  expect(off.map((a) => a.name)).toEqual(['CDU Scholarships', 'Australian or Northern Territory Government Scholarships'])  // what the heading split alone gives
  const on = awardSections(CDU, CDU_URL, { labels: true })
  expect(on.map((a) => a.name)).toEqual([
    "Vice-Chancellor's International High Achievers Scholarships (VCIHAS)", 'CDU Global Merit Scholarship', 'CDU Bachelor of Nursing Scholarship', 'Dili International School Scholarship',
    'CDU International College Scholarship - China and East Asia', 'CDU International College Scholarship - All Regions (excluding China and East Asia)', 'Australia Awards', "Study in Australia's Northern Territory Scholarships",
  ])
  for (const a of on) { expect(a.key).toMatch(/^S-[A-Z0-9-]{3,60}$/); expect(a.codes).toEqual([a.key]) }
  expect(new Set(on.map((a) => a.key)).size).toBe(8)
  expect(on[0].url).toBeNull()  // its link is an application page
  expect(on[1].url).toBeNull()  // its link is a terms PDF
  expect(on[6].url).toBe('https://www.cdu.edu.au/international/scholarships/australia-awards')
  expect(on[0].value_text).toContain('50%')
})

test('s1037: a label section keeps its own text and its group, and leaves the other awards out', () => {
  const on = awardSections(CDU, CDU_URL, { labels: true })
  const merit = sectionHtml(CDU, on[1].key, { labels: true })
  expect(merit).toContain('30% tuition fee reduction')
  expect(merit).toContain('<h2>CDU Scholarships</h2>')
  expect(merit).not.toContain('Bachelor of Nursing')
  expect(merit).not.toContain('13,750')
  expect(sectionHtml(CDU, 'S-NO-SUCH-AWARD', { labels: true })).toBeNull()
  expect(sectionHtml(CDU, on[1].key)).toBeNull()  // setting off: only the s1035 heading section is looked for, and it is not an award there
  expect(sectionCode(`${CDU_URL}#award-${on[1].key.toLowerCase()}`)).toBe(on[1].key)
})

test('s1037: Lincoln: the flagship tiers are each an award named for their award and tier; the group "Other Scholarships" is not', () => {
  expect(awardSections(LIN, LIN_URL)).toEqual([])  // the heading split alone finds nothing on this layout
  const on = awardSections(LIN, LIN_URL, { labels: true })
  const names = on.map((a) => a.name)
  expect(names.filter((n) => n.startsWith('International Flagship Scholarships - ')).length).toBe(5)
  expect(names).toContain('International Flagship Scholarships - NZ$5,000 for a Bachelor\'s degree with academic requirements')
  expect(names).toContain('Manaaki New Zealand Scholarships')
  expect(names).toContain('China Scholarship Council (CSC) PhD Scholarships')
  expect(names.some((n) => /^Other Scholarships$|^International Scholarships$/.test(n))).toBe(false)
  const csc = on.find((a) => a.name.startsWith('China Scholarship'))
  expect(csc.url).toBeNull()  // the page's general "View scholarships" link is not this award's page
  const t5 = on.find((a) => a.name.includes('NZ$5,000'))
  const html = sectionHtml(LIN, t5.key, { labels: true })
  expect(html).toContain('NZ$5,000 for a Bachelor')
  expect(html).toContain('Tuition rebate after 12 or more weeks')  // the text ahead of the tiers is shared
  expect(html).not.toContain('NZ$3,000')
})

test('s1037: fails closed: one award, labels with no value, a list of links and a call to action give nothing', () => {
  const one = '<main><h1>Scholarships</h1><h2>Vice-Chancellor Scholarship</h2><p>Receive 50% of tuition for international students.</p></main>'
  expect(awardSections(one, 'https://u.example/', { labels: true })).toEqual([])
  const novalue = '<main><h2>Group</h2><p><strong>First Scholarship</strong></p><p>Open to students.</p><p><strong>Second Scholarship</strong></p><p>Open to others.</p></main>'
  expect(awardSections(novalue, 'https://u.example/', { labels: true })).toEqual([])
  const cta = '<main><h2>Group</h2><p><strong>How to apply for a scholarship</strong></p><p>Receive 50% off.</p><p><strong>Apply for a scholarship now</strong></p><p>Receive 30% off.</p></main>'
  expect(awardSections(cta, 'https://u.example/', { labels: true })).toEqual([])
})

test('s1037: a page with award codes is split as before, with the setting on or off', () => {
  const unsw = fs.readFileSync('tests/fixtures/scholarship-recovery/unsw-term1-2027.html', 'utf8')
  const a = awardSections(unsw, 'https://www.unsw.edu.au/x'), b = awardSections(unsw, 'https://www.unsw.edu.au/x', { labels: true })
  expect(a.length).toBeGreaterThanOrEqual(2)
  expect(b.map((x) => x.key)).toEqual(a.map((x) => x.key))
})

test('s1037: worker v1.0.39 reads the setting; migration registers it, widens the merit wording, reads the two hubs now; G2/G3/locks/cron guarded', () => {
  expect(worker).toContain('const WORKER = "coverage-sweep-worker-v1.0.67";')
  expect(worker).toContain('const labelOpts = { labels: wsNum("scholarship.label_sections_on", 0) > 0 };')
  expect(worker).toContain('awardSections(pg.html, pg.finalUrl || url, labelOpts).length === 0)')
  expect(worker).toContain('for (const a of awardSections(pg.html, base, labelOpts)) items.set(')
  expect(worker).toContain('const sec = sectionHtml(pg.html, code, { labels: wsNum("scholarship.label_sections_on", 0) > 0 });')
  expect(sql).toContain("'scholarship.label_sections_on'")
  expect(sql).toContain("array['Global Merit', 'High Achiever', 'Flagship']")
  expect(sql).toContain("'6f5cb7f7-7c70-4c06-970f-f368c3a786e2', '248374d1-0629-41cd-a6f4-0804c422a4ff'")
  expect(sql).toContain("(v->>'functions')::int <> 75 or (v->>'relations')::int <> 48")
  expect(sql).toContain('post-check: manual locks changed')
  expect(sql).toContain('post-check: active cron jobs changed')
  expect(sql.split('\n').filter((l) => !l.startsWith('--')).join('\n')).not.toMatch(/create table|cron\.(schedule|unschedule)|daily_budget_total|delete from|drop (table|function|column|index|schema|view|trigger)/i)
})

// s1333 (28 Nov 2026, S2-Build): a label naming a field of an award is part of that award. UQ College's hub (live read 28 Nov 2026 08:22 AEDT, listing 2412)
// gave 14 "awards" named by the rows of its "Scholarship value" fee tables; the reconstruction below keeps that structure.
test('s1333: "Scholarship value" and other award field labels are never awards; their fee-table rows are not tiers', () => {
  const row = (w, a, b, c) => `<tr><td>${w}</td><td>$${a}</td><td>$${b}</td><td>$${c}</td></tr>`
  const UQC = `<main><h1>UQ College scholarships</h1><p>Scholarships for international students.</p>
    <h2>Bridging English – UQ English Language Scholarship</h2><h3>UQ English Language Scholarship</h3><p>The scholarship covers up to 20 weeks of Bridging English, a 25% tuition fee reduction.</p>
    <h2>Integrated English – Scholarship 2026</h2><h3>Integrated English Scholarship</h3><p>Scholarship recipients will receive a 30% reduction in tuition fees and will have their enrolment fee waived.</p>
    <p><strong>Scholarship value</strong></p><table><tr><th>Weeks</th><th>Total fees (before scholarship)</th><th>Total fees (after scholarship)</th><th>Scholarship value</th></tr>
    ${row(15, '8,585.00', '5,985.00', '2,600.00')}${row(20, '11,360.00', '7,980.00', '3,380.00')}${row(25, '14,135.00', '9,975.00', '4,160.00')}</table>
    <p><strong>Scholarship eligibility</strong></p><p>Hold a passport from an eligible country.</p></main>`
  const on = awardSections(UQC, 'https://uqcollege.uq.edu.au/apply/scholarships', { labels: true })
  expect(on.map((a) => a.name)).toEqual(['UQ English Language Scholarship', 'Integrated English Scholarship'])
  expect(on.some((a) => /Scholarship value|\$\d/.test(a.name))).toBe(false)
  expect(on[1].body.join(' ')).toContain('8,585.00')  // the fee table stays in the award it belongs to
  expect(on[1].body.join(' ')).toContain('passport')
})
