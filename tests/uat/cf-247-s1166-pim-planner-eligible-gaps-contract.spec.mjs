// Guards: Global Autonomous PIM step 3 (Platform Admin 25 Nov 2026 18:49, 21:37): the planner takes only eligible gaps (applicable, readable, not evidenced no-source before its revisit); existing planner reused; G2, G3, locks, cron.
// s1166: security.enrich_plan_priority_v1 counts eligible gaps only; same signature; md5-guarded replace.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261128050000_cf247_s1166_pim_planner_eligible_gaps.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1166: a gap is eligible only when a reader exists, the field applies, and no not_applicable or not-yet-due no-source finding is open', () => {
  expect(code).toContain("a.state not in ('admitted', 'no_reader')")
  expect(code).toContain("r.applicability_rule = 'countries'")
  expect(code).toContain("r.applicability_requires = 'international_open' and c.open_to_international is false")
  expect(code).toContain("ab.absence_class = 'not_applicable' or ab.next_eligible_at > now()")
  expect(code).toContain('having count(*) filter (where e.eligible) > 0')
})

test('s1166: the existing planner function is replaced in place behind its md5, signature unchanged, no new queue or job', () => {
  expect(code).toContain("'366ff12040bac05d4e494956319a2b76'")
  expect(code).toContain('returns table(provider_id uuid, name text, country text, courses bigint, missing bigint, best_rank integer)')
  expect(code).not.toMatch(/create table|cron\.schedule|insert into pipeline\.(automation_catalogue|admin_job_kinds)/i)
})

test('s1166: the rehearsal proves the new list is the old list with gaps taken out, never a new provider or a higher count', () => {
  expect(code).toContain('n.missing > o.missing')
  expect(code).toContain('o.provider_id is null')
})

test('s1166: nothing dropped, G3 75/48, locks and cron guarded', () => {
  expect((code.match(/security\.consumer_api_check_v1\(\)/g) || []).length).toBe(2)
  expect(code).not.toMatch(/\b(delete\s+from|truncate|drop\s+(table|function|column|constraint|trigger))\b/i)
  expect(MIG).toContain('-- Replaces:')
})
