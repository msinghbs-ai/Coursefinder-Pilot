// Guards: page-text copies (Pilot #1252; Platform Admin 18 Nov 2026 14:23): a newer stored copy of a course page is recorded as the next capture version of the course's evidence group, one writer per course, and copies that failed on the duplicate key are retried; nothing is deleted.
// CF-247 S642. supabase/migrations-archive/20261118181000_cf247_page_text_capture_version_fix.sql.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations-archive/20261118181000_cf247_page_text_capture_version_fix.sql', 'utf8')

test('the text copy takes the next capture version of its course group under a per-course lock', () => {
  expect(M).toContain("(select coalesce(max(t2.capture_version), 0) + 1 from pipeline.evidence_artifacts t2 where t2.evidence_group_key = 'coverage:' || x.course_id), 'coverage:' || x.course_id)")
  expect(M).toContain("perform pg_advisory_xact_lock(hashtext('coverage:' || x.course_id));  -- fixed: one capture version at a time for a course")
  expect(M).toContain("raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src);")
})

test('the failed copies are made due again and nothing is deleted', () => {
  expect(M).toContain("where outcome = 'failed' and error like '%layer2_evidence_group_capture_version_uq%';")
  expect(M).not.toMatch(/^\s*(delete from|drop |truncate )/im)
})
