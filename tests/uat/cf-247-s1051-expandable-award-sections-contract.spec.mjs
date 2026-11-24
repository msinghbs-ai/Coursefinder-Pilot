// Guards: CF-247 s1051 and s1052 expandable award sections (Platform Admin brief 24 Nov 2026 16:48, S1-Scholarship-Claude): an award named by the toggle of an expandable section (<details><summary>) is an award label,
// a bold label inside such a section ("Type of Award:") is part of that award and never a new one, and the s1037 bold-label and tier splits are unchanged. The fixture follows the live Charles Darwin page's structure.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { execFileSync } from 'node:child_process'

const dir = fs.mkdtempSync('/tmp/s1051-')
const out = `${dir}/b.mjs`
execFileSync('node_modules/.bin/esbuild', ['supabase/functions/coverage-sweep/catalogue.ts', '--bundle', '--format=esm', `--outfile=${out}`, '--log-level=error'])
const { awardSections, sectionHtml } = await import(out)
const ACC = fs.readFileSync('tests/fixtures/scholarship-readers/cdu-international-accordion.html', 'utf8')
const URL_ = 'https://www.cdu.edu.au/international/scholarships'

test('s1051: Charles Darwin: eight awards from the expandable-section toggles, never "Type of Award" or the group headings', () => {
  const on = awardSections(ACC, URL_, { labels: true })
  expect(on.map((a) => a.name)).toEqual([
    "Vice-Chancellor's International High Achievers Scholarships (VCIHAS)", 'CDU Global Merit Scholarship', 'CDU Bachelor of Nursing Scholarship', 'Dili International School Scholarship',
    'CDU International College Scholarship - China and East Asia', 'CDU International College Scholarship - All Regions (excluding China and East Asia)', 'Australia Awards', "Study in Australia's Northern Territory Scholarships",
  ])
  expect(new Set(on.map((a) => a.key)).size).toBe(8)
  expect(on.some((a) => /type of award/i.test(a.name))).toBe(false)
  expect(on[0].value_text).toContain('50%')
  expect(on[0].url).toBeNull()  // its link is an application page
  expect(on[1].group).toBe('CDU Scholarships')
})

test('s1051: an award section keeps its own text and leaves the other awards out; the setting off gives no toggle sections', () => {
  const on = awardSections(ACC, URL_, { labels: true })
  const merit = sectionHtml(ACC, on[1].key, { labels: true })
  expect(merit).toContain('30% tuition fee reduction')
  expect(merit).not.toContain('Nursing')
  expect(awardSections(ACC, URL_).some((a) => /Merit/.test(a.name))).toBe(false)
})

test('s1052: two awards that share one link (a terms page) keep their section keys and no award address', () => {
  const on = awardSections(ACC, URL_, { labels: true })
  expect(on[1].url).toBeNull()
  expect(on[2].url).toBeNull()
  expect(on.map((a) => a.name)).toContain('CDU Global Merit Scholarship')
  expect(on.map((a) => a.name)).toContain('CDU Bachelor of Nursing Scholarship')
  expect(on[7].url).toBe('https://studynt.nt.gov.au/scholarship')
})
