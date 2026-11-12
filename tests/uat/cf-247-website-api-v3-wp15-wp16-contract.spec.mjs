// Guards: Website API v3 build brief WP-1.5 (O20 quote and source_url on entry rows) and WP-1.6 (O22 has_academic_entry and edu_country on search), Decision 277: built in v3 only, v2 only read
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261113220000_cf247_website_api_v3_entry_source_academic_filter.sql', 'utf8')
const held = fs.readFileSync('supabase/held/website_api_v3_entry_source_forward_recovery.sql', 'utf8')

test('O20: the v3 matrix and resolution are the v1 bodies plus the source keys, made by md5-guarded named edits', () => {
  expect(m).toContain("select pg_temp.v3_edit('security.entry_matrix_payload_v1(uuid,text)', '5f7eb75596fd2758871b1df71b859109'")
  expect(m).toContain("'as_at', m.as_at, 'quote', m.quote, 'source_url', m.source_url, /* CF-247 D5")
  expect(m).toContain("select pg_temp.v3_edit('security.entry_resolve_v1(uuid,text)', '69bbc05f650191954a22af09c0c85c74'")
  expect(m).toContain("'quote', r.quote, 'source_url', r.source_url, 'as_at', r.as_at, 'case_by_case'")
  expect(m).toContain("'quote', m.quote, 'source_url', m.source_url, 'as_at', m.as_at, 'edition'")
  // an edit that does not match exactly once, or a different live definition, stops the migration
  expect(m).toContain("raise exception '%: edit % must match exactly once'")
  expect(m).toContain("raise exception 'live % differs from the definition this change edits (md5 %)'")
})

test('O22: has_academic_entry is one rule for the filter and the item; edu_country narrows it and an unknown code is refused', () => {
  expect(m).toContain("r.course_id = p_course and r.status = 'active' and r.audience in ('international', 'all')")
  expect(m).toContain('(p_country is null or r.country_id is null or k.iso_alpha2 = p_country)')
  expect(m).toContain("m.provider_id = p_provider and m.status = 'active' and (m.course_id is null or m.course_id = p_course)")
  expect(m).toContain("select pg_temp.v3_edit('public.website_v2_course_search(jsonb,integer,integer,text)', 'dcefed12a1e879aa1cc0f69e72d91428'")
  expect(m).toContain("'changed_since','institution_types','has_academic_entry','edu_country'];")
  expect(m).toContain("and (not coalesce((f->>'has_academic_entry')::boolean,false) or security.course_has_academic_entry_v3(d.course_id, d.provider_id, v_edu))")
  expect(m).toContain("raise exception 'INVALID_INPUT: edu_country must be a known ISO 3166 alpha-2 country code'")
  expect(m).toContain("jsonb_build_object('has_academic_entry', security.course_has_academic_entry_v3(v_course, v_provider, p_edu_country))")
})

test('only v3 definitions are made or edited; nothing in v2 is created, altered or dropped; the held recovery reverses the four edits', () => {
  // the only statements that name a v2 or v1 function read its definition to make the v3 copy under a new name
  expect(m).not.toMatch(/create or replace function (public\.website_v2_|api\.|security\.entry_(resolve|matrix_payload)_v1)/i)
  expect(m).not.toMatch(/\b(drop|alter|delete|truncate)\b/i)
  for (const from of ['FUNCTION security.entry_matrix_payload_v1(', 'FUNCTION security.entry_resolve_v1(', 'FUNCTION public.website_v2_course_search(']) expect(m).toContain(`array['${from}'`)
  for (const to of ['FUNCTION security.entry_matrix_payload_v3(', 'FUNCTION security.entry_resolve_v3(', 'FUNCTION public.website_v3_course_search_core(']) expect(m).toContain(`array['${to}'`)
  for (const [sig, before, after] of [
    ['public.website_v3_course_search(jsonb,integer,integer,text)', '263f5ac682ed8ae297b8586581abebda', '9d9b5a19e68fd84755a05b3efc6de27a'],
    ['public.website_v3_course(text,text)', '7f56ec0e8fc16b05f8ff5fb15a2998dc', '7ac0239f26c0e1ebb3bd2466e5932aff'],
    ['public.website_v3_provider(text)', '87f7de23346bdd960fefc0ce5af92d9c', 'a24dfbce8997e88145a0ccbf90deaedf'],
    ['public.website_v3_provider(text,text)', 'daf3b4a4b89edc5d864fd2d4a5269b7e', '46a7e222f6d3758456d3929246301181']]) {
    expect(m).toContain(`select pg_temp.v3_edit('${sig}', '${before}'`)
    expect(held).toContain(`select pg_temp.v3_edit('${sig}', '${after}'`)
  }
  expect(m).toContain('-- Replaces: public.website_v3_course_search(jsonb,integer,integer,text)')
  expect(m).toContain('-- Retires: nothing.')
  // the edge function is not part of this change: filters pass through to the database unchanged
  const edge = fs.readFileSync('supabase/functions/website-api-v3/index.ts', 'utf8')
  expect(edge).toContain('case "search": fn = "website_v3_course_search"; args = { p_filters: filters, p_page: page, p_page_size: pageSize, p_sort: sort }; break;')
})
