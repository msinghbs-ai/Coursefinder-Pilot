// Guards: Website API v3 build brief WP-1.6 (O22, REQ-28): search filter has_academic_entry, optionally narrowed by edu_country, Decision 277: v3 only; paging, totals and items as v2
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261113230000_cf247_website_api_v3_academic_entry_filter.sql', 'utf8')

test('the v3 search core is the live v2 search (md5-guarded) with the filter added, every edit applied exactly once', () => {
  expect(m).toContain("select pg_temp.copy_with_edits('public.website_v2_course_search(jsonb,integer,integer,text)', 'dcefed12a1e879aa1cc0f69e72d91428', array[")
  expect(m).toContain("if v_c <> 1 then raise exception '%: copy edit % must apply exactly once (found %)'")
  expect(m).toContain('$n$public.website_v3_course_search_core($n$')
  expect(m).toContain("|| case when nullif(f->>'has_academic_entry','') is not null then array['edu_country'] else array[]::text[] end;")
  expect(m).toContain("from catalogue.provider_entry_matrix em where em.provider_id = d.provider_id and em.status = 'active'")
  expect(m).toContain("and exists (select 1 from catalogue.course_entry_requirements er where er.course_id = d.course_id and er.status = 'active' and er.min_entry_score is not null)))")
  expect(m).toContain("= lower(f->>'has_academic_entry')::boolean)")
  expect(m).toContain("raise exception 'INVALID_INPUT: has_academic_entry must be true or false' using errcode='22023'")
})

test('v3 search calls the core and keeps R28 and the excerpt; without the new filters it answers as v2', () => {
  expect(m).toContain('declare v jsonb := public.website_v3_course_search_core(p_filters, p_page, p_page_size, p_sort);')
  expect(m).toContain('jsonb_agg(public.website_v3_course_search_item(x) order by o)')
  expect(m).toContain("'263f5ac682ed8ae297b8586581abebda'")
  expect(m).toContain("then raise exception 'post-check: without the new filters the v3 search must answer as v2'")
})
