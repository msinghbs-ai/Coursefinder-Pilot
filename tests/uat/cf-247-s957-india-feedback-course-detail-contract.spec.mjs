// Guards: CF-247 s957 (Platform Admin 21 Nov 2026 21:15, Lane 1 item 2; India team review of 20 Nov 2026: REQ-93, REQ-96, REQ-98, REQ-104): Has scholarship agrees with the course detail and the website; the course detail links to the institution and the course page; a course with no entry rule reads the university's requirement for a chosen student country; the chosen state's campuses come first
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { citySummary } from '../../src/catalogue-columns.js'

const src = f => fs.readFileSync(`src/${f}`, 'utf8')
const MIG = fs.readFileSync('supabase/migrations/20261122060000_cf247_s957_course_scholarship_filter_provider_website.sql', 'utf8')

test('REQ-96: every Course catalogue read takes Has scholarship from the course search record, md5-guarded', () => {
  for (const [fn, md5] of [['public.ui_courses_decision_page(', '5e8e9f86c3e590f30fddb6b4ef118635'], ['security.admin_course_page_fast_base(jsonb)', 'aa88cb2bc090a1670cd7fd423e8cf0ca'], ['security.admin_course_page_unfiltered_fast(jsonb)', '5db669272a3fa612b1268ef8502a9b7c']]) {
    expect(MIG).toContain(`select pg_temp.edit_re('${fn}`)
    expect(MIG).toContain(`'${md5}'`)
  }
  expect(MIG).toContain('coalesce((select sd.has_scholarship from search.course_documents sd where sd.course_id=c.id), false)=v_has_scholarship')
  expect(MIG).toContain("'post-check: a catalogue page still counts scholarship scopes'")
  const body = MIG.split('\n').filter(l => !l.trimStart().startsWith('--')).join('\n')
  expect(body).not.toMatch(/\$n\$[^$]*--/)   // no inline comment inside a replacement (it would swallow the rest of a one-line definition)
  expect(body).not.toMatch(/\bdrop\s+(table|function|view)\b|\bdelete\s+from\b|cron\.schedule\(/i)
})

test('REQ-98: the course detail carries provider_website and shows both links at the top', () => {
  expect(MIG).toContain("jsonb_build_object('provider_website',security.course_provider_website_v1(nullif(v_result->>'provider_id','')::uuid))")
  expect(MIG).toContain('language sql stable security definer set search_path = \'\' as $f$')
  expect(MIG).toContain('grant execute on function security.course_provider_website_v1(uuid) to authenticated, service_role;')
  const d = src('DetailSummary.jsx')
  expect(d).toContain('data-course-links')
  expect(d).toContain('data-course-link="institution">Institution website')
  expect(d).toContain('data-course-link="course">Course page')
})

test('REQ-93: a course with no entry rule of its own reads the university requirement for a chosen student country', () => {
  const c = src('CorrelatedBlade.jsx')
  expect(c).toContain('<UniversityEntryForCountry providerId={providerId}/>')
  expect(c).toContain("rpc('admin_aer',{p_action:'matrix_list',p_args:{provider_id:providerId,scope:'university',status:'active',country:cc,page_size:5}})")
  expect(c).toContain('orderAerCountries(opts.data?.countries||[])')
  expect(c).toContain('aria-label="Student\'s education country"')
})

test('REQ-104: with a state chosen, its campuses come first', () => {
  const cities = [{ city: 'Adelaide', subdivision_code: 'AU-SA' }, { city: 'Melbourne', subdivision_code: 'AU-VIC' }]
  expect(citySummary(cities, 'AU-VIC').short).toBe('Melbourne (VIC) +1')
  expect(citySummary(cities).short).toBe('Adelaide (SA) +1')
  expect(src('mature-main.jsx')).toContain("prefer:filters.subdivision||''})")
})
