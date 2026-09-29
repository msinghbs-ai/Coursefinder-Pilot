import { test, expect } from '@playwright/test'
import os from 'node:os'
import path from 'node:path'
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
  expect(scholarshipFaculties('Offered by the Faculty of Law to international students.')).toMatchObject({ fields: ['asced-09'], unmapped: false })
  expect(scholarshipFaculties('Offered by the Faculty of Pharmacy and Pharmaceutical Sciences.').fields).toEqual(['asced-06'])
  expect(scholarshipFaculties('Offered by the School of Wizardry.')).toMatchObject({ unmapped: true })
  const law = '<main>' + 'y '.repeat(800) + '<p>Faculty of Law International scholarship. Total scholarship value $10,000 for undergraduate students.</p></main>'
  expect(scholarshipFacts(law, 'Nicholas Auden International Study Scholarship', 'Nicholas Auden International Study Scholarship')).toMatchObject({ fields: ['asced-09'] })
  const html = '<html><nav>Undergraduate Postgraduate Research PhD</nav><main>' + 'x '.repeat(900) + '<h1>Merit Award</h1><p>25% tuition fee reduction</p></main><footer>Engineering</footer></html>'
  expect(mainText(html)).not.toContain('PhD')
  expect(mainText(html)).toContain('25% tuition fee reduction')
})
