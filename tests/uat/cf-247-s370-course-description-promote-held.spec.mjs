// Guards: "No unauthorised Layer 4 admission" (Platform Admin P0 mandate 3 Nov 2026 10:44 section 7) and the held_first_admission promise of 3 Nov 2026
// (a provider's held descriptions are "admitted once the first ones are approved"): migration 20261107120000 only moves a held reading into the person's queue.
// The database behaviour (16 checks) runs on the production-parity fixture: tests/fixtures/course-description-promote-held/run.sh. This spec holds the source contract.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261107120000_cf247_course_description_promote_held.sql', 'utf8')
const code = MIG.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const FX = 'tests/fixtures/course-description-promote-held'

test('migration: queues held readings for a person and nothing else (no admission, no decision, no trust change, no AI)', () => {
  const a = code.indexOf('function security.course_description_promote_held_v1'), body = code.slice(a, code.indexOf('$function$;', code.indexOf('$function$', a) + 10))
  expect(a).toBeGreaterThan(-1)
  // the only rows it writes are a pending Layer 4 item and the held reading it settles into 'review'
  expect(body).not.toMatch(/\b(update|insert\s+into)\s+catalogue\.courses\b/i)
  expect(body).not.toMatch(/layer4_decisions|search\.refresh_requests/)
  expect(body).toMatch(/insert into pipeline\.layer4_review_items[\s\S]*?'pending'/)
  expect(body).not.toMatch(/status\s*=\s*'(approved|edited_approved)'/)
  // the cap, the trust rule and the switch are settings (G2); no number is written into the function
  expect(body).toContain("pipeline_num_v1('enrich.course_description_pending_max'")
  expect(body).toContain("pipeline_num_v1('enrich.course_description_promote_held_on'")
  expect(body).toContain('security.course_description_trusted_v1(p_provider)')
  // every guard of the original admission is kept: bound page, identity proof, lock, empty description, no second pending item, every check run again
  for (const g of ['e.evidence_id is not distinct from g.evidence_id', 'coverage_identity_allowed', 'manual_locks', "nullif(btrim(c.description), '') is not null", 'course_description_check_v1', 'skip locked']) expect(body, g).toContain(g)
  expect(code).toContain('revoke all on function security.course_description_promote_held_v1(uuid) from public, anon, authenticated')
})

test('migration: the switch ships on inside the existing cap; the old trigger is replaced under an md5 guard; the trust rule is untouched', () => {
  expect(MIG).toMatch(/^-- Replaces: .*course_description_review_trg_v1/m)
  expect(MIG).toMatch(/^-- Retires: nothing/m)
  expect(MIG).toContain('d143eba24f5896f36a3a93e8e5c075aa')
  expect(code).toMatch(/'enrich\.course_description_promote_held_on'[\s\S]*?'number', '1'::jsonb, 0, 1, 'on\/off'/)
  expect(code).not.toMatch(/update\s+pipeline\.platform_toolset_settings/i)
  expect(code).not.toMatch(/enrich\.course_description_review_first'\s*,\s*'/)
  // the trigger keeps its two original steps and adds the call after any decision
  const t = code.slice(code.indexOf('function security.course_description_review_trg_v1'))
  expect(t).toContain("'not admitted in Layer 4 ('")
  expect(t).toContain('security.course_description_release_held_v1(v_pid)')
  expect(t.indexOf('course_description_promote_held_v1')).toBeGreaterThan(t.indexOf('end if;\n  perform') - 1)
  // G3, Decision 260: no consumer API object, no drop or delete
  expect(code).not.toMatch(/website_v2_|website_edge_|zoho_edge_|api\./)
  expect(code).not.toMatch(/\b(drop|delete\s+from|truncate)\b/i)
  expect(code).toContain("'20261107120000'")
})

test('fixture runner applies the migration twice on the production-parity fixture and fails on any scenario error', () => {
  const run = fs.readFileSync(`${FX}/run.sh`, 'utf8'), sc = fs.readFileSync(`${FX}/scenarios.sql`, 'utf8')
  expect(run).toContain('set -euo pipefail')
  expect(run.match(/-f \$MIG/g).length).toBe(2)
  expect(run).toContain('promote-held scenarios FAILED')
  for (const t of ['approve 1: held course 3 now waits for a person', 'reject 2: course 4 takes the place', 'no description was written by the promotion', 'nothing was decided by the promotion',
    'switch off: P2 held readings stay held after a decision', 'trusted provider: promotion is a no-op', 'the function can be called by nobody but the owner']) expect(sc).toContain(t)
})
