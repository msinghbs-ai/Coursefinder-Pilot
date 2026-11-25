// Guards: Global Autonomous PIM step 1 (Platform Admin 25 Nov 2026 21:37, 21:39 AEDT): applicability rules across the registered fields; undefined is never confirmed; the existing gap scan skips a not-applicable field; G2, G3, locks, cron.
// s1163: tri-state applicability (true, false, null), the register's status, requires and basis, and the md5-guarded one-condition patch of security.field_gap_scan_v1.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261128020000_cf247_s1163_pim_applicability_hardening_gap_scan.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1163: a new field is undefined until defined; only deadline stays undefined; undefined and unknown are null, never true', () => {
  expect(code).toContain("applicability_status text not null default 'undefined'")
  expect(code).toContain("where field <> 'deadline' and applicability_status <> 'defined'")
  expect(code).toContain("'applicability_undefined'")
  expect(code).toContain("'international_open_unknown'")
  expect(code).toContain("jsonb_build_object('applicable', null,")
  expect(code).toContain("then 'unconfirmed'")
})

test('s1163: english, academic entry and provider tuition require a course open to international students; the rule is register data', () => {
  expect(code).toContain("field in ('english', 'academic_entry', 'provider_tuition') then 'international_open'")
  expect(code).toContain("applicability_requires in ('international_open')")
  expect(code).not.toMatch(/applicability_requires = 'international_open' and c\.oi is true/)
})

test('s1163: the gap scan is patched once, behind its md5 and anchor, and still takes an unconfirmed field', () => {
  expect(code).toContain("'211c4d5a15c5ed9dbc9ce0f7afa5050c'")
  expect(code).toContain('<> 1 then raise exception')
  expect(code).toContain("ab.absence_class = ''not_applicable''")
  expect(code).toContain("cc.open_to_international is false")
  expect(code).not.toContain('open_to_international is null))))')  // an unconfirmed course is not skipped
})

test('s1163: the smoke scan is undone, nothing is dropped, G3 75/48, locks and cron guarded', () => {
  expect(code).toContain("raise exception 's1163_smoke_ok'")
  expect((code.match(/security\.consumer_api_check_v1\(\)/g) || []).length).toBe(2)
  expect(code).not.toMatch(/\b(delete\s+from|truncate|cron\.schedule|drop\s+(table|function|column|constraint))\b/i)
  expect(MIG).toContain('-- Replaces:')
})
