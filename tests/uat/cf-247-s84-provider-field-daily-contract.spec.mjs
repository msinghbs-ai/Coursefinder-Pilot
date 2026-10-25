// Guards: CF-247 S84: daily field counts per provider: table, job, retention setting, seeds
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

// CF-247 (Platform Admin, 21 Oct 2026 18:32): "Produce it daily please" - the NZ per-provider field report, daily. Real day-by-day
// counts per provider instead of working out "before" afterwards.
const m = fs.readFileSync('supabase/migrations/20261021210000_cf247_provider_field_daily.sql', 'utf8')

test('daily field counts per provider: table, job, retention setting, seeds', () => {
  expect(m).toContain('create table if not exists pipeline.provider_field_daily')
  expect(m).toContain('comment on table pipeline.provider_field_daily')
  expect(m).toContain("select cron.schedule('provider-field-daily', '55 19 * * *', $$select security.provider_field_daily_record_v1()$$);")
  expect(m).toContain("('provider-field-daily', 'Reporting'")
  expect(m).toContain("security.pipeline_num_v1('retention.provider_field_daily_days', 120)")
  expect(m).toContain("select security.provider_field_daily_record_v1('2026-10-21');")
  expect(m).toContain("'reconstructed', now()")
  expect(m).toMatch(/^-- Replaces: /m)
  expect(m).toMatch(/^-- Retires: /m)
})
