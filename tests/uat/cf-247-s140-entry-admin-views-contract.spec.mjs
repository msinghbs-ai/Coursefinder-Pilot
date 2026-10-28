// Guards: CF-247 Track C Step B decision 28 Oct 2026 (Platform Admin mandate 20:36; admin docs/platform/ENTRY-REQUIREMENTS-STEP-B-DECISION-2026-10-28.md section 6): the admin entry-requirements views live in the existing Provider drawer and Course detail blade, read through one bounded server function (one provider or course, at most 100 rows a call), with no table editing, no arbitrary SQL and no second approval route; the one-course read is Platform Admin only
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261028001000_cf247_entry_step_b_course_read_resolver.sql', 'utf8')
const code = m.split('\n').filter(l => !/^\s*--/.test(l)).join('\n')
const fn = code.slice(code.indexOf('create or replace function public.admin_entry_requirements'), code.indexOf('revoke all on function public.admin_entry_requirements'))
const ui = fs.readFileSync('src/EntryRequirements.jsx', 'utf8')

test('bounded, paged reads for an assigned role; the read request for a Platform Admin, one course, a reason', () => {
  expect(fn).toContain("if auth.uid() is null or v_rank < 1 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;")
  expect(fn).toContain("v_size := greatest(1, least(coalesce(nullif(p_args->>'page_size', '')::int, 50), 100));")
  expect(fn).toContain("limit v_size offset (v_page - 1) * v_size")
  expect(fn).toContain("if v_pid is null then raise exception 'provider_id required'; end if;")
  expect(fn).toContain("limit 100) r),")
  expect(fn).toContain("if v_rank < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;")
  expect(fn).toContain("raise exception 'a read of this course is already in progress or waits in Layer 4';")
  expect(fn).not.toMatch(/\bexecute\b/i)
  expect(fn).not.toMatch(/(update|delete from|insert into) catalogue\./i)  // reads only; admission stays in Layer 4
  expect(m).toContain('revoke all on function public.admin_entry_requirements(text, jsonb) from public, anon;')
})

test('existing surfaces only: Provider drawer and Course detail blade; no direct table access from the page', () => {
  expect(fs.readFileSync('src/mature-main.jsx', 'utf8')).toContain('{data.id&&<ProviderRankings providerId={data.id} navigate={navigate}/>}{data.id&&<ProviderEntryMatrix providerId={data.id}/>}')
  expect(fs.readFileSync('src/RecordEditor.jsx', 'utf8')).toContain('<CourseEntryRequirements courseId={courseId} onError={onError}/>')
  expect(ui).toContain("supabase.rpc('admin_entry_requirements',{p_action:action,p_args:args})")
  expect(ui).not.toMatch(/supabase\.from\(/)
  for (const a of ['data-entry-matrix', 'data-entry-rows', 'data-course-entry', 'data-entry-resolution', 'data-course-entry-read']) expect(ui).toContain(a)
  expect(ui).toContain("case_by_case:'This qualification is considered case by case'")
  expect(ui).toContain('<ReasonAction label="Read from the stored page"')
})
