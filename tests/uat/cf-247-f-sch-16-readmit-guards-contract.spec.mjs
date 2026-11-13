// Guards: F-SCH safe re-admission (Platform Admin S2-Scholarship directive 13 Nov 2026 §3; Operating Model v1.19 S2-Scholarship 3): no restore over a person's decision or for an award whose only round closed long ago; the same reason refuses both in the reader and in the restore
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261113293700_cf247_sch_readmit_guards_on.sql', 'utf8')

test('the blocker: human decision first, then a closed round with nothing open and not rolling; unknown dates do not block', () => {
  expect(m).toContain('from pipeline.manual_locks l where l.entity_id = p_scholarship')
  expect(m).toContain('from pipeline.layer4_block_decisions b where b.entity_id = p_scholarship')
  expect(m).toContain("then 'human_decision'")
  expect(m).toContain("s.application_close_date is not null")
  expect(m).toContain("security.pipeline_num_v1('sch_elig.readmit_round_stale_days', 365)")
  expect(m).toContain("w.closes_at >= current_date")
  expect(m).toContain("then 'round_closed'")
})

test('used by the reader and the restore, md5-guarded; the gate on only with the guards; the positive case is now blocked', () => {
  expect(m).toContain("then 'readmit_' || security.scholarship_readmit_blocker_v1(r.admitted_scholarship_id)")
  expect(m).toContain("return jsonb_build_object('readmitted', false, 'reason', security.scholarship_readmit_blocker_v1(s.id));")
  expect(m).toContain("'c757df391e638712d52c7da316778ce0'")
  expect(m).toContain("'2a50a647bf7c36ddfd2baee059f46dae'")
  expect(m).toContain("key = 'sch_elig.readmit_on' and value is distinct from to_jsonb(1)")
  expect(m).toContain("is distinct from 'round_closed' then")
})
