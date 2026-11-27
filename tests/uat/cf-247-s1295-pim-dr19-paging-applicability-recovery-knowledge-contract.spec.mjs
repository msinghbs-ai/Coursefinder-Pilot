// Guards: DR-19 slice 4 (SS-Programme-Control 27 Nov 2026 11:28 AEDT): provider trace paged with whole-provider accounting, evidence-only international applicability (never from a URL), recovery causes from existing registers, knowledge referenced not re-recorded
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261130120000_cf247_s1295_pim_dr19_paging_applicability_recovery_knowledge.sql', 'utf8')

test('s1295: paging accounts for the whole provider', () => {
  expect(sql).toContain("security.pipeline_num_v1('pim.trace_page_size', 150)")
  for (const k of ["'active_courses'", "'next_offset'", "'remaining'", "'complete'"]) expect(sql).toContain(k)
  expect(sql).toContain('order by id offset v_off limit v_page')
})

test('s1295: international applicability comes from link audience and held rows only', () => {
  for (const c of ['field_international_verified', 'domestic_source_detected', 'audience_ambiguous', 'international_source_verified', 'shared_source_verified', 'international_not_checked'])
    expect(sql).toContain(`'${c}'`)
  expect(sql).toContain("l.link_type = 'official_course'")
  expect(sql).not.toMatch(/l\.url\s*~\*?\s*'[^']*domestic/i)
})

test('s1295: recovery causes and knowledge reuse existing registers; nothing recorded', () => {
  for (const c of ['no_reader_configuration', 'reader_not_qualified', 'qualified_reader_awaiting_activation', 'missing_official_source', 'unsupported_website_structure', 'repeated_ineffective_extraction', 'no_eligible_work_from_planner', 'incorrect_source_audience', 'admission_or_publication_hold'])
    expect(sql).toContain(`'${c}'`)
  expect(sql).toContain('from pipeline.integration_issues i where p_course = any(i.course_ids)')
  expect(sql).toContain('from pipeline.ops_remedy_knowledge k')
  expect(sql).not.toMatch(/insert into pipeline\.(ops_remedy_knowledge|integration_issues|admin_control_events)/i)
})
