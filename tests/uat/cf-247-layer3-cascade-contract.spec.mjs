import { test, expect } from '@playwright/test'
import os from 'node:os'
import path from 'node:path'
import fs from 'node:fs'
import { execFileSync } from 'node:child_process'

async function load() {
  const out = path.join(os.tmpdir(), `casc-${process.pid}.mjs`)
  execFileSync('node_modules/.bin/esbuild', ['supabase/functions/_shared/cf247-cascade.ts', '--bundle', '--format=esm', `--outfile=${out}`])
  return import(out)
}

test('cascade escalation signal and audit comparison', async () => {
  const { cascadeSignal, sameAnswer, AUDIT_RATE } = await load()
  expect(cascadeSignal('intake', 'Intakes: February and July each year.')).toBe(true)
  expect(cascadeSignal('intake', 'Start date March 2027')).toBe(true)
  expect(cascadeSignal('intake', 'Contact us in May about accommodation.')).toBe(false)
  expect(cascadeSignal('english', 'IELTS Academic overall 6.5 (no band below 6.0)')).toBe(true)
  expect(cascadeSignal('english', 'English language requirements apply.')).toBe(false)
  expect(sameAnswer('intake', { months: [7, 2] }, { months: [2, 7] })).toBe(true)
  expect(sameAnswer('intake', { months: [2] }, { months: [2, 7] })).toBe(false)
  expect(sameAnswer('english', { tests: [{ test: 'IELTS', overall: 6.5 }] }, { tests: [{ test: 'IELTS', overall: '6.5', min_band: 6 }] })).toBe(true)
  expect(AUDIT_RATE).toBe(0.05)
})

test('ladder migration enforces the tier rule and keeps admission guarded', async () => {
  const sql = fs.readFileSync('supabase/migrations/20260930021000_cf247_l3_cascade_ladder_activate.sql', 'utf8')
  expect(sql).toContain("v_ok::numeric/v_n<0.80 or v_wrong>0")
  expect(sql).toContain('cfb6b617dafeba2ac8ba1301e3c6ec96')
  expect(sql).toContain('layer3_fact_complete_ladder_service')
  expect(sql).toContain("v_disagree>=3 and not v_tier.is_final")
  const fn = fs.readFileSync('supabase/functions/layer3-model-routing/index.ts', 'utf8')
  expect(fn).toContain('layer3_cascade_ladder_service')
  expect(fn).toContain('not_stated_with_signal')
  expect(fn).toContain('audit_disagreement')
  expect(fn).toContain('layer3_fact_release_service')
  expect(fs.readFileSync('supabase/migrations/20260930023000_cf247_l3_key_limit_pause_cleanup.sql', 'utf8')).toContain('budgets:openrouter_refusing')
  expect(fs.readFileSync('supabase/migrations/20260930024000_cf247_l3_release_on_refusal.sql', 'utf8')).toContain('layer3_fact_release_service')
  expect(fs.readFileSync('supabase/functions/_shared/cf247-model-routing.ts', 'utf8')).toContain('export const ROUTING_VERSION = "cf247-l3-model-routing-v1.0.0"')
})
