// Guards: Global Autonomous PIM F-OPS.21 (Platform Admin 25 Nov 2026 19:52 and 21:37 AEDT): live progress in the existing Data Delivery read, no new dashboard, queue or job; G2, G3, locks, cron ceiling.
// s1162: security.pim_progress_v1 is read only and joins security.data_delivery_v1 as the key pim, with the live definition guarded by md5.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261128010000_cf247_s1162_pim_progress_read.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1162: the progress read carries every F-OPS.21 figure', () => {
  for (const k of ["'applicable'", "'held'", "'backlog'", "'queued'", "'running'", "'review'", "'failed'", "'no_source_found'", "'expired_leases'",
    "'canonical_gain_window'", "'published_gain_window'", "'throughput_per_hour'", "'clearance_hours'", "'oldest_outstanding'", "'source_findings'",
    "'jobs'", "'gap_queue'", "'ai'", "'firecrawl'", "'human_required'", "'leases'", "'drill'"]) expect(code).toContain(k)
  expect(code).toContain("case when coalesce(q.filled_window, 0) > 0 then round(")  // no clearance estimate without measured throughput
})

test('s1162: the window is the existing setting, and an undefined rule is never applicable', () => {
  expect(code).toContain("security.pipeline_num_v1('data_delivery.net_short_hours', 24)")
  expect(code).toContain("r.applicability_rule = 'countries' and not (r.applicability_param->'countries') ? c.cc then false")
  expect(code).toContain("a.absence_class = 'not_applicable' and a.resolved_at is null")
})

test('s1162: only a key is added to data_delivery_v1, after an md5 and anchor guard; service role only', () => {
  expect(code).toContain("'1467a69fc8ea311e589af1c2d3be5e6e'")
  expect(code).toContain("''pim'', security.pim_progress_v1(),")
  expect(code).toContain('<> 1 then raise exception')
  expect(code).toContain('revoke all on function security.pim_progress_v1() from public, anon, authenticated')
})

test('s1162: no job, no write, no drop; G3 75/48, locks and cron guarded', () => {
  expect((code.match(/security\.consumer_api_check_v1\(\)/g) || []).length).toBe(2)
  expect(code).not.toMatch(/\b(insert\s+into|delete\s+from|truncate|cron\.schedule|drop\s+(table|function|column|constraint))\b/i)
  expect(code.replace(/create temp table[^;]*;/gi, '')).not.toMatch(/\bupdate\s+\w+\.\w+\s+set\b/i)
  expect(MIG).toContain('-- Replaces: none. Retires: none.')
})
