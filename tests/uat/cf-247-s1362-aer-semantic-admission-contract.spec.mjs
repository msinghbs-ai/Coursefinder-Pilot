// Guards: SS-Programme-Control 28 Nov 2026 PC-20261128-CONTINUOUS-BUILD-EXECUTE (S2-AER P0: unsupported audience labels are negative fixtures for the reader; completion-as-entry is s1354)
// s1362 (S2-AER, integrated by S1-Build as worker v1.0.65): Murdoch H1287 (030196A) rows f41b159b (IB 27 labelled international) and d4222382 (completion requirement) as fixtures;
// no identity or admission gate is changed. The completion check of the S2-AER branch is not taken: s1354 entryCompletionRequirement already drops that row.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { entryAudienceSupported, courseEntrySliceRows } from '../../supabase/functions/coverage-sweep/course-entry.ts'

const Q450 = 'All students will undertake at least 450 hours of approved work experience, plus complete a report outlining the experience gained, in order to complete the requirements of the degree'

test('s1362: an audience label the sentence does not support is "all"; named routes keep their label', () => {
  expect(entryAudienceSupported('international', 'International Baccalaureate (IB) Diploma score of 27 or higher').audience).toBe('all')
  expect(entryAudienceSupported('international', 'International students need IELTS 6.5').normalised).toBe(false)
  expect(entryAudienceSupported('international', 'Overseas applicants: IB 27').audience).toBe('international')
  expect(entryAudienceSupported('domestic', 'Selection rank of 80, which can be met by: ATAR of 80 (adjusted or unadjusted)').audience).toBe('domestic')
  expect(entryAudienceSupported('domestic', 'GCE A Levels Aggregate of 7 points').audience).toBe('all')
  expect(entryAudienceSupported('all', 'anything').normalised).toBe(false)
})

test('s1362: through the slice reader the Murdoch rows come out as the page supports, with one completion check (s1354)', () => {
  const page = `${Q450}. International Baccalaureate (IB) Diploma score of 27 or higher. Selection rank of 80, which can be met by: ATAR of 80 (adjusted or unadjusted).`
  const { rows, dropped } = courseEntrySliceRows({ rows: [
    { kind: 'portfolio_interview', audience: 'all', description: Q450, quote: Q450 },
    { kind: 'minimum_grade', audience: 'international', description: 'IB 27', min_entry_score: '27', min_entry_score_basis: 'IB', quote: 'International Baccalaureate (IB) Diploma score of 27 or higher' },
    { kind: 'minimum_grade', audience: 'domestic', description: 'ATAR 80', min_entry_score: '80', min_entry_score_basis: 'ATAR', quote: 'Selection rank of 80, which can be met by: ATAR of 80 (adjusted or unadjusted)' },
  ] }, page)
  expect(rows.map(r => [r.kind, r.audience])).toEqual([['minimum_grade', 'all'], ['minimum_grade', 'domestic']])
  expect(rows[0].audience_normalised).toEqual({ from: 'international', rule: 's1362 audience not on the page' })
  expect(dropped.map(d => d.reason)).toEqual(['completion_requirement'])
  const src = fs.readFileSync('supabase/functions/coverage-sweep/course-entry.ts', 'utf8')
  expect(src).not.toContain('entryCompletionNotEntry')
  expect(fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')).toContain('const WORKER = "coverage-sweep-worker-v1.0.66"')
})
