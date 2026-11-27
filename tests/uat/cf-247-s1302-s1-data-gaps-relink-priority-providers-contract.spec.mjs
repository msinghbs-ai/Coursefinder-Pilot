// Guards: SS-Programme-Control 27 Nov 2026 12:00 AEDT (International Course Source Integrity, Admin #1271, S1-DG-5 option A): parked courses at the four priority providers go to the existing course relink route; no link, value, lock, job or setting is written.
// s1302: one counted update of pipeline.source_proof_requests (held / no_route to relink / queued), every guard checked after.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261130134500_cf247_s1302_s1_data_gaps_relink_priority_providers.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1302: only held / no_route requests at the four priority providers move to relink, with a counted cohort', () => {
  for (const id of ['349da14b-66b1-4c57-9dfd-6f9c36412432', '1719c3ba-1ddf-483e-935e-c750124ba99c', '6f5cb7f7-7c70-4c06-970f-f368c3a786e2', '5fac5555-18f9-4bc7-91e4-e1466f8e33e3']) expect(code).toContain(id)
  expect(code).toContain("s.state = 'held' and s.route = 'no_route'")
  expect(code).toContain("route = 'relink', state = 'queued'")
  expect(code).toContain("c.lifecycle_status = 'active'")
  expect(code).toContain('v_n < 150 or v_n > 300')
  expect(code).toContain('previous')
})

test('s1302: nothing but the request rows is written (no link, page, value, lock, job, setting or consumer object)', () => {
  expect(code).not.toMatch(/cron\.schedule|cron\.alter_job|cron\.unschedule|platform_toolset_settings|create table |\bdelete from\b|truncate |website_v2_|update catalogue\.|insert into catalogue\.|update pipeline\.(coverage_course_pages|manual_locks)|insert into pipeline\.manual_locks/i)
  expect((code.match(/\bupdate pipeline\./g) || []).length).toBe(1)
  expect(MIG.split('\n').filter((l) => /^(drop|delete|truncate)\b/i.test(l))).toEqual([])
  expect(MIG).toContain('-- Replaces: nothing')
  expect(MIG).toContain('Retires: nothing')
})

test('s1302: the consumer API, cron, locks, links, pages and request totals are checked after', () => {
  for (const s of ['post-check: the consumer API moved', 'post-check: the number of cron jobs changed', 'post-check: manual locks changed', 'post-check: course links changed', 'post-check: official links changed', 'post-check: course pages changed', 'post-check: a request was added or removed', 'still held for want of a route', 'not every cohort request is queued for relink']) expect(code).toContain(s)
})
