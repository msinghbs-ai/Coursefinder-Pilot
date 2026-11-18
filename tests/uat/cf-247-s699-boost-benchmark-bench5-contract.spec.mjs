// Guards: Boost benchmarks only measure (Platform Admin 17 Nov 2026 22:05 and 22:45; 18 Nov 11:57 Qwen3 30B solo): run bench-5 is started by its label alone on the current reader; it stages, admits and qualifies nothing
// CF-247 S699. Migration 20261118276000_cf247_boost_benchmark_bench5. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const code = fs.readFileSync('supabase/migrations/20261118276000_cf247_boost_benchmark_bench5.sql', 'utf8').split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('bench-5 is started by its label alone and changes no qualification, route or admission', () => {
  expect(code).toContain("update pipeline.platform_toolset_settings set value = to_jsonb('bench-5'::text)")
  expect(code).toContain("where toolset_key = 'pipeline' and key = 'boost.benchmark_label';")
  expect(code).toContain("raise exception 'post-check: the study-load admission qualification changed';")
  expect(code).not.toMatch(/insert into pipeline\.boost_model_qualifications|update pipeline\.boost_model_qualifications|ai_route_qualifications|boost_inbound_staging|catalogue\./)
  expect(code).not.toMatch(/\bdrop\s+(table|function|trigger|schema|index|view)\b|\bdelete\s+from\b|\btruncate\b/i)
})
