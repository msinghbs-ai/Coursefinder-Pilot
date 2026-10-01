// Decision 215: the evidence link job signs in with one-time run passes, reads compressed saved pages, and Live activity
// lists worker error replies (a scheduled run "succeeds" even when the worker refuses the work).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { errorReading } from '../../src/lib/workerErrors.js'

test('evidence link worker: run-pass sign-in, compressed pages, schedule and live activity read', async () => {
  const fn = fs.readFileSync('supabase/functions/evidence-link-index/index.ts', 'utf8')
  expect(fn).toContain('svc_pilot_consume_nonce')
  expect(fn).toContain('x-cf-run-nonce')
  expect(fn).toContain('DecompressionStream("gzip")')
  const n = fs.readFileSync('supabase/migrations/20261002180900_cf247_evidence_link_index_nonce.sql', 'utf8')
  expect(n).toContain("svc_pilot_submit_nonce('evidence-link-index'")
  const g = fs.readFileSync('supabase/migrations/20261002181000_cf247_evidence_link_index_gzip.sql', 'utf8')
  expect(g).toContain('.html.gz')
  const w = fs.readFileSync('supabase/migrations/20261002181100_cf247_live_activity_worker_errors.sql', 'utf8')
  expect(w).toContain("if v is distinct from '3ec199b1a612fd5c6c968ba6479de96f' then raise exception")
  expect(w).toContain("'worker_errors'")
  expect(w).toContain("union all select ''evidence-link-index'', ''pages''")
})

test('plain-English reading of worker errors', () => {
  expect(errorReading({ status: 401, message: '{"error":"invalid_pilot_automation_key"}' })).toContain('old automation key')
  expect(errorReading({ status: null, timed_out: true })).toContain('did not reply in time')
  expect(errorReading({ status: 500, message: 'firecrawl exception' })).toContain('Firecrawl')
  expect(errorReading({ status: 429, message: '' })).toContain('slow down')
})

test('browser: Live activity lists worker error replies', async ({ page }) => {
  await mockAdmin(page)
  await page.goto('/#live-activity')
  const la = page.locator('[data-live-activity]')
  const errs = la.locator('[data-worker-errors]')
  await expect(errs).toContainText('Workers sending back errors')
  await expect(errs.locator('[data-worker-error="401"]')).toContainText('Error 401')
  await expect(errs.locator('[data-worker-error="401"]')).toContainText('old automation key')
  await expect(errs.locator('[data-worker-error="401"]')).toContainText('36')
  await expect(la).toContainText('37 worker error replies')
})

test('platform guide covers worker errors and evidence link indexing', () => {
  const g = fs.readFileSync('src/guide/platformGuide.js', 'utf8')
  expect(g).toContain('Workers sending back errors')
  expect(g).toContain('Index evidence links')
  expect(g).toContain('one-time run pass')
})
