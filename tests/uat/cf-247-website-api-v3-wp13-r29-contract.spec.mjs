// Guards: Website API v3 build brief WP-1.3, R29 scholarship linked-course paging (REQ-73), Decision 277: v3 only; no paging asked answers as v2 (first 200)
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261113200000_cf247_website_api_v3_r29_course_paging.sql', 'utf8')
const v3 = fs.readFileSync('supabase/functions/website-api-v3/index.ts', 'utf8')

test('scholarship takes courses_page and courses_page_size (1-200) and answers a page in a stable order', () => {
  expect(v3).toContain('fn = "website_v3_scholarship"; args = { p_scholarship_id: s, p_courses: { page: body.courses_page ?? null, page_size: body.courses_page_size ?? null } };')
  expect(m).toContain('create or replace function public.website_v3_scholarship(p_scholarship_id text, p_courses jsonb)')
  expect(m).toContain("if v_page < 1 or v_size < 1 or v_size > 200 then")
  expect(m).toContain("using errcode = '22023'")
  expect(m).toContain('order by d.course_title, d.course_stable_key')
  expect(m).toContain('offset (v_page - 1) * v_size limit v_size')
  expect(m).toContain("'linked_courses_truncated', v_page * v_size < v_total")
  expect(m).toContain("'linked_courses_total', v_total, 'linked_courses_page', v_page, 'linked_courses_page_size', v_size")
})

test('no paging asked keeps the v2 list and flag; R24 kept; not found passes through; the old form calls the new one', () => {
  expect(m).toContain('declare v jsonb := public.website_v2_scholarship(p_scholarship_id);')
  expect(m).toContain("v := jsonb_set(v, '{item}', public.website_v3_scholarship_item(v->'item'));")
  expect(m).toContain("if jsonb_typeof(v->'item') is distinct from 'object' then return v; end if;")
  expect(m).toContain('select public.website_v3_scholarship(p_scholarship_id, null::jsonb)')
  expect(m).toMatch(/md5\(pg_get_functiondef\('public\.website_v3_scholarship\(text\)'::regprocedure\)\) <> '[0-9a-f]{32}'/)
})
