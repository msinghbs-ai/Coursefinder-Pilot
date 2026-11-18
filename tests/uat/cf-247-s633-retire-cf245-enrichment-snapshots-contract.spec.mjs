// Guards: legacy telemetry retirement (Platform Admin 18 Nov 2026 12:19): only telemetry with no screen or operational reader is retired (two CF-245 rollup targets switched off, their objects marked retiring, drops left to an admin paste file); Link refresh, Stalled fields and every snapshot with a reader are kept.
// CF-247 S633. supabase/migrations-archive/20261118151000_cf247_retire_cf245_enrichment_snapshots.sql.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations-archive/20261118151000_cf247_retire_cf245_enrichment_snapshots.sql', 'utf8')

test('the two CF-245 targets are switched off and their objects marked retiring; readers are kept', () => {
  expect(M).toContain("set enabled = false, updated_at = now(),")
  expect(M).toContain("where target_code in ('coursefinder-cf245-enrichment-coverage-snapshot', 'coursefinder-cf245-enrichment-hourly-admin-cache') and enabled;")
  expect(M).toContain("set status = 'retiring', retire_after = current_date + 14, updated_at = now(),")
  expect(M).toContain("raise exception 'post-check: a target with a reader was switched off'")
  expect(fs.readFileSync('src/LinkRefresh.jsx', 'utf8')).toContain("supabase.rpc('admin_link_refresh_read')")
  expect(fs.readFileSync('src/FieldCoverage.jsx', 'utf8')).toContain('title="Stalled fields"')
})

test('nothing is dropped or deleted by the migration', () => {
  expect(M).not.toMatch(/^\s*(delete from|drop |truncate )/im)
  expect(M).not.toMatch(/cron\.unschedule/)
  expect(M).toMatch(/-- Retires: rollup targets coursefinder-cf245-enrichment-coverage-snapshot/)
})
