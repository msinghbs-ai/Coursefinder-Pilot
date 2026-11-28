// Guards: SS-Programme-Control 28 Nov 2026 14:18 PC-20261128-AER-ROOT-CAUSE (P0: optional E13 recovery must never roll back the AER cycle; no new scheduler, queue, cap or timeout increase); CLAUDE.md G2 every bound a setting
// CF-247 s1352. supabase/migrations/20261201100000_cf247_s1352_aer_e13_bounded.sql
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261201100000_cf247_s1352_aer_e13_bounded.sql', 'utf8')

test('the expensive rule leaves the candidate query and runs one candidate at a time, bounded by room, scan and time', () => {
  expect(sql).toContain("if md5(d) <> 'dc10a3a8c91f94e9654399a42f1f447e' then raise exception")
  expect(sql).toContain("e2_old text := '         and coalesce((security.aer_recovery_rule_v1(i.id)->>''eligible'')::boolean, false)")
  expect(sql).toContain("continue when not coalesce((security.aer_recovery_rule_v1(r.id)->>''eligible'')::boolean, false);")
  expect(sql).toContain("continue when coalesce((v_seen->>r.provider_id::text)::int, 0) >= v_per;")
  expect(sql).toContain("if clock_timestamp() - v_t0 > v_budget then")
  expect(sql).toContain("if v_cand >= v_scan then")
  expect(sql).toContain("raise exception 'post-check: the rule is still evaluated inside the candidate query'")
})

test('both bounds are settings; no switch, cap, timeout or schedule changes', () => {
  expect(sql).toContain("'aer.e13_time_budget_seconds'")
  expect(sql).toContain("'batch.aer_e13_scan_max'")
  expect(sql).not.toMatch(/statement_timeout|cron\.(schedule|alter_job)|aer\.e13_recover_on'\s*,\s*to_jsonb|e13_recover_daily_max'\s*,\s*to_jsonb/i)
  expect(sql).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})
