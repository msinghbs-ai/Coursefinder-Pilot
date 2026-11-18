// Guards: Admin destination data design v1.4 (RM1A-3, O29; F-DISC.01/.04): a code the latest planned register edition carries as a new or changed item is listed, so its registration is not end-dated; departed codes stay ended; no date is invented
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations-archive/20261117010000_cf247_rm1a3_register_end_dates_pending.sql', 'utf8')
const code = m.split('\n').filter(l => !l.startsWith('--')).join('\n')

test('pending edition items count as listed in the guard, the ended step, the restored step and both provider steps', () => {
  expect(code).toContain("i->>2 in ('new', 'changed')")
  expect(code).toContain('s.seen_at >= v_plan.created_at or s.record_key = any(v_pending)')
  expect(code).toContain('and upper(cr.registration_code) <> all(v_pending)')
  expect(code).toMatch(/set valid_to = null\s+where lower\(cr\.scheme\) = v_scheme and cr\.valid_to is not null\s+and \(upper\(cr\.registration_code\) = any\(v_pending\)/)
  expect(code.match(/upper\(cr\.registration_code\) = any\(v_pending\)/g).length).toBeGreaterThanOrEqual(3)
})

test('nothing is invented or removed: the only date written is the last-listed date; the min-share guard and the on/off setting stay; no status is set on a course registration', () => {
  expect(code).toContain("security.pipeline_num_v1('layer1.register_end_dates_min_share', 0.9)")
  expect(code).toContain("security.pipeline_num_v1('layer1.register_end_dates_on', 1) < 1")
  expect(code).toContain('update catalogue.course_registrations cr set valid_to = g.d from gone g')
  expect(code).not.toMatch(/update catalogue\.course_registrations[^;]*set status/i)
  expect(code).not.toMatch(/delete from|drop /i)
})

test('md5-guarded replacements; run once as the job runs it; held reason renamed; recognition[] rule unchanged', () => {
  for (const k of ['security.layer1_register_end_dates_v1(uuid)', 'security.course_recognition_v1(uuid[])', 'security.course_recognition_delivery_v1()'])
    expect(m).toMatch(new RegExp(`'${k.replace(/[()\[\]]/g, '\\$&')}', '[0-9a-f]{32}'`))
  expect(code.trim().endsWith('select security.layer1_register_end_dates_v1();')).toBe(true)
  expect(code).toContain("then 'not_on_latest_register_edition'")
  expect(code).toContain("filter (where r.id is not null and s.url is not null and (r.valid_to is null or r.valid_to > current_date))")
  expect(code).not.toMatch(/create or replace function (public\.website_|public\.zoho_|api\.)/i)
})

test('Admin wording: the course card and Data Delivery say what the hold is', () => {
  expect(fs.readFileSync('src/CourseRecognition.jsx', 'utf8')).toContain('not_on_latest_register_edition')
  expect(fs.readFileSync('src/DataDelivery.jsx', 'utf8')).toContain('not on the latest CRICOS edition')
})
