// Guards: S3 P1 zero Firecrawl spend (Platform Admin 22 Nov 2026), G2, G3, G4.
// The existing service spending gate must refuse every purpose when daily_budget_total=0.
// No new infrastructure; the same code path handles normal and on-demand requests.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const sql = readFileSync('supabase/migrations/20261122230000_cf247_s976_firecrawl_hard_zero.sql', 'utf8');
test('s976: single guarded in-place spending gate, even for on-demand', () => {
  assert.match(sql, /pg_get_functiondef\('public\.svc_fc_spend\(numeric,text,uuid,text\)'::regprocedure\)/);
  assert.match(sql, /md5\(v_before\) <> 'fbc83317e0b4c313af9133f4cb9d6a2e'/);
  assert.match(sql, /if security\.fc_setting_num_v1\(''daily_budget_total'', 15000\) = 0 then/);
  assert.match(sql, /v_why := ''budget_zero'';/);
  assert.match(sql, /elsif v_host is not null and security\.third_party_host_v1/);
  assert.match(sql, /IF strpos\(v_before, 'v_why/);
  assert.doesNotMatch(sql, /create table|create index|cron\.schedule|new edge/i);
});
