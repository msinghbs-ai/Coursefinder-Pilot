// Guards: Website API v3 build brief WP-1.4 (R31 scholarships page link and last reviewed date per provider, REQ-46) and WP-1.7 (O26 description excerpt on search items, REQ-61), Decision 277: v3 only
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261113210000_cf247_website_api_v3_r31_excerpt.sql', 'utf8')

test('R31: provider scholarships_page_url and scholarships_last_reviewed_at from the listing page the platform reads; R23 kept', () => {
  expect(m).toContain("where lp.provider_id = v_provider and lp.active and lp.status = 'read' and lp.read_at is not null")
  expect(m).toContain('order by lp.read_at desc, lp.id limit 1;')
  expect(m).toContain("jsonb_build_object('scholarships_page_url', v_page.url, 'scholarships_last_reviewed_at', v_page.read_at)")
  expect(m).toContain("'campus_id', k.stable_key, 'campus_name', nullif(btrim(k.name), ''), 'course_count', coalesce(n.n, 0))")
  expect(m).toContain("md5(pg_get_functiondef('public.website_v3_provider_item(jsonb)'::regprocedure)) <> '0e81bf4d1b3984a42222936d478c6606'")
})

test('O26: search items carry description_excerpt, the first 240 characters at a whole word; R28 kept', () => {
  expect(m).toContain('declare v jsonb := public.website_v3_course_item_r28(p_item); v_desc text;')
  expect(m).toContain("if v_desc is not null and length(v_desc) > 240 then")
  expect(m).toContain("regexp_replace(left(v_desc, 240), '\\s+\\S*$', '')")
  expect(m).toContain('jsonb_agg(public.website_v3_course_search_item(x) order by o)')
  expect(m).toContain("md5(pg_get_functiondef('public.website_v3_course_search(jsonb,integer,integer,text)'::regprocedure)) <> '38f89a7e4d78b8b86724060accced2e7'")
})
