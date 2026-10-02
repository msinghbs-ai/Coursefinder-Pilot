// Decision 218: fee periods settled by the automatic period check; Live activity names the job behind each worker error
// and an operator can mark an error as seen.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { errorReading } from '../../src/lib/workerErrors.js'

test('migration: period check rules, job, request log, acks, md5 guards', () => {
  const m = fs.readFileSync('supabase/migrations/20261002181600_cf247_fee_period_settle_live_errors.sql', 'utf8')
  for (const g of ['812983b8ec7ea2faaf2eff3f197c6f05', '7967f53602b31a5dedc0a2dbf062bcc4', 'd5f848a2e817aa70e4c3189891d7e7d4', '2dd337996dfc2ca35aa42e058dfee5da', '9a8705ecbc8162af37b3bad6b3ccf8aa']) expect(m).toContain(g)
  expect(m).toContain("if r.q ~* other then v_left := v_left + 1; continue; end if;")
  expect(m).toContain("\\m(first|1st)[- ]year\\M")
  expect(m).toContain("(r.du in ('week', 'weeks') and r.dv <= 52)")
  expect(m).toContain("select cron.schedule('fee-period-settle', '5-59/10 * * * *'")
  expect(m).toContain('grant execute on function public.admin_live_error_ack(text, int, text) to authenticated;')
  expect(m).toContain("and k.message_md5 = md5(e.message) and k.acked_at >= e.last")
})

test('evidence indexing runs four pages at a time; compute-limit replies read plainly', () => {
  const f = fs.readFileSync('supabase/functions/evidence-link-index/index.ts', 'utf8')
  expect(f).toContain('unsupported:0,error:0},C=4;')
  expect(f).toContain('if(text.length>MAX_BYTES*2){')
  expect(errorReading({ status: 546, message: '{"code":"WORKER_RESOURCE_LIMIT"}' })).toContain('ran out of memory or time')
})

test('browser: worker errors show the job and can be marked as seen', async ({ page }) => {
  await mockAdmin(page)
  await page.goto('/#live-activity')
  const errs = page.locator('[data-worker-errors]')
  const row = errs.locator('[data-worker-error="401"]')
  await expect(row).toContainText('Index evidence links')
  await expect(row).toContainText('evidence-link-index')
  await row.locator('[data-error-seen]').click()
  await expect(errs.locator('[data-worker-error="401"]')).toHaveCount(0)
  await expect(errs.locator('[data-worker-error="500"]')).toHaveCount(1)
})

test('platform guide explains Layer 4, the period check and Mark as seen', () => {
  const g = fs.readFileSync('src/guide/platformGuide.js', 'utf8')
  expect(g).toContain('Layer 4 is where decisions that need a person wait')
  expect(g).toContain('automatic period check')
  expect(g).toContain('Mark as seen (Pipeline Operator and above)')
})
