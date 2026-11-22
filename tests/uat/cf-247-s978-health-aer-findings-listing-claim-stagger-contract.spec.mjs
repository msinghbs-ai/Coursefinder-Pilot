// Guards: Platform Admin consolidated batch 23 Nov 2026 07:16 and 07:45 AEDT (IR-013 cron stagger, IR-014 Health, IQ-00367, IQ-00555); Decision 276 (correctness fix only).
// The AER assurance check counts rows the partial admission rule admitted (aer-partial-v1, s914); the scholarship listing claim checks each
// provider once; four jobs leave the :19-:23 and :49-:53 windows; stale AER reads with a stored copy go through the existing $0 re-read rule.
// Pure code contract on the migration text.
import { test, expect } from '@playwright/test';
import fs from 'node:fs';

const sql = fs.readFileSync('supabase/migrations/20261123010000_cf247_s978_health_aer_findings_listing_claim_stagger.sql', 'utf8');

test('s978: AER check edit is md5-guarded, one fragment, and recognises the aer-partial-v1 ledger', () => {
  expect(sql).toContain("md5(v_def) <> '9ebdd7d01a89c00edf85d4a54ce5265a'");
  expect(sql).toContain("ma.rule = 'aer-partial-v1' and ma.checks->'admitted_row_ids' ? m.id::text");
  expect(sql).toContain('the edited fragment is not found exactly once');
  expect(sql).toContain("post-check: an active provider-table row is admitted by no person and no rule");
});

test('s978: listing claim replaced in place under its md5, provider checks once per provider, host check bounded', () => {
  expect(sql).toContain("<> '0ce6a0268db2c2b31d6946cd1fe427e1'");
  expect(sql).toContain('prov as materialized');
  expect(sql).toContain('and not security.fc_sch_held_v1(d.provider_id, true)),');
  expect(sql).toContain('ok as materialized');
  expect(sql).toContain("for update skip locked");
  expect(sql).toContain("set next_read_at = now() + interval '15 minutes' from pick");
  expect(sql).toContain('-- fixed: claim lease');
});

test('s978: jobs move only out of the load windows, commands untouched, layer2 snapshot kept byte for byte', () => {
  for (const s of ["'40 * * * *'", "'35 * * * *'", "'3,18,33,48 * * * *'", "'13,28,43,58 * * * *'", "'29,59 * * * *'"]) expect(sql).toContain(s);
  expect(sql).toContain('perform cron.alter_job(v_id, schedule => r.now_s);');
  expect(sql).not.toMatch(/cron\.schedule\(|cron\.unschedule|command\s*=>/);
  expect(sql).not.toMatch(/alter_job\([^)]*layer2-onboarding-snapshot/);
});

test('s978: re-read uses the existing rule and never approves or rejects a Layer 4 item', () => {
  expect(sql).toContain("security.aer_det_reread_v1('apply', v_ids,");
  expect(sql).toContain("post-check: a Layer 4 item was approved or rejected");
  expect(sql).not.toMatch(/set status = '(approved|edited_approved|rejected)'/);
  expect(sql).not.toMatch(/create table|create or replace view/i);
});
