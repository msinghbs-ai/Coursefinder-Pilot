// Guards: S671 provider matrix rows (Platform Admin standing mandate 18 Nov 2026 19:28 AEDT, session S1-AER step 2): a row with no level read takes the one level named in the stored page heading or file title only when no row of the read names a level and the level is in aer.matrix_level_inherit_codes; "Year N equivalent" is never a study level; a completion requirement with no score is not a missing minimum; nothing is written into a minimum; AER v1 thresholds, the D-R3 gate, the completeness guard and the apply are unchanged (Decision 276); CREATE OR REPLACE only, G3 75/48.
// CF-247 S671. Migration 20261118235000_cf247_s671_aer_matrix_level_inherit_completion (rolled-back live dry run with outcome probe: workflow run 44269575341).
// G2, G3 and housekeeping are guarded centrally by s32, s57 and s42.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261118235000_cf247_s671_aer_matrix_level_inherit_completion.sql', 'utf8')
const code = (t) => t.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')
const exclusions = M.split('create or replace function security.aer_matrix_machine_exclusions_v1(p_run uuid)')[1].split('$function$;')[0]

test('every edited function is checked against its live md5 of 18 Nov first; check and admission are edited in place exactly once', () => {
  for (const [sig, md5] of [['security.aer_matrix_machine_exclusions_v1(uuid)', '48ddc65416bcdcb87dc7a6ea8ecfe9c5'], ['security.aer_matrix_machine_check_v1(uuid)', '590e309e6e795162de19aceafc3b7488'],
    ['security.aer_matrix_machine_admit_v1(uuid,text)', '5770adca4ca3ff162a5fbceb6ad1885e'], ['security.aer_matrix_machine_validate_v1()', '162cfa24e35bfcc9100c1bea81c61b6a']]) {
    expect(M).toContain(`('${sig}', '${md5}')`)
  }
  expect(M).toContain('the edit must apply exactly once')
  expect(M).toContain('already applied')
  // only existing functions are replaced: no new function, table, view or trigger (G3 75 functions and 48 relations)
  const creates = code(M).match(/create\s+(or\s+replace\s+)?(function|table|view|trigger|materialized)[^(]*/gi) || []
  expect(creates.map((s) => s.trim())).toEqual(['create or replace function security.aer_matrix_machine_exclusions_v1'])
  expect(M).toMatch(/-- Replaces: security\.aer_matrix_machine_exclusions_v1, security\.aer_matrix_machine_check_v1, security\.aer_matrix_machine_admit_v1/)
  expect(M).toContain('-- Retires: nothing.')
})

test('level inheritance: one level named in heading or file title, from the allowed codes, and no row of the read naming a level', () => {
  expect(exclusions).toContain("coalesce(r.result->'completeness'->>'heading', '') heading")
  expect(exclusions).toContain("regexp_split_to_table(lower(run.heading || ' ' || run.slug), '[^a-z]+')")
  expect(exclusions).toContain('join ref.study_levels l on l.id = security.entry_level_map_v1(w)')
  expect(exclusions).toContain('(select count(*) from words) = 1 and cfg.inh_codes ? (select min(w.code) from words w)')
  expect(exclusions).toContain('and not exists (select 1 from m0 where m0.level_label is not null and not m0.eqv)')
  expect(exclusions).toContain('and not exists (select 1 from q0 where q0.level_label is not null and not q0.eqv)')
  expect(M).toContain(`'list', '["bachelor", "masters", "doctorate", "foundation"]'::jsonb`)
  // the identity of an inherited row is the one the trigger will compute from the level
  expect(exclusions).toContain('security.entry_matrix_row_hash_v1(m0.provider_id, m0.course_id, m0.country_code, lvl.id, m0.benchmark_band, m0.qualification_name, m0.conditions)')
  expect(exclusions).toContain('when exists (select 1 from m m2 where m2.h2 = m.h2 and m2.id <> m.id) then \'duplicate_identity\'')
})

test('"Year N equivalent" is not a level, and completion-only rows carry no score; nothing is written into a minimum', () => {
  expect(exclusions).toContain("~* '^\\s*(australian\\s+)?year\\s*1[0-2]\\s+equivalent\\s*$' eqv")
  expect(exclusions).toContain("then 'level_equivalence_only'")
  expect(exclusions).toContain("m0.quote ~* '\\m(successful(ly)?\\s+)?complet(e|ed|ion)\\M' and m0.quote !~ '%'")
  expect(exclusions).toMatch(/gpa\|cgpa\|average\|aggregate\|marks\?\|scores\?\|points\?\|pass\(es\)\?/)
  expect(exclusions).toContain(', false) cmp')
  const c = code(M)
  expect(c).not.toMatch(/set\s+min_(grade|value)|min_grade\s*=|min_value\s*=/i)
  expect(c).toContain("jsonb_build_object('completion_only', true, 'completion_rule', 'S671')")
  expect(c).toContain("jsonb_build_object('equivalent_to', m.level_label)")
})

test('both rules are switches that restore the 12 Nov rules at 0; AER v1 thresholds, gate, completeness and apply are untouched', () => {
  expect(M).toContain("'aer.matrix_level_inherit_on'")
  expect(M).toContain("'aer.matrix_completion_only_on'")
  expect(exclusions).toContain("security.pipeline_num_v1('aer.matrix_level_inherit_on', 0) >= 1 inh_on")
  expect(exclusions).toContain("security.pipeline_num_v1('aer.matrix_completion_only_on', 0) >= 1 cmp_on")
  const c = code(M)
  expect(c).not.toMatch(/update pipeline\.platform_toolset_settings/i)
  expect(c).not.toMatch(/entry_matrix_gate_v1\(p_run|function security\.entry_matrix_review_apply_v1|function security\.entry_matrix_gate_v1/i)
  expect(c).not.toMatch(/layer4_decisions|update pipeline\.layer4_review_items|delete from|drop (table|function)|truncate/i)
  expect(c).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings/i)
  expect(c).toContain("security.pipeline_num_v1('aer.matrix_machine_min_confidence', -1) <> 0.9")
  expect(c).toContain("security.pipeline_num_v1('aer.machine_min_confidence', -1) <> 0.8")
  expect(c).toContain('consumer_api_functions_v1()) <> 75')
})

test('the admission writes the inherited level only to rows not held back, before the unchanged apply, and the matrix validation is re-run and audited', () => {
  expect(M).toContain('where m.run_id = v_run and m.status = \'proposed\' and m.study_level_id is null and not (m.id = any(v_ex))')
  expect(M.indexOf("v_inf := security.aer_matrix_machine_exclusions_v1(v_run);")).toBeLessThan(M.lastIndexOf("v_res := security.entry_matrix_review_apply_v1(p_item, 'approve'"))
  expect(code(M)).toContain('v := security.aer_matrix_machine_validate_v1();')
  expect(M).toContain("'authority', 'Platform Admin standing mandate 18 Nov 2026 19:28 AEDT (S1-AER step 2)'")
})
