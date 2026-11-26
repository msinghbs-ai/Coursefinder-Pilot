// Guards: SS-Programme-Control 26 Nov 2026 22:27 AEDT (first autonomous AER cycle: a course entry route that accepts an equivalent qualification is not a domestic requirement; admitted rows corrected, nothing withdrawn)
// s1280: worker v1.0.52 entryAudience and the migration use the same words; only the audience changes, locked courses are left alone, two integration issues recorded.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { entryAudience, courseEntrySliceRows } from '../../supabase/functions/coverage-sweep/course-entry.ts'

const MIG = fs.readFileSync('supabase/migrations/20261130031500_cf247_s1280_aer_equivalent_route_audience.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1280: an equivalent route is all; a named domestic route or group stays domestic; other audiences are unchanged', () => {
  expect(entryAudience('domestic', 'Applicants must have successfully completed Australian Year 12 or an equivalent qualification.')).toEqual({ audience: 'all', normalised: true })
  expect(entryAudience('domestic', 'Completed Australian Year 12 or equivalent (or higher)').audience).toBe('all')
  expect(entryAudience('domestic', 'Australian Year 12 (VCE) or equivalent with an ATAR of 70').audience).toBe('domestic')
  expect(entryAudience('domestic', 'Domestic applicants: Year 12 or equivalent').audience).toBe('domestic')
  expect(entryAudience('domestic', 'Australian Year 12 completion').audience).toBe('domestic')
  expect(entryAudience('international', 'Year 12 or equivalent').audience).toBe('international')
  const page = 'Entry Requirements International Students\nHave successfully completed Australian year 12 or equivalent.'
  const { rows } = courseEntrySliceRows({ rows: [{ kind: 'prior_qualification', audience: 'domestic', quote: 'Have successfully completed Australian year 12 or equivalent.' }] }, page)
  expect(rows[0].audience).toBe('all')
  expect(rows[0].audience_normalised).toEqual({ from: 'domestic', rule: 's1280 equivalent route' })
})

test('s1280: the migration applies the same words to active domestic rows only, skips locked courses, logs every id and keeps the earlier audience', () => {
  expect(code).toContain("e.status = 'active' and e.audience = 'domestic'")
  expect(code).toContain("e.quote ~* '\\mor (an |any )?equivalent'")
  expect(code).toContain("VCE|ATAR|VTAC|STAT|QCE|HSC|SACE|WACE|UAC|QTAC|SATAC|TISC|selection rank|school.leaver|domestic|local|citizen|permanent resident")
  expect(code).toContain("set audience = 'all', updated_at = now()")
  expect(code).toContain("'audience_corrected', jsonb_build_object('from', 'domestic'")
  expect(code).toContain('not exists (select 1 from pipeline.manual_locks l')
  expect(code).toContain("'ids', (select jsonb_agg(id order by id) from s1280_rows)")
  expect(code.match(/insert into pipeline\.integration_issues/g).length).toBe(2)
})

test('s1280: nothing deleted, withdrawn or dropped; no consumer object, job or setting changed', () => {
  expect(code).not.toMatch(/\bdelete from\b|truncate |status = 'withdrawn'|set status|cron\.schedule|cron\.alter_job|platform_toolset_settings\s+set|website_v2_/i)
  expect(MIG.split('\n').filter((l) => /^(drop|delete|truncate)\b/i.test(l))).toEqual([])
  for (const s of ['post-check: consumer API moved', 'post-check: a cron job was created', 'post-check: more than 140 active cron jobs', 'post-check: manual locks changed', 'post-check: a reported course still holds']) expect(MIG).toContain(s)
})
