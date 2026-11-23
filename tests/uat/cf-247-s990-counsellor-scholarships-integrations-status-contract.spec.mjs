// Guards: Platform Admin 23 Nov 2026 (v1.1 Counsellor and Admin UI replacement, Phase 1: additive v3 reads for Scholarships and Integrations status; G3 consumer API frozen, G2 page size is a setting).
// Both reads are additive, role-checked, Melbourne-dated and never raise to a screen for a failed health check.
import { test, expect } from '@playwright/test';
import fs from 'node:fs';

const sql = fs.readFileSync('supabase/migrations/20261123180000_cf247_s990_counsellor_scholarships_and_integrations_status_v3.sql', 'utf8');

test('s990: scholarships read is rank 2 or above, published and active only, status on the Melbourne date', () => {
  expect(sql).toContain('create or replace function public.counsellor_scholarships_list(p_args jsonb default');
  expect(sql).toContain("security.current_role_rank(), 0) < 2");
  expect(sql).toContain("(now() at time zone 'Australia/Melbourne')::date");
  expect(sql).toContain("x.publication_status = 'published' and x.lifecycle_status = 'active'");
  for (const s of ['Dates not published', "'Opens'", "'Closed'", "'Open'"]) expect(sql).toContain(s);
});

test('s990: page size is a setting (G2), not a number in the function body', () => {
  expect(sql).toContain("security.pipeline_num_v1('scholarships.counsellor_page_rows', 50)");
  expect(sql).toContain("insert into pipeline.platform_toolset_settings");
});

test('s990: integrations status returns only healthy, degraded or unknown and swallows a failed check', () => {
  expect(sql).toContain('create or replace function public.admin_integrations_status()');
  expect(sql).toContain("then 'healthy' when v_ok is false then 'degraded' else 'unknown'");
  expect(sql).toContain('exception when others then');
});

test('s990: additive only, G3 guarded before and after, grants exclude anon, nothing dropped', () => {
  expect(sql).toContain("(v->>'functions')::int <> 75 or (v->>'relations')::int <> 48");
  expect(sql).toContain('from public, anon');
  expect(sql).toContain('guard: manual locks changed');
  expect(sql).not.toMatch(/\bdrop\s+(table|function|column)|\bdelete\s+from|website_v2_|zoho_v2_|cron\.(schedule|unschedule)/i);
});
