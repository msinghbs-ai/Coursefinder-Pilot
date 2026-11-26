// Guards: Atlas brief 26 Nov 2026 22:19 AEDT (S1-Data-Gaps), Platform Admin approvals of S1-DG-2 option B and S1-DG-3 option A: the deterministic intake sweep gets its own provider-type scope (no AI fee reader widening) and the 23 unlocked held addresses go to the Course page needed list; nothing deleted, no lock touched.
// s1280: fid.provider_types is new and fid_det_batch_v1 reads it; fees.provider_types is not written; the 23 courses are added through the existing function with every gate repeated.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261130024500_cf247_s1280_s1_data_gaps_det_scope_and_url_worklist.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1280: the sweep gets its own scope setting and reads it; the AI fee reader scope is never written', () => {
  expect(code).toContain("'fid.provider_types'")
  expect(code).toContain('"private_vet", "school", "wananga"')
  expect(code).toContain("s.key = 'fid.provider_types'")
  expect(code).toContain('23f4c2946d9ee8e0cc6778f67b44e657')
  expect(code).toContain('1685019e64b06064f6b50165d5b32a49')
  expect(code).not.toMatch(/update pipeline\.platform_toolset_settings[^;]*fees\.provider_types/i)
  expect(code).toContain('fees.provider_types (the AI fee reader scope) changed')
})

test('s1280: the 23 courses are added through the existing function with the gates repeated, and nothing is deleted or re-pointed', () => {
  expect(code).toContain('security.course_page_needed_add_v1(')
  for (const g of ["k.field like 'link:%'", "'official_url', 'course_url', 'all'", "not exists (select 1 from pipeline.course_page_needed n", "i.field_code = 'official_course_url' and i.status = 'pending'", "count guard: % of % courses still qualify"]) expect(code).toContain(g)
  expect((MIG.match(/'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'/g) || []).length).toBe(23)
  expect(code).not.toMatch(/cron\.schedule|cron\.alter_job|cron\.unschedule|ai_service_routes|create table |\bdelete from\b|truncate |website_v2_|update catalogue\.|insert into catalogue\./i)
  expect(MIG.split('\n').filter((l) => /^(drop|delete|truncate)\b/i.test(l))).toEqual([])
})

test('s1280: cron, locks, links, intakes, the consumer API and the list size are checked after', () => {
  for (const s of ['post-check: active cron jobs changed', 'post-check: manual locks changed', 'post-check: course links changed', 'post-check: official addresses changed', 'post-check: intake rows changed', 'post-check: the list did not grow by exactly 23', 'post-check: the consumer API drifted', 'post-check: a course with a manual address lock was added to the list']) expect(MIG).toContain(s)
})
