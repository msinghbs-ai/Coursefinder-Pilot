// Guards: Platform Admin 14 Nov 2026 00:10 item 1 "fix the 8.9s cold-start page selector so it runs well under the 8s DB limit": the AER v2 page selector reads a stored, ranked sample (pipeline.aer_v2_sample) rebuilt by the aer-v2-shadow job, keeps the same courses, lanes and tries rule, and leaves the reader paused
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261114001500_cf247_aer_v2_sample_table.sql', 'utf8')
const fn = (name) => M.slice(M.indexOf(`create or replace function ${name}`), M.indexOf('$function$;', M.indexOf(`create or replace function ${name}`)) + 1)

test('the selector replaces the live definition it was measured on and reads only the stored sample', () => {
  expect(M).toContain("'9e2c10d3cf4c412b05cde408bea8604d'")
  const cand = fn('security.aer_v2_shadow_candidates_v1')
  expect(cand).toContain('from pipeline.aer_v2_sample s')
  expect(cand).toContain('where s.in_sample and not exists (select 1 from done where done.course_id = s.course_id)')
  expect(cand).toContain('order by s.sample_rank')
  // the slow parts of the old per-call build stay out of the worker's call
  expect(cand).not.toContain('aer_labelled_rows_v1')
  expect(cand).not.toContain('aer_eligible_v1')
  expect(cand).not.toContain('layer4_review_items')
  // same columns as before
  expect(cand).toContain('returns table(course_id uuid, provider_id uuid, title text, level text, provider text, provider_country text, url text, evidence_id uuid, content_hash text, storage_path text, priority bigint, sample_rank bigint)')
})

test('the sample keeps the same lanes and order, and is rebuilt by the existing job, not the worker', () => {
  expect(M).toContain("where l.reason_code = 'gate_incomplete'")
  expect(M).toContain('case when exists (select 1 from gi where gi.course_id = pool.course_id) then 0')
  expect(M).toContain('row_number() over (order by (ranked.lane = 3), (ranked.lane > 0), ranked.lane_rank, ranked.lane) sample_rank')
  expect(M).toContain("select pg_temp.edit_n('security.aer_v2_shadow_fire_v1()', 'd5abb3cd4e78834c9406ffa7f8bd26fe'")
  expect(M).toContain("security.pipeline_num_v1('aer.v2_sample_refresh_minutes', 60)")
  expect(M).toContain("'aer.v2_sample_refresh_minutes', 'Entry requirements v2: rebuild the reader sample after'")
  expect(M).not.toMatch(/cron\.schedule/)
})

test('the reader stays paused and nothing is deleted or admitted', () => {
  expect(M).toContain("if security.pipeline_num_v1('aer.v2_shadow_on', 0) <> 0 then raise exception")
  expect(M).not.toMatch(/key\s*=\s*'aer\.v2_shadow_on'/)
  expect(M).not.toMatch(/aer_v2_shadow_results\s+(set|where)/i)
  expect(M).not.toMatch(/^\s*(delete|drop|truncate)\b/im)
  expect(M).not.toMatch(/insert into catalogue\.|course_entry_review_apply_v1/)
  expect(M).toContain('set in_sample = false')
  expect(M).toMatch(/^-- Replaces: /m)
})
