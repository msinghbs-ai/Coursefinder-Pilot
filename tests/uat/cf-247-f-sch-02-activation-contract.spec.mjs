// Guards: F-SCH.01 activation (Platform Admin 12 Nov 2026 11:50 AEDT: reader on in shadow first, the four built scholarship recoveries on, scope staged by cohort, alerts for declining admission); each change recorded with its before value, after value and the decision as reason
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261113040000_cf247_sch_activation.sql', 'utf8')

test('the decided values only, each with a control event; the reader stays in shadow', () => {
  for (const [k, v] of [['batch.sch_eligibility_enqueue', 'to_jsonb(300)'], ['batch.sch_eligibility_read', 'to_jsonb(40)'], ['sch_elig.on', 'to_jsonb(1)'],
    ['sch_cov.recover_listings_on', 'to_jsonb(1)'], ['sch_cov.recover_register_pages_on', 'to_jsonb(1)'], ['sch_cov.recover_stored_reads_on', 'to_jsonb(1)'],
    ['retry.scholarship_transient_recover_on', 'to_jsonb(1)'], ['scholarship.pilot_only', 'to_jsonb(false)']]) expect(m).toContain(`('${k}', ${v}, 'Platform Admin decision 12 Nov 2026 11:50 AEDT`)
  expect(m).not.toMatch(/'sch_elig\.apply_on',\s*to_jsonb\(1\)/)
  expect(m).not.toMatch(/'sch_elig\.silent_resolves',\s*to_jsonb\(1\)/)
  expect(m).toContain("insert into pipeline.admin_control_events(area, action, target, detail, actor)")
  expect(m).toContain("jsonb_build_object('before', v_before, 'after', r.v, 'reason', r.reason)")
  expect(m).toContain("security.pipeline_num_v1('sch_elig.apply_on', -1) <> 0 then raise exception 'post-check: the reader is on in shadow only'")
  expect(m).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

test('the flow guard reports a declining admission from settings, md5-guarded', () => {
  expect(m).toContain("'0dbd3d33b48b2cc3622e5f2ad0a36009'")
  expect(m).toContain("'code', 'admission_declining'")
  for (const k of ['sch_flow.decline_pct', 'sch_flow.decline_window_days', 'sch_flow.decline_min_daily']) expect(m).toContain(`security.pipeline_num_v1('${k}'`)
})
