import { test, expect } from '@playwright/test'
import fs from 'node:fs'

// Decision 255 (6 Oct 2026): a read-only dry run and a "fee used" label. Neither changes a stored fee.
test('fee rules: dry-run report and fee-used label are read only, guarded and rule-shaped', () => {
  const dry = fs.readFileSync('supabase/migrations/20261006001760_cf247_fee_rules_dry_run.sql', 'utf8')
  const used = fs.readFileSync('supabase/migrations/20261006001770_cf247_fee_used_label.sql', 'utf8')
  for (const m of [dry, used]) {
    expect(m).not.toMatch(/\b(drop|truncate|cascade)\b/i)
    expect(m).not.toMatch(/delete\s+from/i)
    expect(m).not.toMatch(/\bupdate\s+\S+\s+set\b/i)
    expect(m).not.toMatch(/insert\s+into/i)
  }
  expect(dry).toContain('Operator or above required')
  expect(dry).toContain("'registered_total_course'")
  expect(dry).toContain('manual_locks')
  expect(used).toContain("md5(s) is distinct from 'a9edf2b34508931f9eea1df7c8ed6dfc'")
  expect(used).toContain('fee_year >= v_year')
  expect(used).toContain('revoke all on function security.course_fee_used_v1(uuid) from public, anon, authenticated')
  const ui = fs.readFileSync('src/CourseDetailPolish.jsx', 'utf8')
  expect(ui).toContain('<FeeUsed u={f.fee_used}/>')
  const ad = fs.readFileSync('src/AdaptersWorkspace.jsx', 'utf8')
  expect(ad).toContain("supabase.rpc('admin_fee_rules_report'")
})
