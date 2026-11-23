// Guards: Platform Admin 23 Nov 2026 15:39 AEDT (scholarship fire job counts as due only items the picker can take: a stored copy is held or the Firecrawl lane may fetch; ends about 255 empty worker calls an hour).
// The fire job applies the picker's own filters, bounded by what the send loop can use; the function is edited under its md5.
import { test, expect } from '@playwright/test';
import fs from 'node:fs';

const sql = fs.readFileSync('supabase/migrations/20261123160000_cf247_s989_scholarship_fire_counts_takeable_items.sql', 'utf8');

test('s989: fire job edited under its md5 with two fragments, idempotent and post-checked', () => {
  expect(sql).toContain("md5(v_def) <> '51245484e579a0d918b5368497ab0de6'");
  expect(sql).toContain('fragment % of security.scholarship_ai_fire_v1 is found % times');
  expect(sql).toContain("position('s989 (23 Nov 2026' in v_def) > 0");
  expect(sql).toContain('post-check: the s989 edit is not in security.scholarship_ai_fire_v1');
});

test('s989: due uses the picker lane test and stored-copy check, bounded by the send loop', () => {
  expect(sql).toContain("v_paid boolean := security.pipeline_num_v1('lanes.stored_first_on', 1) < 1 or security.lane_paid_hold_v1('sch_scrape') is null;");
  expect(sql).toContain('and (v_paid or security.scholarship_ai_has_copy_v1(q.id))');
  expect(sql).toContain('not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = q.provider_id)');
  expect(sql).toContain('limit greatest(coalesce(v_max, 3), 1) * 8) t;');
  expect(sql).not.toMatch(/create table|cron\.(schedule|unschedule)|platform_toolset_settings/i);
});
