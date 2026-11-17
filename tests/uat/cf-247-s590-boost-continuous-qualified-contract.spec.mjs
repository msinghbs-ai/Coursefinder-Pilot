// Guards: Boost runs continuously and admits (Platform Admin 17 Nov 2026 22:50): the Boost windows are opened to the whole day by their settings, with no function changed; the squash lock (Thu 19 Nov 2026 01:15 to 03:30 Melbourne) still closes both gates and promotion; exactly one model, Qwen3 30B, is qualified, for study_load only; a course that held a study load is never changed and only verified, stated answers are admitted; the jobs hold no number
// CF-247 S590. Migration 20261118002000_cf247_boost_continuous_and_qualify. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261118002000_cf247_boost_continuous_and_qualify.sql', 'utf8')
const code = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('all day is a matter of settings: no function is created or replaced, and the squash lock starts at the freeze', () => {
  expect(code).not.toMatch(/create (or replace )?function/)
  expect(code).toContain("(values ('boost.ingest_window_start_minute', to_jsonb(0)), ('boost.ingest_window_end_minute', to_jsonb(1440)),\n               ('boost.quiet_window_start_hour', to_jsonb(0)), ('boost.quiet_window_end_hour', to_jsonb(24))) v(key, value)")
  expect(code).toContain("update pipeline.platform_toolset_settings set value = to_jsonb(1795011300), updated_at = now(),")
  expect(new Date(1795011300 * 1000).toISOString()).toBe('2026-11-18T14:15:00.000Z')   // Thu 19 Nov 2026 01:15 Melbourne
  expect(code).toContain("raise exception 'post-check: a Boost gate is open inside the squash lock (Thu 01:15 to 03:30)'")
  expect(code).toContain("raise exception 'post-check: promotion ran inside the squash lock'")
  expect(code).toContain("if to_regprocedure('security.boost_on_demand_v1(timestamptz)') is null then raise exception")   // promotion's blackout check is in place first
})

test('exactly one model is qualified, for study load, and it is the route\'s pinned model', () => {
  expect((code.match(/insert into pipeline\.boost_model_qualifications/g) || []).length).toBe(1)
  expect(code).toContain("select 'study_load', 'openrouter', 'qwen/qwen3-30b-a3b-instruct-2507', null, now(),")
  expect(code).toContain("if (select cascade from pipeline.ai_service_routes where service_code = 'boost_extract') is distinct from array['qwen3-30b'] then")
  expect(code).toContain("raise exception 'post-check: the qualification is not exactly Qwen3 30B for study_load'")
})

test('the non-overwrite rule is proven in the change: nothing that held a study load changes, and only verified, stated answers are admitted', () => {
  expect(code).toContain("raise exception 'post-check: a study load that did not come from Boost changed'")
  expect(code).toContain("raise exception 'post-check: % course(s) gained a study load but only % are named by an admitted row'")
  expect(code).toContain("raise exception 'post-check: an unverified or empty answer was admitted'")
  expect(code).toContain("and s.promotion_state = 'shadow' and s.worker_status = 'verified' and s.batch_id like 'bx-%';")
  expect(code).toContain('v := security.boost_promote_v1(b, false, now());')
  expect(code).not.toMatch(/update catalogue\./)   // the catalogue is written only by security.boost_promote_v1
  expect(code.replace(/on commit drop/g, '')).not.toMatch(/\b(drop|delete from|truncate)\b/i)
})

test('throughput is settings, the route\'s own caps and the schedules; the job commands are not rewritten', () => {
  expect(code).toContain("(values ('batch.boost_extract', to_jsonb(40)), ('boost.ingest_files_per_run', to_jsonb(10))) v(key, value)")
  expect(code).toContain("update pipeline.ai_service_routes set daily_usd_cap = 3, daily_calls_cap = 5000, changed_at = now(),")
  expect(code).toContain("select cron.alter_job((select jobid from cron.job where jobname = 'boost-extract'), schedule := '* * * * *');")
  expect(code).toContain("select cron.alter_job((select jobid from cron.job where jobname = 'worker-boost-bulk-ingest'), schedule := '*/2 * * * *');")
  expect(code).not.toMatch(/cron\.schedule\(|command :=/)
  expect(code).toContain("raise exception 'post-check: a Boost job is inactive or holds a number'")
})
