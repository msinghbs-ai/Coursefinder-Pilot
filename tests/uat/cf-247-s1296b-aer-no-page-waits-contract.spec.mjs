// Guards: SS-Programme-Control 27 Nov 2026 11:27 AEDT (autonomous AER reader selection): a course with no proven page is not offered for a read until a page is bound; the pattern is a setting
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261130153000_cf247_s1296_aer_no_page_waits_for_a_page.sql', 'utf8')

test('s1296b: a not-a-read outcome of "no proven course page" waits for a bound page, from a setting, not a timer', () => {
  expect(MIG).toContain("'aer.no_page_pattern'")
  expect(MIG).toContain("to_jsonb('^no proven course page'::text)")
  expect(MIG).toMatch(/d\.last_at < now\(\) - d\.tech and not \(d\.nopage <> '' and d\.last_reason ~\* d\.nopage and d\.bound_ev is null\)/)
  expect(MIG).toContain('no proven course page yet')
  expect(MIG).toContain("security.toolset_setting('pipeline', 'aer.no_page_pattern')")
})

test('s1296b: the setting has a label, a unit and used_by; nothing is dropped, deleted or changed in the consumer API, locks or jobs', () => {
  expect(MIG).toMatch(/'Entry requirements: outcome that means no page is bound to the course'/)
  expect(MIG).toContain("'pattern', 1158")
  expect(MIG).toContain("'security.aer_first_read_state_v1'")
  expect(MIG.replace(/on commit drop/g, '')).not.toMatch(/(^|\n)\s*(drop|delete from|truncate)\b/i)
  expect(MIG).toContain("(v->>'functions')::int <> 75")
  expect(MIG).toContain('manual locks changed')
  expect(MIG).toContain('-- Replaces:')
  expect(MIG).toContain('-- Retires:')
})
