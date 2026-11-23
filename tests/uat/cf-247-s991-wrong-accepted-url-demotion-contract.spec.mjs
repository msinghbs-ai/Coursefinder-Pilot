// Guards: Platform Admin 23 Nov 2026 17:50 AEDT (S2-CF s991): known-wrong accepted official course URLs are demoted through the existing governed remediation route, never the manual locks, with counts recorded
// Pure code contract: the s991 migration file.
import { test, expect } from '@playwright/test';
import fs from 'node:fs';

const sql = fs.readFileSync('supabase/migrations/20261123203000_cf247_s991_wrong_accepted_url_demotion.sql', 'utf8');

test('s991: demotion goes through the existing governed remediation function, not new logic', () => {
  expect(sql).toContain('security.binding_remediation_apply_v1(');
  expect(sql).not.toMatch(/update\s+catalogue\.course_links/i);
  expect(sql).not.toMatch(/\b(delete\s+from|drop\s+(table|function))\b/i);
});

test('s991: manual locks, manual bindings and held courses are never candidates, and locks are counted before and after', () => {
  expect(sql).toContain("k.field in ('official_url', 'course_url', 'all')");
  expect(sql).toContain("coalesce(g.basis, '') <> 'manual'");
  expect(sql).toContain('not security.course_held_v1(c.id)');
  expect(sql).toContain('post-check: manual locks changed');
});

test('s991: refused pages and soft 404s are the only candidates, with the four reason classes', () => {
  expect(sql).toContain("x.chk->>'verdict' = 'refuse'");
  for (const c of ['shared_fee_list_page', 'old_handbook_year', 'soft_404', 'wrong_course_level_or_award']) expect(sql).toContain(c);
});

test('s991: G2 and G3 and housekeeping: batch size is a setting, consumer API checked before and after, headers present, nothing else written', () => {
  expect(sql).toContain("security.pipeline_num_v1('remediation.max_batch_courses', 50)");
  expect((sql.match(/security\.consumer_api_check_v1\(\)/g) || []).length).toBeGreaterThanOrEqual(2);
  expect(sql).toMatch(/^-- Replaces: nothing\.$/m);
  expect(sql).toMatch(/^-- Retires: nothing\.$/m);
  expect(sql).toContain('post-check: descriptions changed');
  expect(sql).toContain("'s991_demote_wrong_urls'");
});
