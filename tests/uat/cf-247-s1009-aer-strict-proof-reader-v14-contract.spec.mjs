// Guards: Platform Admin 23 Nov 2026 15:52 AEDT, Priority 2 Step 1 (items 1 and 3): strict-proof row rule (international or all applicants, academic kind, value word for word in the quote, no maximum or "up to", no age; also no one-subject mark), 5% audit kept, aer.machine_min_confidence untouched; reader aer-det-v1.4 with a $0 re-read of stored pages
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261123170000_cf247_s1009_aer_strict_proof_reader_v14.sql', 'utf8')
const reader = fs.readFileSync('supabase/functions/coverage-sweep/aer-det-reader.ts', 'utf8')

test('s1009: every edit is md5-guarded and found once; the confidence setting and the consumer API are asserted unchanged', () => {
  for (const m of ['f9fcaed44a848edd9af5c73b0482075d', 'a0937504d0e9106321d2d607f4537e71', '5a7509f942850edd2ed8c5f26679a4af', '0d321c926e9003fc3ac88bc6dc49a650']) expect(sql).toContain(m)
  expect(sql).toContain("post-check: the confidence setting changed")
  expect(sql).toContain('security.consumer_api_check_v1()')
  expect(sql).not.toMatch(/update pipeline\.platform_toolset_settings|aer\.machine_min_confidence', [0-9]/)
  expect(sql).not.toMatch(/create table|cron\.schedule|create or replace function public\./i)
})

test('s1009: the strict-proof pass admits only rows that prove themselves and keeps the audit share for a person', () => {
  expect(sql).toContain("rule = 'aer-course-proof-v1'")
  expect(sql).toContain("x.audience in ('international', 'all') and x.kind in ('minimum_grade', 'prior_qualification', 'subject_prerequisite')")
  expect(sql).toContain("x.quote !~* '(maximum|up to|max\\.)' and x.quote !~* '(minimum age|years of age|years old)'")
  expect(sql).toContain("(in|for) [A-Z][a-z]")
  expect(sql).toContain("continue when p_bucket < p_audit;")
  expect(sql).toContain("not exists (select 1 from catalogue.course_entry_requirements a where a.course_id = i.entity_id and a.status = 'active')")
  expect(sql).toContain("and ma.rule in ('aer-course-partial-v1', 'aer-course-proof-v1')")
})

test('s1009 historical v1.4 contract retained; current v1.5 reader versioned by S3 Admin 1054, earlier held readers do not bypass protection', () => {
  expect(reader).toContain('export const AER_DET_VERSION = "aer-det-v1.4"')
  expect(sql).toContain("v_ext constant text := 'aer-det-v1.4';")
  expect(sql).toContain("r.proposed_value->>'extractor' is distinct from v_ext")
  expect(sql).toContain("<> 'audit_sample'")
  expect(sql).toContain('r.claimed_at is null and r.assigned_to is null')
  expect(fs.readFileSync('scripts/aer-det-read.mjs', 'utf8')).toContain("const V = 'aer-det-v1.4'")
})
