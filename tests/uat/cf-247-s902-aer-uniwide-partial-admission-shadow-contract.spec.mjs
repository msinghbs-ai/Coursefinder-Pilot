// Guards: CF-247 s902 (Platform Admin 21 Nov 2026 07:48, chat S1-Coverage-Unlock-UI-Notes; decision "New auto-admit rule, in shadow first for
// 24 hours"): the university-wide partial admission of entry rows runs in shadow only — it records what it would admit (rows passing every
// machine row rule when only completeness stops the read; dropped countries stay with a person) and admits nothing; it runs as a rule of
// admission-rule-runner (no new cron job), is catalogued and registered, and its switch and batch are settings
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261121101000_cf247_s902_aer_uniwide_partial_admission_shadow.sql', 'utf8')
const fn = MIG.slice(MIG.indexOf('create or replace function security.aer_uniwide_partial_shadow_v1()'), MIG.indexOf('create or replace function security.aer_uniwide_partial_shadow_report_v1()'))

test('shadow only: the run writes its own table and nothing else; no admission or entry-row write anywhere', () => {
  expect(fn).toContain("return jsonb_build_object('on', true, 'shadow', true, 'admitted', 0,")
  expect(fn).toContain('insert into pipeline.aer_uniwide_partial_shadow as s')
  expect(fn).not.toMatch(/update\s+catalogue\.|insert\s+into\s+catalogue\.|aer_matrix_machine_admit_v1|layer4_decisions|update\s+pipeline\.layer4_review_items/i)
  expect(MIG).not.toMatch(/aer_matrix_machine_admit_v1\(/)
  expect(MIG).toContain("raise exception 'post-check: the shadow changed an entry row';")
})

test('only items stopped by completeness are measured, with the machine admission row rules in its order', () => {
  expect(fn).toContain("c := security.aer_matrix_machine_check_v1(r.id);")
  expect(fn).toContain("if c->>'rule' in ('gate_incomplete', 'completeness') and v_run is not null then")
  for (const w of ["then 'excluded_by_rule'", "then 'low_confidence'", "then 'short_quote'", "then 'level_unmapped'", "then 'no_minimum'", "then 'minimum_not_in_quote'"]) expect(fn).toContain(w)
  expect(fn).toContain("where m.run_id = v_run and m.status = 'proposed' and m.course_id is null)")
  expect(fn).toContain("coalesce(array(select jsonb_array_elements_text(c->'checks'->'gate'->'countries_missing')), '{}')")
})

test('a rule of admission-rule-runner: catalogued, registered, settings with labels; no cron job; housekeeping lines', () => {
  expect(MIG).toContain("values ('aer-uniwide-partial-shadow', 'aer-uniwide-partial-shadow', 'select security.aer_uniwide_partial_shadow_v1()', md5('select security.aer_uniwide_partial_shadow_v1()'),")
  expect(MIG).toContain("('aer-uniwide-partial-shadow', 'Admission', 21, 'Entry requirements: university-wide partial admission (shadow)',")
  expect(MIG).toContain("('job', 'aer-uniwide-partial-shadow', 'Layer 4', 'Admission',")
  expect(MIG).toContain("('pipeline', 'aer.uniwide_partial_shadow_on', 'Entry requirements: measure university-wide partial admission (shadow)',")
  expect(MIG).toContain("('pipeline', 'batch.aer_uniwide_partial_shadow', 'Entry requirements: items measured a run (university-wide partial admission shadow)',")
  expect(fn).toContain("security.pipeline_num_v1('batch.aer_uniwide_partial_shadow', 200)")
  expect(MIG).toContain('comment on table pipeline.aer_uniwide_partial_shadow is')
  expect(MIG).not.toMatch(/cron\.schedule\(|cron\.alter_job|cron\.unschedule|^\s*(drop|delete|truncate)\b/im)
  expect(MIG).toMatch(/^-- Replaces: .+$/m)
  expect(MIG).toMatch(/^-- Retires: .+$/m)
})
