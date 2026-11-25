// Guards: Platform Admin decision 26 Nov 2026 06:57 AEDT (Accelerated Source Recovery): scoped pim.source_revisit_days (7) for the s1171 revisit, gaps.recheck_days unchanged; batch enforced in the function; eligibility tested again on the claimed row; entry-missing courses first; access restrictions kept; G2, G3, locks, cron ceiling.
// s1172: security.pim_source_revisit_due_v1 and security.pim_source_revisit_v1 replaced.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261128235000_cf247_s1172_pim_source_revisit_days.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1172: the scoped setting drives the backoff; gaps.recheck_days is not touched', () => {
  expect(code).toContain("'pipeline', 'pim.source_revisit_days'")
  expect(code).toContain("'number', '7'::jsonb, 1, 60, 'days'")
  expect(code).toContain("security.pipeline_num_v1('pim.source_revisit_days', 7)::int * power(2, least(coalesce(rv.revisits, 0), 6))::int")
  expect(code).not.toContain("pipeline_num_v1('gaps.recheck_days'")
})

test('s1172: the batch is capped inside the function and each claim re-tests eligibility under a row lock', () => {
  expect(code).toContain("least(greatest(0, coalesce(p_limit, 0)), security.pipeline_num_v1('pim.source_revisit_batch', 25)::int)")
  expect(code).toContain('for update of g skip locked')
  expect(code).toContain("g.read_attempts >= 3 and coalesce(g.leased_until, '-infinity') < now()")
  expect(code).toContain('guard: a page was retried twice')
})

test('s1172: courses without academic entry rows come first; access refusals never retried', () => {
  expect(code).toContain("order by exists (select 1 from catalogue.course_entry_requirements q where q.course_id = g.course_id and q.status = 'active')")
  expect(code).toContain('not in (401, 403, 407, 429, 451)')
  expect(code).not.toMatch(/\bg\.read_status in \([^)]*(blocked|robots_disallowed)/)
})

test('s1172: no queue, job or drop; G3 75/48, no lock removed, cron ceiling', () => {
  expect(code).not.toMatch(/\b(create table|cron\.schedule|truncate|drop\s+(table|function|column|constraint|trigger)|delete\s+from)\b/i)
  expect((code.match(/security\.consumer_api_check_v1\(\)/g) || []).length).toBe(2)
  expect(MIG).toMatch(/^-- Replaces:/m)
  expect(MIG).toMatch(/^-- Retires:/m)
})
