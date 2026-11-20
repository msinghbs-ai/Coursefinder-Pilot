// Guards: CF-247 s904 to s906 (session S1-ELR-Bands-And-Crawl, Platform Admin 21 Nov 2026 09:00 AEDT): IELTS sub-score wording ("band 6.0", "no band less than 6.0", "IELTS band 7") is never an English band scheme; elr-central-v1.2 reads the values a central page gives each named band (rows, columns, headings, lines; decimals kept; one value per band and test) and never makes a band a study-level default; elr-band-v1.0 reports only a course page's named band among the bands its university defines; both readers are pure and the worker band mode is read only
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { centralRead, bandOf, ELR_CENTRAL_VERSION } from '../../supabase/functions/coverage-sweep/elr-central-reader.ts'
import { bandMentions, ELR_BAND_VERSION } from '../../supabase/functions/coverage-sweep/elr-band-reader.ts'

const vals = (defs) => Object.fromEntries(Object.entries(defs).map(([k, v]) => [k, v.map((x) => [x.test_code, x.overall_score])]))

test('s904: IELTS sub-score wording is not a band scheme and names no band', () => {
  expect(ELR_CENTRAL_VERSION).toBe('elr-central-v1.2')
  const r = centralRead(['## Undergraduate', 'IELTS Academic 6.5 overall with no band less than 6.0.', 'Each band 6.0 or above.', 'An IELTS band score of 7 is needed for nursing.',
  ].join('\n'))
  expect(r.bands).toBe(false)
  expect(r.band_defs).toEqual({})
  expect(r.defaults.undergraduate.map((x) => [x.test_code, x.overall_score])).toEqual([['IELTS', 6.5]])
  expect(centralRead('For people around IELTS Band 4 who want to improve exam skills.').bands).toBe(false)
  expect([bandOf('Band 6.5'), bandOf('band 7.0 overall'), bandOf('Level 2 diploma'), bandOf('IELTS band 6')]).toEqual([null, null, null, null])
  expect([bandOf('| Band A |'), bandOf('**English band B**'), bandOf('### English Level 3'), bandOf('Band 2: IELTS 6.5')]).toEqual(['band A', 'band B', 'level 3', 'band 2'])
})

test('s905: band rows, band columns, band headings and band lines give each band its values; decimals kept; never a tier default', () => {
  const rows = centralRead(['English language bands', '| Band | IELTS | TOEFL iBT | PTE |', '|---|---|---|---|', '| Band A | 6.0 | 79 | 50 |', '| Band B | 6.5 | 85 | 58.5 |'].join('\n'))
  expect(vals(rows.band_defs)).toEqual({ 'band A': [['IELTS', 6], ['TOEFL_IBT', 79], ['PTE', 50]], 'band B': [['IELTS', 6.5], ['TOEFL_IBT', 85], ['PTE', 58.5]] })
  expect(rows.defaults).toEqual({})
  expect(rows.bands).toBe(true)
  expect(rows.band_defs['band B'][2].quote).toBe('| Band B | 6.5 | 85 | 58.5 |')
  expect(vals(centralRead(['| Test | Band 1 | Band 2 |', '|---|---|---|', '| IELTS Academic | 6.0 | 7.0 |', '| PTE Academic | 50 | 65 |'].join('\n')).band_defs))
    .toEqual({ 'band 1': [['IELTS', 6], ['PTE', 50]], 'band 2': [['IELTS', 7], ['PTE', 65]] })
  const h = centralRead(['### English Level 3', 'IELTS Academic overall 7.0 with no band below 6.5', 'PTE Academic 65'].join('\n'))
  expect(vals(h.band_defs)).toEqual({ 'level 3': [['IELTS', 7], ['PTE', 65]] })
  expect(h.band_defs['level 3'][0].component_scores).toEqual({ reading: 6.5, writing: 6.5, speaking: 6.5, listening: 6.5 })
  expect(vals(centralRead('Band C: IELTS 7.0 overall, no band less than 6.5; TOEFL iBT 94.').band_defs)).toEqual({ 'band C': [['IELTS', 7], ['TOEFL_IBT', 94]] })
})

test('s905: two values of one test for one band are a conflict and the test is left out of that band', () => {
  const r = centralRead(['Band A: IELTS 6.0 overall.', 'Band A: IELTS 6.5 overall; PTE 50.'].join('\n'))
  expect(vals(r.band_defs)).toEqual({ 'band A': [['PTE', 50]] })
  expect(r.band_conflicts).toEqual([{ band: 'band A', test_code: 'IELTS', values: [6, 6.5] }])
})

test('s906: a course page names a band only among the bands its university defines; IELTS wording is not a band', () => {
  expect(ELR_BAND_VERSION).toBe('elr-band-v1.0')
  const page = ['English language requirements: Band B', 'IELTS band 6.0 or above in each band', '| English language band | C |', 'English band 7.0', 'English level 2'].join('\n')
  expect(bandMentions(page, ['band A', 'band B', 'band C'])).toEqual([{ band: 'band B', quote: 'English language requirements: Band B' }, { band: 'band C', quote: '| English language band | C |' }])
  expect(bandMentions(page, ['level 2']).map((m) => m.band)).toEqual(['level 2'])
  expect(bandMentions('IELTS overall 6.5 (no band less than 6.0)', ['band 6'])).toEqual([])
})

test('the readers are pure; the worker band mode is read only and answers with its version', () => {
  for (const f of ['supabase/functions/coverage-sweep/elr-band-reader.ts', 'supabase/functions/coverage-sweep/elr-central-reader.ts']) {
    expect(fs.readFileSync(f, 'utf8')).not.toMatch(/fetch\(|Deno\.|createClient|openrouter|firecrawl|\.rpc\(|import\(/i)
  }
  const W = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  const at = W.indexOf('if (mode === "elr_band_read") {'), block = W.slice(at, W.indexOf('// CF-247 s907', at))
  expect(at).toBeGreaterThan(0)
  expect(block).not.toMatch(/\brpc\(|\.insert\(|\.update\(|\.upsert\(|fcx\.|useFc|openrouter/i)
  expect(block).toContain('extractor: ELR_BAND_VERSION')
})
