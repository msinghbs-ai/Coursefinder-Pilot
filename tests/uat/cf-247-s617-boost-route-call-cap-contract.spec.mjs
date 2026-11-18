// Guards: Boost extraction route caps (Platform Admin 18 Nov 2026 07:08 decision 2 and 17 Nov 2026 22:50): the route boost_extract may make 15,000 calls a day with its US$3 cap unchanged and stays pinned to Qwen3 30B
// CF-247 S617. Migration 20261118101500_cf247_boost_route_call_cap. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const code = fs.readFileSync('supabase/migrations-archive/20261118101500_cf247_boost_route_call_cap.sql', 'utf8').split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('the call cap is raised, the spend cap and the pinned model are not changed', () => {
  expect(code).toContain("update pipeline.ai_service_routes set daily_calls_cap = 15000, prompt_source = 'worker code: boost.ts (boost-study-load-v4)', changed_at = now(),")
  expect(code).not.toMatch(/daily_usd_cap\s*=/)
  expect(code).not.toMatch(/cascade\s*=\s*array/)
  expect(code).toContain("raise exception 'post-check: the route caps are not US$3 and 15,000 calls'")
  expect(code).toContain("raise exception 'post-check: the route is not pinned to qwen3-30b'")
  expect(code).not.toMatch(/create or replace function|delete from|drop (table|function)|truncate|insert into pipeline\.boost_model_qualifications/i)
})
