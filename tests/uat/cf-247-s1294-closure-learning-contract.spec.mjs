// Guards: Agent Operating Model v1.29 mandatory knowledge capture and design #1271 Phase A (s1294): engineering and human closures and release regressions are harvested once each into non-automatic closure patterns by the existing learning step, and the course-link domestic-path signal is held as knowledge and raised as one owned issue without changing any link.
// CF-247 S1294. supabase/migrations/20261130113000_cf247_s1294_closure_learning_and_link_audience_signal.sql
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const code = fs.readFileSync('supabase/migrations/20261130113000_cf247_s1294_closure_learning_and_link_audience_signal.sql', 'utf8').split('\n').filter(l => !l.trimStart().startsWith('--')).join('\n')

test('closure learning is an anchored, md5-guarded edit of the existing harvest, deduplicated and never automatic', () => {
  expect(code).toContain("md5(pg_get_functiondef('security.ops_learning_harvest_v1()'::regprocedure)) <> '8daa37d0de36cabf94d0fcb73287a373'")
  expect(code).toContain("o.issue_id = x.id and o.remedy_run_id is null and o.evidence->>'closure_event' = x.ev_at::text")
  expect(code).toContain("'closure record (s1294): engineering or human resolution, not an automatic remedy'")
  expect(code).toContain("security.pipeline_num_v1('learn.closure_days', 14)")
})

test('the link audience signal changes no link and goes to its owner', () => {
  expect(code).toContain("'course_link:domestic_page_tagged_international'")
  expect(code).toContain("perform security.integration_issue_upsert_v1(")
  expect(code).not.toMatch(/update catalogue\.course_links|delete\s+from|cron\.schedule\(|create table/i)
})
