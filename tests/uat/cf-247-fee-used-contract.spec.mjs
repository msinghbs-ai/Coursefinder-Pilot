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

// Rule 2 (8 Oct 2026, Platform Admin): the provider's own course page fee with captured evidence wins over the CRICOS
// registered fee, with no Layer 4 review and whatever year it names. Hand-locked fees keep the earlier rule.
test('migration 0900 applies Rule 2: evidence-backed own-site page fee wins, guarded, writes nothing', () => {
  const m = fs.readFileSync('supabase/migrations/20261008000900_cf247_rule2_page_fee_wins.sql', 'utf8')
  expect(m).toContain("'ae51169df5c347a5fcf5628c6f8e87dd'")
  expect(m).toContain("'10bbafb98bb8edb77579a327499e24db'")
  expect(m).toContain('security.fee_evidence_own_site_v1(pg.evidence_id, p_course_id)')
  expect(m).toContain('(not v_locked and v_ev)')
  expect(m).toContain("where rule = 'unofficial_source'")
  expect(m).not.toContain('layer4_review_items')
  expect(m).not.toMatch(/\b(drop|truncate|cascade)\b/i)
  expect(m).not.toMatch(/delete\s+from/i)
  expect(m).not.toMatch(/insert\s+into/i)
  expect(m).not.toMatch(/\bupdate\s+\S+\s+set\b/i)
  const ad = fs.readFileSync('src/AdaptersWorkspace.jsx', 'utf8')
  expect(ad).toContain('d.kept_no_evidence')
  expect(ad).toContain('d.kept_other_site')
  expect(ad).not.toContain('kept_older_year')
})

// Rule 3 (8 Oct 2026, Platform Admin): a year-less page fee with evidence captured this year is aligned to this year, no review.
test('migration 1000 applies Rule 3: aligns year-less fees captured this year, skips same-year conflicts and hand locks', () => {
  const m = fs.readFileSync('supabase/migrations/20261008001000_cf247_rule3_fee_year_align.sql', 'utf8')
  expect(m).toContain('extract(year from ea.captured_at)::int = v_year')
  expect(m).toContain('where not conflict')
  expect(m).toContain('manual_locks')
  expect(m).toContain("escalation_reason like 'No fee year on record%'")
  expect(m).toContain("cron.schedule('l4-rule-fee-year-align', '27 3 * * *'")
  expect(m).not.toMatch(/\b(drop|truncate|cascade)\b/i)
  expect(m).not.toMatch(/delete\s+from/i)
})

// Rule 3 conflicts (8 Oct 2026, Platform Admin, "Newest evidence wins"): the other fee is superseded, never removed.
test('migration 1100 resolves same-year conflicts by newest evidence and is guarded', () => {
  const m = fs.readFileSync('supabase/migrations/20261008001100_cf247_rule3_newest_evidence_wins.sql', 'utf8')
  expect(m).toContain("'5809297309d14a1a7ce609b6a9d55138'")
  expect(m).toContain('yearless_newer')
  expect(m).toContain("set status = 'superseded'")
  expect(m).toContain('manual_locks')
  expect(m).not.toMatch(/\b(truncate|cascade)\b/i)
  expect(m).not.toMatch(/delete\s+from/i)
  expect(m).not.toMatch(/drop\s+(table|function)/i)
})

// Rule 4 (8 Oct 2026, Platform Admin): low agreement - page wins, admitted automatically daily; never switches a field off.
test('migration 1500 admits low-agreement fields daily, keeps Decision 220 and the hold list, never switches admission off', () => {
  const m = fs.readFileSync('supabase/migrations/20261008001500_cf247_rule4_low_agreement_daily.sql', 'utf8')
  expect(m).toContain('security.adapter_qualify_one_v1(a.provider_id, 0.5, 0.9)')
  expect(m).toContain("(x.v->>'agree_share')::numeric < 0.9")
  expect(m).toContain("not (x.k = 'fee' and v_country = 'CA')")
  expect(m).toContain('pipeline.l4_rule4_holds')
  expect(m).toContain("cron.schedule('l4-rule-low-agreement', '37 3 * * *'")
  expect(m).not.toMatch(/admit\s*=\s*false/i)
  expect(m).not.toMatch(/delete\s+from/i)
  const j = fs.readFileSync('supabase/migrations/20261008001600_cf247_job_layers_rules_retention.sql', 'utf8')
  expect(j).toContain("('l4-rule-low-agreement', 4, now())")
  expect(j).toContain('on conflict (jobname) do nothing')
})
