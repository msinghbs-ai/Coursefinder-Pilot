// Guards: CF-247 s912 (Platform Admin 21 Nov 2026 09:57, chat S1-Coverage-Unlock-UI-Notes: partial entry-table admission approved, superseding
// the all-or-nothing completeness hold under Decision 276): the 24-hour shadow measures every proposed row of the read, university-wide and
// course rows, with course rows also counted on their own; it still records only and admits nothing
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261121130000_cf247_s912_partial_admission_shadow_course_rows.sql', 'utf8')
const fn = MIG.slice(MIG.indexOf('create or replace function security.aer_uniwide_partial_shadow_v1()'), MIG.indexOf('create or replace function security.aer_uniwide_partial_shadow_report_v1()'))

test('the decision is quoted and the shadow counts university-wide and course rows of the read', () => {
  expect(MIG).toContain('admit all country rows in a university-wide or course')
  expect(fn).toContain("where m.run_id = v_run and m.status = 'proposed')  -- s912")
  expect(fn).not.toContain("and m.status = 'proposed' and m.course_id is null")
  expect(fn).toContain('select m.id, m.course_id is not null course_row, case')
  expect(MIG).toContain("'course_rows_would_admit', coalesce(sum(s.course_would_admit), 0)")
  expect(MIG).toContain('alter table pipeline.aer_uniwide_partial_shadow add column if not exists course_would_admit int not null default 0;')
})

test('still a shadow: no admission, no entry-row write, no job change, nothing dropped', () => {
  expect(fn).toContain("return jsonb_build_object('on', true, 'shadow', true, 'admitted', 0,")
  expect(fn).not.toMatch(/update\s+catalogue\.|insert\s+into\s+catalogue\.|aer_matrix_machine_admit_v1|layer4_decisions|update\s+pipeline\.layer4_review_items/i)
  expect(MIG).toContain("raise exception 'post-check: the shadow changed an entry row';")
  expect(MIG).not.toMatch(/cron\.schedule\(|cron\.alter_job|cron\.unschedule|^\s*(drop|delete|truncate)\b/im)
  expect(MIG).toMatch(/^-- Replaces: .+$/m)
  expect(MIG).toMatch(/^-- Retires: .+$/m)
})
