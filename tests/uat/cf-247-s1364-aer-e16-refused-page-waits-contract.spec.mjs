// Guards: CF-247 s1364, Platform Admin 28 Nov 2026 22:01 AEDT and PC-20261128-2113/2121 (E16 selector alignment): a course whose reader found no proven page (E16 refused the page, or none is bound) is not offered for a first read again until a page the reader may take is bound or read again after that outcome, or the reader revision changes; E16, the identity policy and the reader are unchanged
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261201170000_cf247_s1364_aer_e16_refused_page_waits.sql', 'utf8')
const BODY = MIG.match(/as \$f\$([\s\S]*?)\$f\$/)[1]

test('s1364: the no-page outcome waits for a changed page or reader, not the technical retry timer, even when a page is bound', () => {
  // the page set the reader itself may take (security.enrich_fields_slice_v1: bound, or ambiguous with an identity proof)
  expect(BODY).toContain("(select max(greatest(pg.bound_at, pg.read_at)) from pipeline.coverage_course_pages pg where pg.course_id = c.course_id and pg.status in ('bound', 'ambiguous')) page_at")
  expect(BODY).toContain("when d.read_class = 'not_a_read' and d.nopage <> '' and d.last_reason ~* d.nopage then coalesce(d.page_at > d.last_at, false) or coalesce(d.changed_at > d.last_at, false)")
  // other outcomes that were not a read keep the technical retry timer
  expect(BODY).toContain("when d.read_class = 'not_a_read' then d.last_at < now() - d.tech\n")
  // the s1296b condition (held only while no page is bound) is gone from the eligibility
  expect(BODY).not.toMatch(/d\.last_at < now\(\) - d\.tech and not \(d\.nopage <> '' and d\.last_reason ~\* d\.nopage and d\.bound_ev is null\)/)
  // the no-page branch comes before the timer branch, so a bound but refused page never falls through to the timer
  expect(BODY.indexOf("when d.read_class = 'not_a_read' and d.nopage")).toBeLessThan(BODY.indexOf("when d.read_class = 'not_a_read' then d.last_at < now() - d.tech"))
})

test('s1364: each waiting course says why, and E16 itself is not run or relaxed by the selector', () => {
  expect(BODY).toContain('the course page check (E16) refused the page found: a read waits until')
  expect(BODY).toContain('a page was bound or read again since the reader found no proven course page')
  expect(BODY).toContain('the reader changed since it found no proven course page')
  expect(BODY).toContain('no proven course page yet: a read waits until a page is bound to this course')
  expect(BODY).not.toContain('course_page_check_v1')
  expect(BODY).not.toContain('coverage_identity_allowed')
  // the existing guards on every eligible course stay: unchanged-copy learning, deterministic reader outcome
  expect(BODY).toContain("security.ops_learning_retry_check_v1('aer_first_read:unchanged_copy_no_result', d.course_id::text, d.sig)")
  expect(BODY).toContain('and not (d.det is not null and not (d.detok ? d.det))) as eligible')
})

test('s1364: the pattern stays a setting; nothing is dropped, deleted or changed in the consumer API, locks or jobs', () => {
  expect(BODY).toContain("security.toolset_setting('pipeline', 'aer.no_page_pattern')")
  expect(BODY).toContain("security.toolset_setting('pipeline', 'aer.read_again_change_keys')")
  expect(MIG).toMatch(/update pipeline\.platform_toolset_settings\s+set help = [\s\S]*where toolset_key = 'pipeline' and key = 'aer\.no_page_pattern';/)
  expect(MIG.replace(/on commit drop/g, '')).not.toMatch(/(^|\n)\s*(drop|delete from|truncate)\b/i)
  expect(MIG).toContain("(v->>'functions')::int <> 75")
  expect(MIG).toContain('manual locks changed')
  expect(MIG).toContain('a cron job changed')
  expect(MIG).toContain('-- Replaces:')
  expect(MIG).toContain('-- Retires:')
  expect(MIG).toContain('-- Consumer API change approved: none')
})
