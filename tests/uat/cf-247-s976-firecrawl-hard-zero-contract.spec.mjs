// Guards: S3 P1 zero Firecrawl spend (Platform Admin 22 Nov 2026); G2, G3, G4.
// The same existing service spend function refuses scheduled and on-demand with daily_budget_total=0.
// Pure code contract; never invokes a production service or costs a vendor credit.
import { test, expect } from '@playwright/test';
import fs from 'node:fs';

const sql = fs.readFileSync('supabase/migrations/20261122230000_cf247_s976_firecrawl_hard_zero.sql', 'utf8');

test('s976: existing spending gate has md5-guarded hard zero before every exempt path', () => {
  expect(sql).toContain("pg_get_functiondef('public.svc_fc_spend(numeric,text,uuid,text)'::regprocedure)");
  expect(sql).toContain("md5(v_before) <> 'fbc83317e0b4c313af9133f4cb9d6a2e'");
  expect(sql).toContain("if security.fc_setting_num_v1(''daily_budget_total'', 15000) = 0 then");
  expect(sql).toContain("v_why := ''budget_zero'';");
  expect(sql).toContain("elsif v_host is not null and security.third_party_host_v1");
  expect(sql).toContain("IF strpos(v_before, 'v_why");
  expect(sql).not.toMatch(/create table|create index|cron\.schedule|new edge/i);
});
