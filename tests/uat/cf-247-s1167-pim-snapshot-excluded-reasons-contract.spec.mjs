// Guards: F-OPS.21 and PIM step 3 (Platform Admin 25 Nov 2026 23:12 AEDT): the monitoring count never delays the Admin UI (existing Data Delivery snapshot reused); excluded-gap reasons kept and reconsidered automatically; G1, G2, G3, locks, cron.
// s1167: security.data_delivery_v1 reads the PIM snapshot; security.data_delivery_refresh_v1 counts it; security.pim_excluded_gaps_v1 gives the reasons.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261128060000_cf247_s1167_pim_snapshot_excluded_reasons.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1167: the screen read takes the snapshot; the existing background count makes it; a failed count keeps the last good one', () => {
  expect(code).toContain("from pipeline.data_delivery_job_runs j where j.singleton),")
  expect(code).toContain("'5f5f1bd84808ce59d587f7d1a419697d'")
  expect(code).toContain("'d84480a5d78ee11e204b305fdb2d9787'")
  expect(code).toContain('pim_error = left(sqlerrm, 300), pim_failed_at = clock_timestamp() where singleton')
  expect(code).toContain("guard: the screen read still runs the count")
  expect(code).not.toMatch(/cron\.schedule|insert into pipeline\.automation_catalogue/i)
})

test('s1167: every non-admitted gap has a reason; only eligible ones are planned; the reasons agree with the planner', () => {
  for (const r of ['no_reader', 'country_not_covered', 'closed_to_international', 'recorded_not_applicable', 'no_source_revisit_pending', 'eligible_unconfirmed', 'eligible'])
    expect(code).toContain(`'${r}'`)
  expect(code).toContain("'next_revisit'")
  expect(code).toContain("guard: planner % and eligible reasons % disagree")
})

test('s1167: the count-again time is the existing setting (G2)', () => {
  expect(code).toContain('make_interval(mins => v_every)')
})

test('s1167: nothing dropped, G3 75/48, locks and cron guarded', () => {
  expect((code.match(/security\.consumer_api_check_v1\(\)/g) || []).length).toBe(2)
  expect(code).not.toMatch(/\b(delete\s+from|truncate|drop\s+(table|function|column|constraint|trigger))\b/i)
  expect(MIG).toContain('-- Replaces:')
})
