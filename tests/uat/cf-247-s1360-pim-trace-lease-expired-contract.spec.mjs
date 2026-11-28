// Guards: DR-19 trace (PC-20261128-CONTINUOUS-BUILD-EXECUTE): the record trace names deferred account refusals (s1355) and expired capped leases with their registry remedy; the failure classifier reads s1353's settled reason as lease_expired; one migration version per file (main-green fix for the duplicate 20261201120000)
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261201140000_cf247_s1360_pim_trace_lease_expired.sql', 'utf8')

test('s1360: the trace names expired capped leases (registry remedy) and deferred refusals; the classifier reads lease_expired', () => {
  expect(sql).toContain("v_last.state = 'leased' and v_last.leased_until <= now() and coalesce(v_last.attempts, 0) >= v_attempts")
  expect(sql).toContain("'lease_orphaned' = any(m.treats)")
  expect(sql).toContain('attempt not counted (recovery policy ai_account_refusal)')
  expect(sql).toContain("when v_cause = 'lease_expired' then 'lease_expired'")
  expect(sql).toContain("when p_reason ilike 'lease expired at the attempt cap%' then 'lease_expired'")
  expect(sql).toContain("'security.pim_record_trace_v1(uuid,text,boolean)'")
  expect(sql).toContain("'security.pim_failure_cause_v1(text)'")
})

test('s1360: anchored, guarded, read-only diagnostics', () => {
  expect(sql).toContain('found % times')
  expect(sql).toContain('security.consumer_api_check_v1()')
  expect(sql).toContain('manual locks changed')
  expect(sql).toContain('active job count changed')
  expect(sql).not.toMatch(/insert into|update pipeline\.|cron\.schedule/i)
  expect(sql).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

test('s1360: no two migration files share a version (from 20261201120000 on)', () => {
  const v = fs.readdirSync('supabase/migrations').filter(f => f.endsWith('.sql')).map(f => f.split('_')[0]).filter(x => x >= '20261201120000')  // from the duplicate this fixes on
  const dup = v.filter((x, i) => v.indexOf(x) !== i)
  expect(dup).toEqual([])
})
