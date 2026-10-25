// CF-247 SP-2a (Platform Admin 26 Oct 2026 08:25): no-page / conjoint first runs are admitted without a person only when the course list
// is verified, the sample is confirmed and the list shape is already person-approved; 1 in layer4.auto_admit_sample_rate is audited.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261026002000_cf247_sp2a_layer4_auto_admit_first_runs.sql', 'utf8')
const fn = m.slice(m.indexOf('create or replace function security.no_page_auto_admit_v1()'), m.indexOf("comment on function security.no_page_auto_admit_v1()"))

test('every tunable is a setting (G2), sample rate default 10, on by the Platform Admin decision', () => {
  for (const k of ['auto_admit_on', 'auto_admit_sample_rate', 'auto_admit_sample_pct', 'auto_admit_min_sample', 'auto_admit_list_recall', 'auto_admit_min_bound', 'auto_admit_list_days', 'auto_admit_match_share'])
    expect(m).toMatch(new RegExp(`\\('pipeline', 'layer4\\.${k}', `))
  expect(m).toMatch(/'layer4\.auto_admit_sample_rate', [^\n]*'number', '10'::jsonb, 1, 100,/)
  expect(m).toMatch(/'layer4\.auto_admit_sample_pct', [^\n]*'number', '0\.8'::jsonb,/)
  expect(fn).toContain("if security.pipeline_num_v1('layer4.auto_admit_on', 0) < 1 then return")
})

test('the three checks gate the approval, novel shapes and the audit stay with a person', () => {
  const at = (s) => { const i = fn.indexOf(s); expect(i, s).toBeGreaterThan(0); return i }
  const approve = at("perform security.no_page_review_apply_v1(r.id, 'approve', v_final, v_reason);")
  for (const o of ["v_out := 'no_list'", "v_out := 'list_not_verified'", "v_out := 'sample_not_confirmed'", "v_out := 'novel_shape'", "v_out := 'sampled_to_layer4'"])
    expect(at(o)).toBeLessThan(approve)
  expect(fn).toContain("if v_out is null then")
  expect(fn).toContain("(v_n + 1) % v_rate = 0")
  expect(fn).toContain("not ((v_list->>'shape') = any (v_proven))")
  // proven shapes come only from first runs a person approved, never from this job's own admissions
  expect(fn).toMatch(/into v_proven[\s\S]*?x\.outcome = 'auto_admitted'\);/)
  // a conjoint rule takes every course: any look-alike sends it to a person
  expect(fn).toContain("r.field_code = 'conjoint_rule_first_run' and (v_s->>'confirmed')::int < (v_s->>'n')::int")
})

test('every auto-admission is recorded with evidence and shows as "Auto:" in Decided', () => {
  expect(fn).toContain("v_reason := format('Auto: own course list verified")
  expect(fn).toContain('insert into pipeline.layer4_decisions(')
  expect(fn).toContain("values ('layer4', 'inbox_decide', r.id::text,")
  expect(fn).toContain('insert into pipeline.layer4_auto_admissions(')
  expect(m).toContain("comment on table pipeline.layer4_auto_admissions is")
})

test('job catalogued before scheduling, no number in the command, housekeeping lines, nothing dropped', () => {
  expect(m.indexOf("('layer4-auto-admit', 'Course pages'")).toBeLessThan(m.indexOf("select cron.schedule('layer4-auto-admit'"))
  expect(m).toContain("select cron.schedule('layer4-auto-admit', '47 * * * *', $$select security.no_page_auto_admit_v1()$$);")
  expect(m).toMatch(/^-- Replaces: nothing\n-- Retires: nothing$/m)
  expect(m).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})
