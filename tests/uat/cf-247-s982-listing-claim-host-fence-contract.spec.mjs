// Guards: Platform Admin consolidated batch 23 Nov 2026 07:16 and 07:45 AEDT (IQ-00555, IQ-00029: coverage-sweep HTTP 500 from the scholarship listing claim).
// The listing claim fences the pages of passing providers before the host check, under the live md5; same rule, order, limit and lease.
import { test, expect } from '@playwright/test';
import fs from 'node:fs';

const sql = fs.readFileSync('supabase/migrations/20261123040000_cf247_s982_listing_claim_host_fence.sql', 'utf8');

test('s982: in place under the live md5, host check only after the provider fence', () => {
  expect(sql).toContain("<> '0fd4943e0dce7769320fd51f375ab808'");
  expect(sql).toContain('cand as materialized (');
  expect(sql.indexOf('cand as materialized')).toBeLessThan(sql.indexOf('not security.third_party_host_v1(l.url)'));
  expect(sql).toContain('select l.id from cand join pipeline.scholarship_listing_pages l on l.id = cand.id');
  expect(sql).toContain('for update skip locked');
  expect(sql).toContain("set next_read_at = now() + interval '15 minutes' from pick");
  expect(sql).not.toMatch(/create table|cron\\.schedule|concurrently/i);
});
