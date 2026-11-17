// Guards: Boost study-load admission (Platform Admin 18 Nov 2026 07:08, decision 2): Qwen3 30B is qualified for the study_load lane only; only study loads verified against their page under prompt boost-study-load-v4 are admitted, through the unchanged promotion, only where a course has none, and the migration fails if any course that held a value changes
// CF-247 S615. Migration 20261118100000_cf247_boost_qualify_qwen3_study_load. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations-archive/20261118100000_cf247_boost_qualify_qwen3_study_load.sql', 'utf8')
const code = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('one qualification: the study_load lane, the pinned Qwen3 30B model, with the decision as its reason', () => {
  expect((code.match(/insert into pipeline\.boost_model_qualifications/g) || []).length).toBe(1)
  expect(code).toContain("values ('study_load', 'openrouter', 'qwen/qwen3-30b-a3b-instruct-2507', null, now(),")
  expect(code).toContain("'Platform Admin decision 18 Nov 2026 07:08 (S2 - BOOST)")
  expect(code).toContain("raise exception 'post-check: the qualifications are not the one row this migration adds'")
})

test('only verified readings under prompt boost-study-load-v4 are settled again, through the unchanged promotion', () => {
  expect(code).toContain("if v <> 'fa4e3a8671577e2674e652fc5012f497' then raise exception")
  expect(code).toMatch(/update pipeline\.boost_inbound_staging set promotion_state = 'staged', promotion_note = null, promoted_at = null\n where lane = 'study_load' and prompt_version = 'boost-study-load-v4' and worker_status = 'verified' and promotion_state = 'shadow'\n\s+and answer->>'study_load' is not null and provider = 'openrouter' and model = 'qwen\/qwen3-30b-a3b-instruct-2507';/)
  expect(code).toContain('perform security.boost_promote_v1(b, false, now());')
  expect(code).not.toMatch(/update catalogue\.courses|insert into catalogue\.|create or replace function|delete from|drop (table|function)|truncate/i)
})

test('post-checks: no course that held a study load changes, nothing else is admitted, every admitted row filled its course once', () => {
  expect(code).toContain('create temp table cf_boost_before on commit drop as')
  expect(code).toContain("raise exception 'post-check: % course(s) that already held a study load were changed', v_changed;")
  expect(code).toContain("raise exception 'post-check: a row not verified under prompt boost-study-load-v4 was admitted';")
  expect(code).toContain("raise exception 'post-check: a course was admitted twice';")
  expect(code).toContain("raise exception 'post-check: % rows admitted but % courses filled from them', v_admitted, v_filled;")
})
