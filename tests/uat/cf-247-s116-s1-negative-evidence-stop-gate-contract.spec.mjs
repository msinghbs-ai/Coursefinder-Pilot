// CF-247 S1 part 1 (v2.15.352): one negative-evidence predicate asked by every automatic binding path, one course-search stop gate.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261025002000_cf247_s1_negative_evidence_and_stop_gate.sql', 'utf8')

test('one predicate: rejections and blocks', () => {
  expect(m).toContain('create or replace function security.page_refused_v1(p_course uuid, p_url text) returns boolean')
  expect(m).toContain('from pipeline.page_rejections r where r.course_id = p_course and r.url = p_url')
  expect(m).toContain('from pipeline.course_page_blocks b where b.course_id = p_course and b.url = p_url')
})

test('every automatic binding path and both candidate readers ask it (plant-a-rejection proof in the dry run)', () => {
  for (const f of ['public.svc_course_link_search_record(uuid,integer,text[],text)', 'security.course_link_bind_v1(uuid,uuid,text,text)',
                   'security.coverage_bind_v2(uuid)', 'security.coverage_ai_match_prepare_v1(integer,integer)', 'public.svc_coverage_reidentify_next(integer,text)'])
    expect(m).toMatch(new RegExp(`pg_temp\\.edit_n\\('${f.replace(/[()[\]]/g, '\\$&')}', '[0-9a-f]{32}'`))
  expect(m).toContain("where not security.page_refused_v1(p_course_id, t.u)")
  expect(m).toContain('from _cb_best where not security.page_refused_v1(course_id, url)')
  expect(m).toContain('where not security.page_refused_v1(p_course_id, p_url)')
  expect(m).toContain('and not security.page_refused_v1(p.course_id, p.url)')
  expect(m).toContain('union select b.course_id, b.url from pipeline.course_page_blocks b join c using (course_id)')
})

test('one stop gate in its three callers; behaviour unchanged', () => {
  expect(m).toContain('create or replace function security.search_stop_gate_v1(p_provider uuid, p_course uuid default null, p_stopped boolean default null, p_person boolean default null)')
  expect(m).toContain("and security.search_stop_gate_v1(s.provider_id, s.course_id, pv.stopped) is null")
  expect(m).toContain("security.search_stop_gate_v1(p_provider_id) = 'search_stopped' then")
  expect(m).toContain("if security.search_stop_gate_v1(p_provider, null, null, v_person) = 'search_stopped' then")
  expect(m).toContain("security.pipeline_num_v1('search.stop_per_course_after', 6)")
  expect(m).not.toContain("pages.max_distinct_wrong'")
  expect(m).toMatch(/-- Replaces: [^\n]+\n(--[^\n]*\n)*-- Retires: nothing/)
})
