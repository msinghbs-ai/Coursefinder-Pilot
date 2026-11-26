// Guards: SS-Programme-Control 26 Nov 2026 22:27 AEDT (first autonomous AER cycle: a printed minimum age is not a minimum entry score; admitted rows corrected, nothing withdrawn)
// s1284: worker v1.0.53 entryAgeNotScore and the migration use the same words; only kind and score change, locked courses are left alone, one integration issue recorded.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { entryAgeNotScore, courseEntrySliceRows } from '../../supabase/functions/coverage-sweep/course-entry.ts'

const MIG = fs.readFileSync('supabase/migrations/20261130051500_cf247_s1284_aer_age_not_entry_score.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1284: an age is a general note with no score; a real score or a score word is left as read', () => {
  const age = entryAgeNotScore({ kind: 'minimum_grade', min_entry_score: 18, min_entry_score_basis: 'years of age' }, 'Applicants must be 18 years of age or over at the time of application.')
  expect(age.normalised).toBe(true)
  expect(age.row.kind).toBe('general_note')
  expect(age.row.min_entry_score).toBe(null)
  expect(age.row.age_not_score).toEqual({ min_entry_score: 18, rule: 's1284 age is not a score' })
  expect(entryAgeNotScore({ kind: 'minimum_grade', min_entry_score: 70 }, 'A minimum ATAR of 70').normalised).toBe(false)
  expect(entryAgeNotScore({ kind: 'minimum_grade', min_entry_score: 25 }, 'Minimum score of 25 in the selection test, age 18 or over').normalised).toBe(false)
  expect(entryAgeNotScore({ kind: 'general_note', min_entry_score: null }, 'Be at least 18 years old').normalised).toBe(false)
  const page = 'Applicants must be 18 years of age or over at the time of application.'
  const { rows } = courseEntrySliceRows({ rows: [{ kind: 'minimum_grade', audience: 'all', min_entry_score: 18, min_entry_score_basis: 'years of age', quote: page }] }, page)
  expect(rows[0].kind).toBe('general_note')
  expect(rows[0].min_entry_score).toBe(null)
})

test('s1284: the migration applies the same words to active minimum_grade rows, skips locked courses and logs every id', () => {
  expect(code).toContain("e.status = 'active' and e.kind = 'minimum_grade'")
  expect(code).toContain('e.min_entry_score between 14 and 30')
  expect(code).toContain("set kind = 'general_note', min_entry_score = null, min_entry_score_basis = null, updated_at = now()")
  expect(code).toContain("'age_not_score', jsonb_build_object('kind', r.kind")
  expect(code).toContain('not exists (select 1 from pipeline.manual_locks l')
  expect(code).toContain("'ids', (select jsonb_agg(id order by id) from s1284_rows)")
  expect(code.match(/insert into pipeline\.integration_issues/g).length).toBe(1)
})

test('s1284: nothing deleted, withdrawn or dropped; no consumer object, job or setting changed', () => {
  expect(code).not.toMatch(/\bdelete from\b|truncate |set status|cron\.schedule|cron\.alter_job|platform_toolset_settings\s+set|website_v2_/i)
  expect(MIG.split('\n').filter((l) => /^(drop|delete|truncate)\b/i.test(l))).toEqual([])
  for (const s of ['post-check: consumer API moved', 'post-check: a cron job was created', 'post-check: manual locks changed', 'post-check: a corrected row is not']) expect(MIG).toContain(s)
})
