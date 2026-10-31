// Guards: StudySearch SS-007 integrity (decision D1, Platform Admin 31 Oct 2026 13:30; mandate 1 Nov 2026 08:57; admin 2026-10-31-studysearch-transformation.md §34): coverage admission never plans a course under an open binding remediation hold, and the 167 official links a coverage-admit run re-activated on held courses are set unverified again, count- and md5-guarded, with a search refresh.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261101030000_cf247_ss007_hold_admission.sql', 'utf8')
const code = (s) => s.replace(/--[^\n]*/g, '')

test('md5-guarded plan edit adds the SS-007 hold; nothing dropped; consumer API untouched', () => {
  expect(m).toContain("if md5(v) <> '7390a600044900f5d11d2be436e94ff6' then raise exception")
  expect(m).toContain("'f9dceaf2ff05e2b410d06ed968cfcac0'")
  expect(m).toContain('and not security.course_held_v1(p.course_id)),')
  expect(m).toMatch(/^-- Replaces: security\.coverage_admission_plan_v1/m)
  expect(m).toMatch(/^-- Retires: nothing/m)
  expect(code(m)).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(code(m)).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|function\s+api\./)
})

test('repair restores exactly the measured 167 links, as D1 did, then requests a refresh; post-check', () => {
  expect(m).toContain("if v_n <> 167 or v_md5 <> 'c0aff804f9a0465da788a65efd7987d7' then raise exception")
  expect(m).toContain("update catalogue.course_links l set status = 'unverified', is_primary = false, updated_at = now()")
  expect(m).toContain("l.updated_at = '2026-10-31 03:30:00.566382+00'")
  expect(m).toContain('insert into search.refresh_requests(requested_by)')
  expect(m).toContain("raise exception 'SS-007 post-check: the admission plan still includes a held course'")
})
