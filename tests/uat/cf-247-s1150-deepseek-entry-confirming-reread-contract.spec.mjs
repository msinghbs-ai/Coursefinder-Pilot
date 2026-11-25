// Guards: Platform Admin 25 Nov 2026 14:36 AEDT (Decision 1: one confirming re-read of DeepSeek V4 Flash on the 83 benchmark pages under the live v1.0.44 selector, about US$0.07; qualification criteria unchanged)
// s1150: the existing qualification harness reads the same 83 DeepSeek V4 Flash pages and labels again under a new run label; no route, qualification, job or limit changes.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261126233000_cf247_s1150_deepseek_entry_confirming_reread.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1150: the 83 DeepSeek V4 Flash benchmark pages are copied with their labels into a new run of the existing harness', () => {
  expect(MIG).toContain("v_run constant text := 's1150-entry-qualify-deepseek-v6-2026-11-25'; v_from constant text := 's1125-entry-qualify-2026-11-25';")
  expect(MIG).toContain("v_model constant text := 'deepseek-v4-flash'")
  expect(MIG).toContain("where x.run_label = v_from and x.field = 'entry_requirements' and x.model_code = v_model")
  expect(MIG).toContain("if v_n <> 83 then raise exception")
  expect(MIG).toContain("raise exception 'guard: the s1125 qualification run is not complete'")
})

test('s1150: nothing is switched on, qualified, admitted or scheduled, and nothing is dropped', () => {
  expect(code).not.toMatch(/update pipeline\.ai_service_routes|ai_route_qualifications\s*\(|insert into pipeline\.ai_route_qualifications|platform_toolset_settings|cron\.schedule|cron\.alter_job|layer4_review_items|catalogue\.|\bdelete from\b|truncate /i)
  expect(MIG.split('\n').filter((l) => /^(drop|delete|truncate)\b/i.test(l) || /^alter table .* drop /i.test(l))).toEqual([])
  for (const s of ['post-check: the course entry route changed', 'post-check: the consumer API moved', 'post-check: manual locks changed', 'post-check: the number of active cron jobs changed']) expect(MIG).toContain(s)
})
