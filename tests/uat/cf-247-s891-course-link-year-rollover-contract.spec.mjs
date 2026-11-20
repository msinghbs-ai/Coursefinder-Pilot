// Guards: Platform Admin 20 Nov 2026 22:58 AEDT (S1-CourseLink-2027-CRICOS s891): rule course_link_year_rollover_v1. A held official course page whose address
// carries a past year is tried at 2027, 2026, 2025 and then as held; the newest address that answers a plain read on the provider's own host, is not a
// "not found" or "no longer offered" page and proves the exact CRICOS code is admitted through the existing decision path under the system automation
// account, with its stored copy recorded at once. No new job (it runs inside link-refresh), no Firecrawl, no model, G3 and the 7,585 locks unchanged.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { addressYear, pageAnswer, strongIdentity, yearCandidates } from '../../supabase/functions/coverage-sweep/link-rollover.ts'

const MIG = fs.readFileSync('supabase/migrations/20261120235000_cf247_s891_course_link_year_rollover.sql', 'utf8')
const code = MIG.split('\n').filter(l => !l.trimStart().startsWith('--')).join('\n')

test('s891 migration: no public object, G3 and locks before and after, nothing deleted, no new job', () => {
  expect((MIG.match(/consumer_api_check_v1/g) || []).length).toBeGreaterThanOrEqual(2)
  expect((MIG.match(/pipeline\.manual_locks\) <> 7585/g) || []).length).toBe(2)
  expect(MIG).toMatch(/^-- Replaces:/m); expect(MIG).toMatch(/^-- Retires:/m)
  expect(code).not.toMatch(/create\s+(or replace\s+)?function\s+public\.|create\s+view\b|\b(drop|delete|truncate)\b/i)
  expect(code).not.toMatch(/cron\.schedule\(/)
  expect(code).toContain("select cron.alter_job(j.jobid, command := 'select security.link_refresh_with_rollover_v1(security.pipeline_num_v1(''batch.link_refresh'', 500)::int)')")
  expect(code).toContain("if (select count(*) from cron.job where active) > 140 then raise exception")
  for (const t of ['pipeline.link_rollover_requests', 'pipeline.link_rollover_checks']) expect(code).toContain(`comment on table ${t} is`)
  for (const k of ['link_rollover.on', 'batch.link_rollover', 'link_rollover.items_per_call', 'link_rollover.in_flight_max', 'link_rollover.retry_days', 'link_rollover.min_chars', 'link_rollover.page_markers', 'link_rollover.fetches_at_once', 'link_rollover.request_lost_minutes'])
    expect(code).toContain(`('pipeline', '${k}'`)
})

test('s891 decisions: the existing path, the system account, never a locked, refused or foreign page', () => {
  expect(code).toContain("v_sys constant uuid := 'c0ffee00-0000-4000-8000-000000000150'")
  expect(code).toContain("public.layer4_review_decide(r.id, 'approve', v_reason, null)")
  expect(code).toContain("public.layer4_review_decide(r.id, 'edit_and_approve', v_reason, to_jsonb(v_url))")
  expect(code).toContain("l.field in ('official_url', 'course_url')) then v_out := 'locked'")
  expect(code).toContain("then v_out := 'refused_before'")
  expect(code).toContain("security.provider_page_host_v1(v_prov, v_url) <> 'own' then v_out := 'not_own_host'")
  expect(code).toContain("public.svc_coverage_read_record(r.entity_id, 'read', nullif(ch->>'http', '')::int, 'direct'")
  expect(code).toContain("r.escalation_reason like 'The page we show carries the year%'")
  expect(code).toContain("'mode', 'link_year_rollover'")
  expect(code).toContain("begin w := security.link_rollover_tick_v1(); exception when others then")
})

test('s891 rule: candidate addresses, newest first, never an archived handbook as the held fallback', () => {
  expect(addressYear('https://handbook.latrobe.edu.au/courses/2023/PHDLJ')).toEqual({ year: 2023, at: 'segment' })
  expect(yearCandidates('https://handbook.latrobe.edu.au/courses/2023/PHDLJ', 2026).map(c => c.url)).toEqual([
    'https://handbook.latrobe.edu.au/courses/2027/PHDLJ', 'https://handbook.latrobe.edu.au/courses/2026/PHDLJ',
    'https://handbook.latrobe.edu.au/courses/2025/PHDLJ', 'https://handbook.latrobe.edu.au/courses/2023/PHDLJ'])
  expect(yearCandidates('https://programsandcourses.anu.edu.au/2025/program/VMIRS', 2026).map(c => c.year)).toEqual([2027, 2026, 2025])
  expect(yearCandidates('https://programsandcourses.anu.edu.au/2025/program/VMIRS', 2026).at(-1).held).toBe(true)
  expect(yearCandidates('https://www.example.edu.au/course-2022/', 2026)[0].url).toBe('https://www.example.edu.au/course-2027/')
  expect(yearCandidates('https://www.example.edu.au/course?year=2021&x=1', 2026)[0].url).toBe('https://www.example.edu.au/course?year=2027&x=1')
  const arch = yearCandidates('https://www.sydney.edu.au/handbooks/archive/2019/engineering_pg/x.shtml', 2026)
  expect(arch.some(c => c.held)).toBe(false)
  expect(yearCandidates('https://handbook.example.edu.au/courses/2027/X', 2026)).toEqual([])
  expect(yearCandidates('https://example.edu.au/courses/bachelor-of-arts', 2026)).toEqual([])
})

test('s891 rule: a page answers only on its own host, at its own year, with text and no "not found" words; identity is the exact code', () => {
  const base = { http: 200, requested: 'https://h.edu.au/courses/2027/X', finalUrl: 'https://h.edu.au/courses/2027/X', year: 2027, text: 'x'.repeat(2000), minChars: 1500, markers: ['page not found', 'not offered in {year}'], jsonIdentity: false }
  expect(pageAnswer(base)).toEqual({ ok: true, reason: 'live' })
  expect(pageAnswer({ ...base, http: 404 }).reason).toBe('http_404')
  expect(pageAnswer({ ...base, finalUrl: 'https://other.edu.au/courses/2027/X' }).reason).toBe('moved_to_another_host')
  expect(pageAnswer({ ...base, finalUrl: 'https://h.edu.au/' }).reason).toBe('moved_to_a_general_page')
  expect(pageAnswer({ ...base, finalUrl: 'https://h.edu.au/search?q=X' }).reason).toBe('moved_to_a_general_page')
  expect(pageAnswer({ ...base, finalUrl: 'https://h.edu.au/courses/2026/X' }).reason).toBe('moved_to_another_year')
  expect(pageAnswer({ ...base, text: 'This course is not offered in 2027. ' + 'x'.repeat(2000) }).reason).toBe('page_says: not offered in {year}')
  expect(pageAnswer({ ...base, text: 'short' }).reason).toBe('page_needs_a_browser')
  expect(pageAnswer({ ...base, text: 'short', jsonIdentity: true }).ok).toBe(true)
  expect(strongIdentity('cricos_code', 'AU')).toBe(true)
  expect(strongIdentity('adapter_code', 'AU')).toBe(true)
  expect(strongIdentity('exact_title', 'AU')).toBe(false)
  expect(strongIdentity('cricos_code', 'NZ')).toBe(false)
  expect(strongIdentity('nzqa_code', 'NZ')).toBe(true)
})
