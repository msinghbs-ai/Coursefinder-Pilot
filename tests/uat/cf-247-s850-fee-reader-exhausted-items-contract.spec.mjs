// Guards: S850 Fee reader (AI) never shows as stuck behind an item that used its three tries (Platform Admin 20 Nov 2026 15:11 AEDT, chat S1-Fees-Intakes): the watchdog counts only claimable items, and an item that used its three tries (still queued, or a third lease that ran out) is settled to failed every minute by the sweep job.
// CF-247 s850. Migration 20261120175000.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { migrationPath } from './support/migration-files.mjs'

const SQL = fs.readFileSync(migrationPath('20261120175000_cf247_s850_fee_reader_exhausted_items_settle.sql'), 'utf8')
const SWEEP = fs.readFileSync(migrationPath('20261120175100_cf247_s851_s852_fid_det_reader_and_sweep.sql'), 'utf8')

test('the watchdog waiting count matches the claim step (attempts < 3) and exhausted counts the rest', () => {
  expect(SQL).toContain("set pending_sql = 'select count(*) from pipeline.fee_reader_queue q where q.attempts < 3 and (q.state = ''queued'' or (q.state = ''leased'' and q.leased_until < now()))'")
  expect(SQL).toContain("exhausted_sql = 'select count(*) from pipeline.fee_reader_queue q where q.state = ''failed'' or (q.attempts >= 3 and q.state in (''queued'', ''leased''))'")
  expect(SQL).toContain("where key = 'fee_reader';")
})

test('an item set back to queued after its third try is settled to failed, with the reason kept; no DDL on the busy queue table', () => {
  expect(SQL).toContain("and (q.state = 'queued' or (q.state = 'leased' and q.leased_until < now()))")
  expect(SQL).toMatch(/where q\.attempts >= 3  -- fixed: three tries/)
  expect(SQL).toContain('gave up after three tries; s850')
  expect(SQL.replace(/--[^\n]*/g, '')).not.toMatch(/\btrigger\b|alter table pipeline\.fee_reader_queue/i)
})

test('an expired third lease is settled with a read_failed finding, every run of the sweep job', () => {
  expect(SQL).toContain("perform security.fee_reader_finding_v1(r.provider_id, r.fact_source_id, 'read_failed'")
  expect(SWEEP).toContain('v_settle := security.fee_reader_queue_settle_v1();')
})

test('the one stuck item found live gets one more try; the change is guarded and checked', () => {
  expect(SQL).toMatch(/set attempts = 0, leased_until = null, priority = greatest\(priority, 1\)[\s\S]*where state = 'queued' and attempts >= 3 and error is null;/)
  expect(SQL).toContain("raise exception 'post-check: an item that used its three tries is still queued'")
  expect(SQL).toContain("if v_ms > 300 then raise exception 'post-check: the fee reader waiting count took % ms (limit 300)'")
  expect(SQL).toContain('security.consumer_api_check_v1()')
  expect(SQL).not.toMatch(/create (or replace )?function public\./i)
})
