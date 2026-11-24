// Guards: CF-247 s1035 heading-based multi-award splitter (Platform Admin 24 Nov 2026 13:08, S2-Scholarship-Readers): a page that prints several awards under
// headings with no codes and no pages of their own is split into one award per heading (key S-<slug>, section address #award-s-<slug>) and fails closed otherwise.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { execFileSync } from 'node:child_process'

const dir = fs.mkdtempSync('/tmp/s1035-')
const out = `${dir}/b.mjs`
execFileSync('node_modules/.bin/esbuild', ['supabase/functions/coverage-sweep/catalogue.ts', '--bundle', '--format=esm', `--outfile=${out}`, '--log-level=error'])
const { awardSections, sectionHtml, sectionCode } = await import(out)
const page = fs.readFileSync('tests/fixtures/scholarship-heading/umbrella.html', 'utf8')

test('splits the umbrella by heading: two awards, no furniture, no linked heading', () => {
  const a = awardSections(page, 'https://www.example.ac.nz/international')
  expect(a.map((x) => x.name)).toEqual(['Flagship International Scholarship', "Vice-Chancellor's Merit Scholarship"])
  expect(a[0].key).toBe('S-FLAGSHIP-INTERNATIONAL-SCHOLARSHIP')
  expect(a.every((x) => x.url === null && x.codes[0] === x.key)).toBe(true)
})
test('section address round-trips and the copy keeps only its own award', () => {
  const code = sectionCode('https://www.example.ac.nz/international#award-s-vice-chancellor-s-merit-scholarship')
  expect(code).toBe('S-VICE-CHANCELLOR-S-MERIT-SCHOLARSHIP')
  const html = sectionHtml(page, code)
  expect(html).toContain('NZ$10,000 per year')
  expect(html).toContain('open to international students')
  expect(html).not.toContain('50%')
  expect(sectionHtml(page, 'S-NO-SUCH-AWARD')).toBeNull()
})
test('fails closed: one heading, thin sections, coded umbrellas keep their own path', () => {
  expect(awardSections('<main><h2>Flagship International Scholarship</h2><p>' + 'A tuition fee reduction of 50% applies. '.repeat(6) + '</p></main>', 'https://x.invalid/')).toEqual([])
  expect(awardSections('<main><h2>Flagship International Scholarship</h2><p>Apply now.</p><h2>Merit Scholarship Award</h2><p>Apply now.</p></main>', 'https://x.invalid/')).toEqual([])
  const coded = '<main><table><tr><td>International Scientia Coursework Scholarship (PUCA1025)</td></tr><tr><td>International Scientia Research Scholarship (PGCA1107)</td></tr></table></main>'
  expect(awardSections(coded, 'https://x.invalid/').map((x) => x.key)).toEqual(['PUCA1025', 'PGCA1107'])
})
