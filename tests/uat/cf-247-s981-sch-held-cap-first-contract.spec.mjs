// Guards: Platform Admin consolidated batch 23 Nov 2026 07:16 and 07:45 AEDT (IQ-00555, IQ-00029: coverage-sweep HTTP 500 from the scholarship listing claim).
// security.fc_sch_held_v1 keeps its rule and answers and tests the per-university cap before the eligibility rule; parity with the replaced definition is checked in the migration.
import { test, expect } from '@playwright/test';
import fs from 'node:fs';

const sql = fs.readFileSync('supabase/migrations/20261123030000_cf247_s981_sch_held_cap_first.sql', 'utf8');

test('s981: in place under the live md5, cap before eligibility, parity checked, covering index only', () => {
  expect(sql).toContain("<> 'f8d6fb4bf9196dfa596b8274819670a6'");
  const body = sql.slice(sql.indexOf('CREATE OR REPLACE FUNCTION security.fc_sch_held_v1('));
  expect(body.indexOf("scholarship_cap_per_uni")).toBeLessThan(body.indexOf('security.fc_sch_eligible_v1(p_provider_id)'));
  expect(body).toContain('return p_discovery and not security.fc_sch_eligible_v1(p_provider_id);');
  expect(sql).toContain("pg_temp.s981_old_held(p.provider_id, m.disc) is distinct from security.fc_sch_held_v1(p.provider_id, m.disc)");
  expect(sql).toContain("include (units) where purpose like ''sch\\_%''");
  expect(sql).not.toMatch(/create table|cron\.schedule|concurrently/i);
});
