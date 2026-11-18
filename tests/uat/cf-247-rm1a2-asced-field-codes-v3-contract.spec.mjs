// Guards: Admin destination data design v1.3 (RM1A-2, O28): field_of_study_codes[] on Website v3 and Zoho v3 course detail, read only from catalogue.course_field_observations (CRICOS register evidence); Platform Admin 16 Nov 2026 22:30: Zoho v3 additive fields merge on green; Decision 277
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations-archive/20261116200000_cf247_rm1a2_asced_field_codes_v3.sql', 'utf8')
const dd = fs.readFileSync('src/DataDelivery.jsx', 'utf8')
const card = fs.readFileSync('src/CourseRecognition.jsx', 'utf8')

test('codes come only from current register observations: printed 4-digit code, same ASCED field, active public source, stored evidence, CRICOS registration', () => {
  expect(m).toContain("o.status = 'current' and o.source_field_code ~ '^[0-9]{4}$'")
  expect(m).toContain("f.code = 'asced-' || o.source_field_code and f.status = 'active'")
  expect(m).toContain("r.course_id = u.id and r.scheme = 'cricos'")
  expect(m).toContain('filter (where o.id is not null and f.id is not null and s.url is not null and e.id is not null')
  expect(m).toContain("and (not o.is_primary or o.field_id = c.primary_field_id)")
  expect(m).toContain("then 'primary_field_superseded'")
  for (const k of ["'scheme', 'ASCED'", "'level', 'narrow'", "'rank', case when o.is_primary then 1 else 2 end", "'source_url', s.url", "'evidence_date'"]) expect(m).toContain(k)
})

test('no new table and nothing inferred: no create table, no CIP or NZSCED scheme, courses.primary_field_id is only compared, study_area untouched', () => {
  expect(m).not.toMatch(/create table/i)
  expect(m).not.toMatch(/'scheme', '(CIP|NZSCED)'/)
  expect(m.split('\n').filter(l => !l.startsWith('--')).join('\n')).not.toContain('study_area')
  expect(m).not.toMatch(/update catalogue\.|insert into catalogue\./i)
})

test('one item function adds recognition[] and field_of_study_codes[] to Website v3 course (both forms) and Zoho v3 course; md5-guarded; R28, O20 and entry kept', () => {
  expect(m).toContain("jsonb_build_object('recognition', coalesce(v_rec, '[]'::jsonb), 'field_of_study_codes', coalesce(v_codes, '[]'::jsonb))")
  expect(m.match(/v := jsonb_set\(v, '\{item\}', security\.course_roadmap_item_v1\(v->'item'\)\);/g)).toHaveLength(3)
  expect(m.match(/public\.website_v3_course_item_r28\(v->'item'\)/g)).toHaveLength(3)
  expect(m).toContain("m.country_code = v_cc and m.quote = r->>'quote'")
  expect(m).toContain("v := jsonb_set(v, '{item,entry}', w #> '{item,entry}')")
  for (const k of ['public.website_v3_course(text)', 'public.website_v3_course(text,text)', 'public.zoho_v3_course(text,text)'])
    expect(m).toMatch(new RegExp(`'${k.replace(/[()]/g, '\\$&')}', '[0-9a-f]{32}'`))
})

test('scope and housekeeping: no v2 or api.* object replaced; Zoho search, courses, sync and export untouched; old item function marked retiring', () => {
  expect(m).not.toMatch(/create or replace function (public\.website_v2_|public\.zoho_v2_|api\.|public\.zoho_v3_(courses|sync|export|course_search))/i)
  for (const f of ['security.course_field_codes_v1(uuid[])', 'security.course_roadmap_item_v1(jsonb)', 'security.course_field_codes_delivery_v1()'])
    expect(m).toContain(`revoke all on function ${f} from public, anon, authenticated;`)
  expect(m).toMatch(/set status = 'retiring'[\s\S]*name = 'security\.course_recognition_item_v1'/)
})

test('Admin: the course Recognition card and the Data Delivery panel show the field codes', () => {
  expect(card).toContain('data-recognition-field-codes')
  expect(card).toContain('field_codes_held_reason')
  expect(dd).toContain('k="fc_au_served"')
  expect(m).toContain("'field_codes', security.course_field_codes_delivery_v1()")
})
