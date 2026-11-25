// Guards: PIM step 5 and interface 3 (Platform Admin 26 Nov 2026 03:48, 03:55 AEDT): bounded, reason-aware source revisit through the existing reader with history and backoff kept, no access restriction bypassed, no bulk reset; academic entry hand-off whose fetch is never counted as delivery; deadline three states; provider scholarships measured; G1, G2, G3, locks, cron ceiling.
// s1171: security.pim_source_revisit_v1 and its due read, the planner academic_entry step, the handoff state in the tick, deadline defined, p_scholarships measured.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261128110000_cf247_s1171_pim_source_revisit_academic_entry_handoff.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1171: only revisitable outcomes, never access refusals; backoff on the existing recheck setting; one read per revisit; history kept', () => {
  expect(code).toContain("g.read_status in ('fetch_failed', 'needs_render', 'too_thin')")
  expect(code).toContain('not in (401, 403, 407, 429, 451)')
  expect(code).not.toMatch(/\bg\.read_status in \([^)]*(blocked|robots_disallowed)/)
  expect(code).toContain("security.pipeline_num_v1('gaps.recheck_days', 60)::int * power(2, least(coalesce(rv.revisits, 0), 6))::int")
  expect(code).toContain('attempts_before_revisit = rv.attempts_before_revisit + excluded.attempts_before_revisit')
  expect(code).toContain('set read_attempts = 2, next_read_at = now()')
  expect(code).toContain('comment on table pipeline.coverage_page_revisits')
  expect(code).toContain("coalesce(g.leased_until, '-infinity') < now()")
})

test('s1171: bounded by a setting, logged, no bulk reset', () => {
  expect(code).toContain("'pipeline', 'pim.source_revisit_batch'")
  expect(code).toContain('limit greatest(0, coalesce(p_limit, 0))')
  expect(code).toContain("'pim', 'source_revisit'")
  expect(code).not.toMatch(/update pipeline\.coverage_course_pages[^;]*set read_attempts = 0/i)
})

test('s1171: the planner hands academic entry to the lane; the tick ends the step on fetches, not on admitted rows', () => {
  expect(code).toContain("''step'', ''academic_entry''")
  expect(code).toContain("''kind'', ''handoff''")
  expect(code).toContain("when s->''ref''->>''kind'' = ''handoff'' then")
  expect(code).toContain('fetches finished, not rows admitted')
})

test('s1171: deadline defined in three states with no derived date; provider scholarships measured; guards', () => {
  expect(code).toContain("where field = 'deadline'")
  expect(code).toContain('No date is ever derived')
  expect(code).toContain("when ''p_scholarships'' then exists (select 1 from scholarship.scholarships s")
  expect((code.match(/security\.consumer_api_check_v1\(\)/g) || []).length).toBe(2)
  expect(code).not.toMatch(/\b(truncate|cron\.schedule|drop\s+(table|function|column|constraint|trigger)|delete\s+from)\b/i)
})
