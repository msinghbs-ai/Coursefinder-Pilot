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
  const api = fs.readFileSync('supabase/migrations/20261006001780_cf247_fee_used_in_course_apis.sql', 'utf8')
  expect(api).toContain("md5(s) is distinct from r.guard")
  expect(api).toContain('c2e7944d91b06058e7bd7a456540f3c2')
  expect(api).toContain('f82cdc9284081a9b73977cb32b3107f7')
  expect(api).toContain("'fee_used',security.course_fee_used_v1(course_id)")
  expect(api).not.toMatch(/\b(drop|truncate|cascade)\b/i)
  expect(api).not.toMatch(/delete\s+from/i)
})

test('migration 1790 divides CRICOS by the course length only when it is a year or more', () => {
  const m = fs.readFileSync('supabase/migrations/20261006001790_cf247_fee_under_one_year.sql', 'utf8')
  expect(m).toContain('greatest(case c.duration_unit')
  expect(m).toContain('round(cr.amount / greatest(v_yrs, 1), 0)')
  expect(m).not.toMatch(/\b(drop|truncate|cascade)\b/i)
  expect(m).not.toMatch(/delete\s+from/i)
})

test('migration 1800 holds suspected half-year page fees out of the page-wins count and is guarded', () => {
  const m = fs.readFileSync('supabase/migrations/20261006001800_cf247_fee_suspected_half.sql', 'utf8')
  expect(m).toContain('d7233b6b8ea2a5f3687c1e9d238cf322')
  expect(m).toContain("abs(pa / ann - 0.5) < 0.03")
  expect(m).toContain("'suspected_half'")
  expect(m).not.toMatch(/\b(drop|truncate|cascade)\b/i)
  expect(m).not.toMatch(/delete\s+from/i)
  expect(fs.readFileSync('src/AdaptersWorkspace.jsx', 'utf8')).toContain('data-fee-suspected-half')
})
