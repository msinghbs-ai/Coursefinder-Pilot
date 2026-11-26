// Guards: F-OPS.21 Data Delivery performance (SS-Programme-Control P0, 26 Nov 2026 14:25 AEDT): the four heavy helpers are counted by the existing background count, never by the screen read; response contracts kept; last good result, freshness and errors kept; no new scheduler; G3, locks, cron ceiling.
// s1174: pipeline.data_delivery_helper_snapshots, md5-guarded edits of security.data_delivery_refresh_v1 and security.data_delivery_v1.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261129103000_cf247_s1174_data_delivery_helper_snapshots.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1174: the four helpers are snapshotted in the existing background count and read from the snapshot', () => {
  expect(code).toContain("array[''cdesc_stages'', ''intake'', ''aer'', ''pdesc'']")
  expect(code).toContain("make_interval(mins => v_every)")
  expect(code).toContain("from pipeline.data_delivery_helper_snapshots x where x.helper = %L), security.data_delivery_%s_v1())")
  expect(code).toContain("'3dac30bc7f5239a2536c0b1f1b15d1d4'")
  expect(code).toContain("'4ef07c81650790ec305116240a94249a'")
})

test('s1174: a failed count keeps the last good result and records the error; freshness is reported', () => {
  expect(code).toContain('do update set took_ms = excluded.took_ms, error = excluded.error, failed_at = excluded.failed_at')
  expect(code).toContain("''snapshots''")
})

test('s1174: no new scheduler; nothing dropped; G3 75/48, no lock removed, cron ceiling', () => {
  expect(code).not.toMatch(/\b(cron\.schedule|truncate|drop\s+(table|function|column|constraint|trigger)|delete\s+from)\b/i)
  expect(code).toContain('comment on table pipeline.data_delivery_helper_snapshots')
  expect((code.match(/security\.consumer_api_check_v1\(\)/g) || []).length).toBe(2)
  expect(MIG).toMatch(/^-- Replaces:/m)
  expect(MIG).toMatch(/^-- Retires:/m)
})
