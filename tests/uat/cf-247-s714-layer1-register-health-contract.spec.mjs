// Guards: Layer 1 Register health (Platform Admin 19 Nov 2026 06:45 and 06:50): ABS and BOM get a real first run through the standard Layer 1 scheduler (no value overwritten, next run one cadence later); the ten stale August 2026 Canadian college readers are retired with the gap on record (supersedes the 18 Nov hold of s624 by Platform Admin decision); Ontario APS is paused with its reason; LIN 19/198 is made due after its loader is deployed.
// CF-247 S714. supabase/migrations/20261119085100_cf247_layer1_register_health_ca_cleanup.sql.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261119085100_cf247_layer1_register_health_ca_cleanup.sql', 'utf8')
const code = M.split('\n').filter(l => !l.trimStart().startsWith('--')).join('\n')

test('ABS and BOM are made due for the standard scheduler, not stamped as run', () => {
  expect(code).toContain("s.label in ('ABS Regional Population', 'BOM Climate Statistics (IDCJCM0037)') and o.active and not o.paused and o.last_verified_at is null")
  expect(code).toContain('set next_verification_at = now()')
  expect(code).not.toMatch(/last_verified_at\s*=|verification_status\s*=\s*'passed'|last_schedule_status\s*=/)
})

test('the ten college readers are retired, kept and paused, with the gap on record', () => {
  for (const l of ['Fanshawe College current programme catalogue', 'Seneca Polytechnic current academic catalogue', 'Fleming College Programs A-Z', 'Lambton College Full-Time Programs',
    'St. Clair College Programs', 'Collège Boréal postsecondary programmes', 'Sault College Programs A-Z', 'Northern College programme catalogue',
    'Centennial College Program Catalogue API', 'St. Lawrence College Full-Time Programs']) expect(code).toContain(`'${l}'`)
  expect(code).toContain("update pipeline.sources set status = 'retired'")
  expect(code).toContain('set paused = true, auto_ingest = false')
  expect(code).toContain("'Retired on Platform Admin instruction (19 Nov 2026 06:50): August 2026 per-college reader on Manual with a failed count check. Nothing replaces it yet ('")
  expect(code).toContain("'source_retire'")
  expect(code).toContain("raise exception 'post-check: expected 10 retired Canadian readers, found %'")
})

test('Ontario APS is paused with a clear reason; LIN 19/198 is due', () => {
  expect(code).toContain("s.label = 'Ontario public college programmes / APS' and not o.paused")
  expect(code).toContain('the scoped apply timed out on 8 Nov 2026')
  expect(code).toContain("s.label = 'LIN 19/198 Evidence of Financial Capacity (Subclass 500 and 590)' and o.last_verified_at is null")
})

test('data only: no new table or function, nothing dropped or deleted, consumer API checked, housekeeping lines', () => {
  expect(code).not.toMatch(/create table|create or replace function/i)
  expect(code).not.toMatch(/^\s*(delete from|drop |truncate )/im)
  expect(code).toContain('v_drift := security.consumer_api_check_v1();')
  expect(M).toMatch(/^-- Replaces: /m)
  expect(M).toMatch(/^-- Retires: the ten Canadian college readers/m)
})
