// Guards: Platform Admin 23 Nov 2026 11:10 AEDT Phase 3 (scholarship value parser in the canonical pipeline; REQ-64 upper figure marked up to; REQ-71 values read from the stored note).
// The hourly publishing job reads the award value from the stored note of a text-only record before its publishability check; locks and every check are kept.
import { test, expect } from '@playwright/test';
import fs from 'node:fs';

const sql = fs.readFileSync('supabase/migrations/20261123060000_cf247_s984_scholarship_value_from_note.sql', 'utf8');

test('s984: md5-guarded one-fragment edit of the publishing job, before its publishability check', () => {
  expect(sql).toContain("<> '971c6011f0cb1c53dc77e1e4d6ce6bb2'");
  expect(sql).toContain('perform security.scholarship_expire_v1();\n  -- s984 (23 Nov 2026, REQ-64/REQ-71)');
  expect(sql).toContain('guard: the fragment is found % times');
});

test('s984: only text-only records with no value and no lock; tiers take the upper figure marked up to', () => {
  expect(sql).toContain("coalesce(s.award_value_type, 'text_only') = 'text_only'");
  expect(sql).toContain("k.field in ('award_value', 'award_value_type', 'award_amount', 'award_percentage', 'all')");
  expect(sql).toContain("max(replace(x[1], ',', '')::numeric)");
  expect(sql).toContain("(m.pct_clause is null and m.tier_clause is not null) or coalesce(m.pct_clause, m.tier_clause, m.amt_clause) ~* 'up to' is_max");
  expect(sql).toContain("v.num > 0 and (v.kind <> 'percentage' or v.num <= 100)");
  expect(sql).toContain("insert into pipeline.scholarship_sweep_changes");
  expect(sql).not.toMatch(/publication_status = 'published'|create table|cron\.schedule|PROBE ONLY/i);
});
