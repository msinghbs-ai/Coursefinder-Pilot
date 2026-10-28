// Guards: CF-247 Track C Step B decision 28 Oct 2026 section 7 (approval Platform Admin 25 Oct 2026 14:36/14:50, decision 7; plan ENTRY-REQUIREMENTS-IMPLEMENTATION.md 2.4): the consumer entry fields are additive keys on the EXISTING course and provider payloads (entry, entry_matrix) with an optional edu_country; no existing key renamed, removed or retyped; no separate AER function; the change is approved in its migration and re-takes the baseline (G3 itself is guarded by s57)
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261028005000_cf247_entry_step_b_consumer_api.sql', 'utf8')
const code = m.split('\n').filter(l => !/^\s*--/.test(l)).join('\n')
const edge = fs.readFileSync('supabase/functions/website-api-v2/index.ts', 'utf8')

test('approved, md5-guarded edits that add one key to each existing payload and keep every other key', () => {
  expect(m).toMatch(/^-- Consumer API change approved: Platform Admin, 25 Oct 2026 14:36 and 14:50/m)
  expect(code).toContain("select pg_temp.edit_n('public.website_v2_course(text)', 'ad9ba3889ac6a1a7ed0b68ef08c8b507'")
  expect(code).toContain("select pg_temp.edit_n('public.website_v2_provider(text)', '2411c7e4c30b0a04fcc9d159764327da'")
  expect(code).toContain("    'other_matches', greatest(v_matches - 1, 0),\n    'entry', security.entry_course_payload_v1(v_id, null));")
  expect(code).toContain("    'rankings', public.website_v2_provider_rankings(v_pid),\n    'entry_matrix', security.entry_matrix_payload_v1(v_pid, null),")
  expect(code).not.toMatch(/\b(drop|rename|alter\s+column)\b/i)
  expect(code).toContain("select security.consumer_api_rebaseline_v1('Track C Step B (28 Oct 2026)")
})

test('the approved shapes: entry {min_score, min_score_basis, benchmark_band, prerequisites, selection_tasks, requirements_note, resolution}; entry_matrix rows', () => {
  for (const k of ["'min_score'", "'min_score_basis'", "'benchmark_band'", "'prerequisites'", "'selection_tasks'", "'requirements_note'", "'resolution'"]) expect(code).toContain(k)
  for (const k of ["'country'", "'study_level'", "'qualification'", "'min_grade'", "'scale'", "'band'", "'course_code'", "'conditions'", "'as_at'"]) expect(code).toContain(k)
  expect(code).toContain("'scale', case when m.min_grade is null then 'none' else m.grade_scale end")  // case by case: min_grade null, scale none (decision 10)
  expect(code).toContain("where m.provider_id = p_provider and m.status = 'active'")
  expect(code).toContain("from catalogue.course_entry_requirements x where x.course_id = p_course and x.status = 'active'")
  expect(code).toContain("'resolution', case when p_country is null then null else security.entry_resolve_v1(p_course, p_country) end")
})

test('edu_country: the same two payload functions with one more argument; validated; passed by website-api-v2 only for course and provider', () => {
  expect(code).toContain('create or replace function public.website_v2_course(p_identifier text, p_edu_country text) returns jsonb')
  expect(code).toContain('create or replace function public.website_v2_provider(p_provider_id text, p_edu_country text) returns jsonb')
  expect((code.match(/raise exception 'INVALID_INPUT: edu_country must be a known ISO 3166 alpha-2 country code'/g) || []).length).toBe(2)
  expect(code).not.toMatch(/create or replace function (public|api)\.(website_v2_entry|website_v2_resolve|entry_)/i)  // no separate AER API function
  expect(edge).toContain('fn = "website_v2_course"; args = ec ? { p_identifier: c, p_edu_country: ec } : { p_identifier: c }; break;')
  expect(edge).toContain('fn = "website_v2_provider"; args = ec ? { p_provider_id: p, p_edu_country: ec } : { p_provider_id: p }; break;')
  expect(edge).toContain('"edu_country must be a two-letter country code"')
  expect(edge).toContain('case "search": fn = "website_v2_course_search"; args = { p_filters: filters, p_page: page, p_page_size: pageSize, p_sort: sort }; break;')  // search unchanged
})
