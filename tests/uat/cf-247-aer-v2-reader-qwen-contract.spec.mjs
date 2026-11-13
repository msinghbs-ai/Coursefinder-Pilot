// Guards: Platform Admin 13 Nov 2026 22:52 "Then build reader" and 23:05 model choice: the AER v2 reader trial runs prompt aer-v2-course-v2 pinned to Qwen3 30B A3B Instruct 2507, reads the gate_incomplete courses first, stays shadow, and leaves the 19:23 stop of the GPT-4.1 mini readers in place
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261113391500_cf247_aer_v2_reader_qwen.sql', 'utf8')

test('prompt v2 is pinned to the chosen model, with the quote rules the v1 trial failed on', () => {
  expect(M).toContain("'aer-v2-course-v2', 'course_page', t, encode(sha256(convert_to(t, 'UTF8')), 'hex'), 'qwen/qwen3-30b-a3b-instruct-2507', 300, 'trial', 'migration 20261113391500'")
  expect(M).toContain('Copy each quote character for character from ONE place in the page text')
  expect(M).toContain('at most 200 characters')
  expect(M).toContain('When min_grade is filled, give a quote with value min_grade whose text contains min_grade exactly as printed')
  expect(M).toContain("update pipeline.aer_prompt_versions set status = 'retired' where version = 'aer-v2-course-v1'")
})

test('gate_incomplete courses are read first, in one pass inside the statement limit', () => {
  expect(M).toContain("'ab6deb5b306a9c931a4841ce8f0eca73'")
  expect(M).toContain("where l.reason_code = 'gate_incomplete'")
  expect(M).toContain('case when exists (select 1 from gi where gi.course_id = pool.course_id) then 0')
  expect(M).not.toContain('join lateral (select a.reason_code')
})

test('still shadow, and the v1 readers stay stopped', () => {
  expect(M).not.toMatch(/key\s*=\s*'(aer\.schedule_daily_max|aer\.schedule_correction_daily_max|entry\.matrix_enabled|aer\.e13_recover_on)'/)
  expect(M).not.toMatch(/insert into catalogue\.|course_entry_review_apply_v1|layer4_review_items\s*\(/)
  expect(M).not.toMatch(/^\s*(delete|drop|truncate)\b/im)
  expect(M).toMatch(/^-- Replaces: /m)
  expect(M).toMatch(/^-- .*Retires: /m)
})
