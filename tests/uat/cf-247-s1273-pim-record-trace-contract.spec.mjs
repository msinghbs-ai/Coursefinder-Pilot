// Guards: DR-19 slice 1 (SS-Programme-Control assignment 26 Nov 2026 19:18 AEDT; Master Plan section 6): record-level PIM trace and evidence-only diagnosis (operational failure, data exception and software defect kept apart), read-only, Viewer and above
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261129210000_cf247_s1273_pim_record_trace.sql', 'utf8')

test('s1273: the trace reads the PIM interfaces and runs nothing', () => {
  expect(sql).toContain('security.field_state_v1(r.field, p_course)')
  expect(sql).toContain('from pipeline.field_enrich_items i')
  expect(sql).toContain('from pipeline.course_field_absence a')
  expect(sql).toContain('from pipeline.layer4_review_items l')
  for (const fn of ['security.pim_record_trace_v1', 'security.pim_provider_trace_v1']) {
    const body = sql.slice(sql.indexOf(`create or replace function ${fn}`), sql.indexOf('end $f$;', sql.indexOf(`create or replace function ${fn}`)))
    expect(body).toMatch(/language plpgsql stable/)
    expect(body).not.toMatch(/\b(insert|update|delete)\s+(into\s+)?(pipeline|catalogue)\./i)
  }
})

test('s1273: classes are kept apart and the defect rules read the register and settings', () => {
  for (const c of ['not_applicable', 'verified', 'protected_hold', 'in_progress', 'operational_failure', 'data_exception', 'software_defect', 'partial', 'awaiting_first_read'])
    expect(sql).toContain(`'${c}'`)
  expect(sql).toContain("elsif r.reader = 'none' then")
  expect(sql).toContain("security.pipeline_num_v1('pim.trace_failure_attempts', 3)")
  expect(sql).toContain("security.pipeline_num_v1('pim.trace_max_courses', 1000)")
  expect(sql.indexOf("v_class := 'operational_failure'") < sql.indexOf("v_class := 'data_exception'")).toBe(true)
})

test('s1273: admin reads check the role; nothing is granted to anon', () => {
  expect(sql.match(/coalesce\(security\.current_role_rank\(\), 0\) < 1/g)?.length).toBe(2)
  expect(sql).toMatch(/from public, anon;/)
  expect(sql).toContain('grant execute on function public.admin_pim_record_trace_v1(uuid, text), public.admin_pim_provider_trace_v1(uuid, text, text, integer) to authenticated')
  expect(sql).toContain("'website_v2', 'not read (frozen surface)'")
  expect(sql).toContain("security.pipeline_num_v1('pim.trace_list_limit', 200)")
})
