// Guards: F-OPS.03A (Platform Admin P0, 9 Nov 2026 21:28): the Data Delivery summary is one read-only, rank-3 server read behind the existing Operations operation, shown first on Operations, built from the existing lane funnel and catalogue infrastructure, never shows an unknown as zero, and its database behaviour is proved on an isolated fixture.
// Source contract (chromium-desktop; no browser page is used). The central rules are not re-asserted here: G2 is s32, G3 is s57, housekeeping and G1 are s42.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261109210000_cf247_fops03a_data_delivery.sql', 'utf8')
const UI = fs.readFileSync('src/DataDelivery.jsx', 'utf8')
const MAIN = fs.readFileSync('src/mature-main.jsx', 'utf8')
const FX = fs.readFileSync('tests/fixtures/fops03a-data-delivery/fixtures.sql', 'utf8')
const RUN = fs.readFileSync('tests/fixtures/fops03a-data-delivery/run.sh', 'utf8')
const WF = fs.readFileSync('.github/workflows/fops03a-data-delivery-test.yml', 'utf8')

test('one set-based read, STABLE, behind the existing Operations operation at the same rank (3), with no new public function and no new menu', () => {
  expect(M).toMatch(/function security\.data_delivery_v1\(\)[\s\S]*?stable security definer/i)
  expect(M).toContain("if p_action = 'data_delivery' then")
  expect(M).toContain('return security.data_delivery_v1();')
  expect(M).toContain('pg_temp.edit_one(\'public.admin_layer23(text,jsonb)\'')
  expect(M).not.toMatch(/create or replace function public\./i)
  expect(UI).toContain("rpc('admin_layer23',{p_action:'data_delivery'")
  expect(UI).toMatch(/rank<3\)return null/)
})

test('the read never writes and the refresh is the only writer; the evaluator of the lane funnels is reused, not copied', () => {
  const read = M.slice(M.indexOf('create or replace function security.data_delivery_v1()'), M.indexOf('-- 6. the Operations action'))
  expect(read).not.toMatch(/\b(insert into|update\s+pipeline|delete from|truncate)\b/i)
  expect(M).toContain('security.lane_funnel_eval_v1(m.sql, m.hours)')
  expect(M).not.toMatch(/create or replace function security\.lane_funnel_eval_v1/)
  expect(M).toMatch(/create or replace function security\.data_delivery_refresh_v1[\s\S]*?security definer/i)
  // one pass over the scheduler history for all streams: the cron history is read once, outside the stream loop
  expect((read.match(/cron\.job_run_details/g) || []).length).toBe(1)
})

test('every stream states what it does not measure, and the read returns known=false with a reason rather than a zero', () => {
  for (const key of ['net_removed', 'speed', 'queue', 'website', 'zoho', 'coverage_total', 'holds_by_cause']) expect(M).toContain(`'${key}'`)
  expect(M).toContain("jsonb_build_object('known', false")
  expect(M).toContain('Could not be counted: ')
  expect(M).toContain('Not counted yet')
  // the screen never defaults a missing figure to 0
  expect(UI).not.toMatch(/\?\?\s*0\b|\|\|\s*0\b[^.]/)
  expect(UI).toContain('Not measured')
  expect(UI).toContain('data-dd-unknown')
})

test('the refresh interval, the windows and the number of reasons are settings, not code', () => {
  for (const k of ['data_delivery.on', 'data_delivery.refresh_minutes', 'data_delivery.measures_per_run', 'data_delivery.run_budget_seconds', 'data_delivery.net_short_hours', 'data_delivery.net_long_hours', 'data_delivery.stale_after_minutes', 'data_delivery.ui_refresh_seconds', 'data_delivery.run_history_hours', 'data_delivery.reasons_shown']) expect(M).toContain(`'${k}'`)
  expect(UI).toContain('d?.ui_refresh_seconds')
  expect(UI).toContain('visibilityState')
  expect(M).toContain("'* * * * *', 'select security.data_delivery_refresh_v1()'")
})

test('it is the first panel on Operations, above the existing panels, and the lane funnels it links to stay', () => {
  expect(MAIN).toMatch(/<div className="m-page-stack"><DataDelivery rank=\{rank\} onError=\{err\}\/><Layer23Operations/)
  expect(MAIN).toContain('<LaneFunnels rank={rank} onError={err}/>')
  expect(MAIN).toContain('function presetOf(')
  expect(MAIN).toMatch(/PRESET_KEYS=\[[^\]]*'hasIntake'[^\]]*'website'[^\]]*'zoho'/)
})

test('the database fixture proves behaviour on a scratch database and CI runs it on the isolated image', () => {
  for (const needle of ['unknown', 'green_no_admission', 'stale', 'rank 2 is refused', 'division by zero', 'applied twice'.slice(0, 7)]) expect((FX + RUN).toLowerCase()).toContain(needle.toLowerCase())
  expect((FX.match(/pg_temp\.(ok|raises)\(/g) || []).length).toBeGreaterThan(40)
  expect(RUN).toContain('migration applied twice')
  expect(WF).toContain('postgres:17.6-alpine')
  expect(WF).toContain('tests/fixtures/fops03a-data-delivery/run.sh')
  expect(WF).toMatch(/^# Guards: /m)
})
