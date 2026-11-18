// Guards: found course pages left unread past the reader's attempts are released for reading without search credits (Platform Admin 19 Nov 2026 07:39, S2-BOOST-Discovery handover decision 3; decision 2 keeps the proved ANU and La Trobe pages untouched)
// CF-247 S659. Migration 20261119085000_cf247_s659_release_unread_found_pages. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { migrationPath } from './support/migration-files.mjs'

const code = fs.readFileSync(migrationPath('20261119085000_cf247_s659_release_unread_found_pages.sql'), 'utf8').split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('only found pages with no read result, no proof and no stored reading, past the reader attempts, with the lease ended', () => {
  expect(code).toContain("s.state = 'found' and s.bound_url = p.url")
  expect(code).toContain("s.done_at >= (select min(r.opened_at) from pipeline.on_demand_requests r where r.reason like '[S656 course page search]%')")
  expect(code).toContain('p.read_status is null and p.read_at is null and p.identity_basis is null and p.evidence_id is null and p.candidates is null')
  expect(code).toContain("coalesce(p.leased_until, '-infinity') < now()")
  expect(code).toContain('not exists (select 1 from security.coverage_read_eligible_v1() e where e.course_id = p.course_id)')
  expect(code).toContain('not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.provider_id)')
  expect(code).toContain("l.field in ('official_url', 'course_url')")
})

test('the release is the reader first step only: next read now, attempts reset, lease cleared; no rebind, no overwrite of a proved page', () => {
  expect(code).toContain('set next_read_at = now(), read_attempts = 0, leased_until = null')
  expect(code).toContain("and p.status = 'bound' and p.read_status is null and p.identity_basis is null and p.candidates is null;")
  expect(code).not.toContain('course_page_rebind_v1')
  expect(code).not.toMatch(/set[^;]*\b(url|basis|identity_basis|candidates|evidence_id|read_status)\s*=/)
  expect(code.match(/update pipeline\.coverage_course_pages/g)).toHaveLength(1)
})

test('no number of attempts or course is written into the file; the reader own condition is checked, and the result is checked and recorded', () => {
  expect(code).not.toMatch(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/)
  expect(code.replace("like '%p.read_attempts<3%'", '')).not.toMatch(/read_attempts\s*(>=|=|<)\s*[1-9]/)
  expect(code).toContain("like '%p.read_attempts<3%'")
  expect(code).toContain("if v_done <> v_n then raise exception 'post-check:")
  expect(code).toContain("if v_eligible <> v_n then raise exception 'post-check:")
  expect(code).toContain("'search_credits', 0")
  expect(code).toContain("insert into pipeline.admin_control_events(area, action, target, detail, actor)")
})

test('no search is queued, no Firecrawl call, no setting; nothing is created or dropped', () => {
  expect(code).not.toMatch(/course_link_search\s+(set|values)|insert into pipeline\.(course_link_search|platform_toolset_settings|course_priority)|update pipeline\.(course_link_search|platform_toolset_settings)/)
  expect(code).not.toMatch(/on_demand_open_v1|firecrawl_calls|net\.http/i)
  expect(code).not.toMatch(/create (or replace )?(function|table|view|index|trigger)|alter table|cron\.schedule/i)
  expect(code).not.toMatch(/\bdrop\s+(table|function|trigger|schema|index|view)\b|\bdelete\s+from\b|\btruncate\b/i)
})
