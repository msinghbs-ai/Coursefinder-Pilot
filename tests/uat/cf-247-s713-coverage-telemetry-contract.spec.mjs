// Guards: Coverage telemetry (Platform Admin 18 Nov 2026 12:19, applied 19 Nov 2026 05:21 item 3): a metadata-driven tracked-field registry with no hardcoded attribute ceiling, a generic recorder inside the existing hourly target (no new job), and one read for the Coverage screen (fields, 7-day change, 0 of N to N of N, country x domain grid); window lengths are settings; nothing in the consumer API.
// CF-247 S713. supabase/migrations/20261119053000_cf247_coverage_tracked_fields_telemetry.sql.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261119053000_cf247_coverage_tracked_fields_telemetry.sql', 'utf8')
const code = M.split('\n').filter(l => !l.trimStart().startsWith('--')).join('\n')

test('registry, recorder and read; the recorder is replaced only from its known definition', () => {
  expect(code).toContain('create table if not exists pipeline.tracked_fields (')
  expect(code).toContain('comment on table pipeline.tracked_fields is')
  expect(code).toContain('create or replace function security.tracked_field_coverage_v1()')
  expect(code).toContain('create or replace function public.admin_coverage_telemetry_v1(p_args jsonb default')
  expect(code).toContain("'769e1a9dfe1c9219c3bba02fa63e5e40'")
})

test('window lengths are settings (G2); no new job (G1); housekeeping lines (s42)', () => {
  expect(code).toContain("'coverage.velocity_days'")
  expect(code).toContain("'coverage.spark_days'")
  expect(code).not.toMatch(/cron\.schedule\(/)
  expect(M).toMatch(/^-- Replaces: /m)
  expect(M).toMatch(/^-- Retires: /m)
})

test('nothing in the frozen consumer API; nothing dropped or deleted', () => {
  expect(code).not.toMatch(/website_v2_|website_edge_|zoho_edge_|website_api_v2_|svc_website_settings_v1|function api\./)
  // the one delete is the recorder's existing 120-day history retention, carried over unchanged inside its function body
  const deletes = code.split('\n').filter(l => /^\s*(delete from|drop |truncate )/i.test(l))
  expect(deletes.length).toBe(1)
  expect(deletes[0]).toContain('delete from pipeline.field_coverage_daily where snapshot_date < current_date - 120;')
})
