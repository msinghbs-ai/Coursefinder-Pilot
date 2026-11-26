// Guards: SS-Programme-Control 27 Nov 2026 09:57 AEDT (academic entry classification: an application instruction is not a prior qualification; D9 course_general must not serve it)
// s1293: worker v1.0.54 entryDocumentInstruction and the migration use the same words; only kind changes, a wording that names a qualification level is left as read, locked courses are left alone.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { entryDocumentInstruction, courseEntrySliceRows } from '../../supabase/functions/coverage-sweep/course-entry.ts'

const MIG = fs.readFileSync('supabase/migrations/20261130110000_cf247_s1293_aer_document_instruction_not_requirement.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1293: an application instruction is a general note; a wording that names a level, a grade or a score is left as read', () => {
  const q = 'Certified transcripts of all academic achievements, including secondary school education'
  const a = entryDocumentInstruction({ kind: 'prior_qualification', description: 'Applicants should submit certified transcripts of all academic achievements, including secondary school education', audience: 'all' }, q)
  expect(a.normalised).toBe(true)
  expect(a.row.kind).toBe('general_note')
  expect(a.row.audience).toBe('all')
  expect(a.row.document_instruction).toEqual({ kind: 'prior_qualification', rule: 's1293 application instruction' })
  const b = entryDocumentInstruction({ kind: 'minimum_grade', description: 'Certified copies of three most recent school reports (in English)' }, 'Certified copies of three most recent school reports (in English).')
  expect(b.row.kind).toBe('general_note')
  expect(entryDocumentInstruction({ kind: 'prior_qualification', description: 'Submit a copy of minimum Year 12 or equivalent qualification or AQF Certificate III / IV or higher.' }, 'Submit a copy of minimum Year 12 or equivalent').normalised).toBe(false)
  expect(entryDocumentInstruction({ kind: 'prior_qualification', description: 'Submit other evidence of relevant research qualifications or research experience' }, 'Submit other evidence of relevant research qualifications').normalised).toBe(false)
  expect(entryDocumentInstruction({ kind: 'minimum_grade', min_entry_score: 70, description: 'Submit certified copies; minimum ATAR 70' }, 'Submit certified copies; minimum ATAR 70').normalised).toBe(false)
  expect(entryDocumentInstruction({ kind: 'minimum_grade', min_grade: 'GPA 5.0', description: 'Submit certified copies' }, 'Submit certified copies').normalised).toBe(false)
  expect(entryDocumentInstruction({ kind: 'portfolio_interview', description: 'Submit a portfolio' }, 'Submit a portfolio').normalised).toBe(false)
  const page = 'Applicants should submit certified transcripts of all academic achievements, including secondary school education.'
  const { rows } = courseEntrySliceRows({ rows: [{ kind: 'prior_qualification', audience: 'all', description: page, quote: page }] }, page)
  expect(rows[0].kind).toBe('general_note')
})

test('s1293: the migration applies the same words to active rows, skips locked courses, keeps the earlier kind and logs every id', () => {
  expect(code).toContain("e.status = 'active' and e.kind in ('prior_qualification', 'minimum_grade')")
  expect(code).toContain('e.min_entry_score is null')
  expect(code).toContain("set kind = 'general_note', updated_at = now()")
  expect(code).toContain("'document_instruction', jsonb_build_object('kind', r.kind")
  expect(code).toContain('not exists (select 1 from pipeline.manual_locks l')
  expect(code).toContain("'ids', (select jsonb_agg(id order by id) from s1293_rows)")
  expect(code.match(/insert into pipeline\.integration_issues/g).length).toBe(1)
  expect(code).toContain('certified (copy|copies|transcripts?|documents?)')
  expect(code).toContain('year\\s*(10|11|12)|certificate\\s*(iii|iv|3|4)|diploma|bachelor|degree|aqf|honours|masters?|doctorate|equivalent')
})

test('s1293: nothing deleted, withdrawn or dropped; no consumer object, job or setting changed', () => {
  expect(code).not.toMatch(/\bdelete from\b|truncate |set status|cron\.schedule|cron\.alter_job|platform_toolset_settings\s+set|website_v2_/i)
  expect(MIG.split('\n').filter((l) => /^(drop|delete|truncate)\b/i.test(l))).toEqual([])
  for (const s of ['post-check: consumer API moved', 'post-check: a cron job was created', 'post-check: manual locks changed', 'post-check: a corrected row is not']) expect(MIG).toContain(s)
})
