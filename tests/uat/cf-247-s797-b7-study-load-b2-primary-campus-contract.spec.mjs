// Guards: Platform Admin 20 Nov 2026 05:42 AEDT (chat S1-Build, s797; decisions B7 and B2): AU CRICOS courses open to international students and holding no study load are recorded full_time from the register (source register, no evidence id), a reading always replaces that rule value, and the primary campus is set from the register head office, then the most active courses, with ties left for a person.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261120093000_cf247_s797_b7_study_load_b2_primary_campus.sql', 'utf8')
const body = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const RULE = "(c.study_load_source = 'register' and c.study_load_evidence_id is null)"

test('B7 fills only empty loads of AU CRICOS courses open to international students, skips locks, and marks the value as a rule (no evidence id)', () => {
  expect(body).toContain("join ref.countries k on k.id = p.country_id and k.iso_alpha2 = 'AU'")
  expect(body).toContain("where c.lifecycle_status = 'active' and c.study_load is null")
  expect(body).toContain('and c.open_to_international is true')
  expect(body).toContain("and exists (select 1 from catalogue.provider_registrations r where r.provider_id = p.id and r.registration_scheme = 'cricos')")
  expect(body).toMatch(/not exists \(select 1 from pipeline\.manual_locks l where l\.entity = 'course' and l\.entity_id = c\.id\s+and l\.field in \('study_load', 'study_load_source', 'study_load_evidence_id'\)\)/)
  expect(body).toContain("set study_load = 'full_time', study_load_source = 'register', study_load_evidence_id = null")
  expect(body).toContain('where c.id in (select x.id from security.course_study_load_register_rule_rows_v1() x) and c.study_load is null;')
})

test('a reading always replaces a rule value: the page writer, the boost lane, a person and the register loader', () => {
  for (const [sig, md5] of [
    ['security.course_study_load_stage1_v1(boolean)', '866bac4e020c8110a690afd5112e72f2'],
    ['security.boost_study_load_review_feed_v1()', '1b533e4dd4591a7910f7c6edc7b6fd08'],
    ['security.layer4_boost_study_load_inbox_decide_v1(text,text,text,text)', '58344e5618e9ac2ae8a88e852a9b65cf'],
    ['security.boost_extract_claim_v1(integer)', 'a80ff8e9ce2989abe8f786b0748c9357'],
    ['security.boost_promote_v1(text,boolean,timestamp with time zone)', 'fa4e3a8671577e2674e652fc5012f497'],
    ['public.svc_page_text_next_v1(integer)', '04f3286ab30c4d7cd49ed8e401ed83cb'],
    ['public.svc_layer1_apply_baseline_records_v1(text,text,uuid,uuid,text,jsonb)', '784027d2f339d7aebc00b2629be2d197'],
  ]) expect(body).toContain(`select pg_temp.cf_edit_def('${sig}'::regprocedure, '${md5}',`)
  expect(body.split(RULE).length - 1).toBeGreaterThanOrEqual(5)
  expect(body).toContain("(study_load is null or (study_load_source = 'register' and study_load_evidence_id is null))")
})

test('B2 keeps the register first, then the most active courses, never a second primary, ties and locks left for a person', () => {
  expect(body).toContain('v_reg := security.campus_primary_apply_v1(p_apply);')
  expect(body).toContain("set is_primary = true, primary_basis = 'highest_course_count'")
  expect(body).toContain('r.rk = 1 and r.top = 1')
  expect(body).toContain("l.entity = 'campus' and l.field in ('is_primary', 'primary_basis')")
  expect(body).toContain("raise exception 'post-check: % providers now have more than one primary campus'")
  expect(body).not.toMatch(/^\s*(delete|drop|truncate)\b/im)
  expect(body).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_/)
})
