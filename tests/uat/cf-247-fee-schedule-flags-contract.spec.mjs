// Decision 210: an approved fee schedule settles flagged fees it answers; the rest show the schedule's fee.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const read = p => fs.readFileSync(p, 'utf8')

test('database: same fee or a per-year fee within 15% settles the flag; approval runs it; hand locks left alone', () => {
  const m = read('supabase/migrations-archive/20261001180200_cf247_fee_schedule_settles_flags.sql')
  expect(m).toContain("if r.amount = r.sched_amount then")
  expect(m).toContain("elsif r.amount > 0 and r.sched_amount / r.amount between 0.85 and 1.15 then")
  expect(m).toContain("where s.decision = 'approved' and fr.current and fr.basis = 'annual'")
  expect(m).toContain("exception when others then null; -- a value locked by hand is left for a person")
  expect(m).toContain("jsonb_build_object(''flags'', security.fee_schedule_settle_flags_v1(p_source_id))")
  expect(m).toContain("if v is distinct from '664ed3249f3c07678db0797dc18c4c8d' then raise exception")
  expect(m).toContain("if v is distinct from 'badaca6600ca02c5195491306d82440e' then raise exception")
  expect(m.toLowerCase()).not.toContain('delete from')
})

// v2.15.253 (Platform Admin, 12 Oct 2026): Layer 4 › Flagged values retired (open flags closed); the browser check of its schedule fee went with it.
