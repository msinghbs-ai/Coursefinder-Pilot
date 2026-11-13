// Guards: Admin destination data design v1.1 §4 M1 (RM1A-1, O29): CRICOS recognition[] on Website API v3 course detail only, held reasons, Admin Recognition card and Data Delivery panel; Decision 277: v3 only, Zoho v3 and v2 untouched
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261113333000_cf247_rm1a_course_recognition_v3.sql', 'utf8')
const dd = fs.readFileSync('src/DataDelivery.jsx', 'utf8')
const card = fs.readFileSync('src/CourseRecognition.jsx', 'utf8')
const summary = fs.readFileSync('src/DetailSummary.jsx', 'utf8')

test('recognition[]: active CRICOS with an active public source and no past end date; withdrawn gives nothing; held reasons named', () => {
  expect(m).toContain("r.scheme = 'cricos' and r.status = 'active'")
  expect(m).toContain("filter (where r.id is not null and s.url is not null and (r.valid_to is null or r.valid_to > current_date))")
  expect(m).toContain("then 'registration_dates_inconsistent'")
  expect(m).toContain("then 'registration_source_missing'")
  for (const k of ["'scheme', 'CRICOS'", "'status', 'registered'", "'source_url', s.url", "'evidence_date'", "'checked_on'"]) expect(m).toContain(k)
  // NZQA is not released by this change (provider-grain evidence)
  expect(m).not.toMatch(/'scheme', 'NZQ/)
})

test('only items v2 returned are decorated; [] when nothing is admitted; both website_v3_course forms, md5-guarded; R28 and O20 kept', () => {
  expect(m).toContain("lower(d.course_stable_key) = lower(p_item->>'course_id')")
  expect(m).toContain("jsonb_build_object('recognition', coalesce(v_rec, '[]'::jsonb))")
  expect(m.match(/v := jsonb_set\(v, '\{item\}', security\.course_recognition_item_v1\(v->'item'\)\);/g)).toHaveLength(2)
  expect(m.match(/public\.website_v3_course_item_r28\(v->'item'\)/g)).toHaveLength(2)
  expect(m).toContain("m.country_code = v_cc and m.quote = r->>'quote'")
  for (const k of ['public.website_v3_course(text)', 'public.website_v3_course(text,text)'])
    expect(m).toMatch(new RegExp(`'${k.replace(/[()]/g, '\\$&')}', '[0-9a-f]{32}'`))
})

test('scope: no v2, api.* or Zoho v3 object is replaced; new functions are not granted to anon', () => {
  expect(m).not.toMatch(/create or replace function (public\.website_v2_|public\.zoho_|api\.)/i)
  for (const f of ['security.course_recognition_v1(uuid[])', 'security.course_recognition_item_v1(jsonb)', 'security.course_recognition_delivery_v1()'])
    expect(m).toContain(`revoke all on function ${f} from public, anon, authenticated;`)
  expect(m).toContain('revoke all on function public.admin_course_recognition_delivery() from public, anon;')
  expect(m).toContain('revoke all on function public.admin_course_recognition_read(uuid) from public, anon;')
  expect(m).toContain("coalesce(security.current_role_rank(), 0) < 3")
})

test('Admin: Data Delivery shows the recognition panel; the course summary shows the Recognition card with registrations and held reason', () => {
  expect(dd).toContain("rpc('admin_course_recognition_delivery',{})")
  expect(dd).toContain('<RecognitionDelivery rpc={rpc}/>')
  expect(dd).toContain('data-dd-recognition')
  expect(card).toContain("'admin_course_recognition_read',{p_course_id:courseId}")
  expect(card).toContain('registration_dates_inconsistent')
  expect(summary).toContain('<CourseRecognition courseId={data.id}/>')
})
