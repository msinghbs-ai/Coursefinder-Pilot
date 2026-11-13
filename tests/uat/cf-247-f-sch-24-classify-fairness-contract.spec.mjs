// Guards: F-SCH.14 fair scholarship coverage classification (Platform Admin S2-Scholarship directive 13 Nov 2026 23:07, Priority 1): no provider is stranded behind others; providers whose open Layer 4 case or AI review waits on re-classification, or that are older than sch_cov.max_age_hours, are classified before the routine order
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261113371500_cf247_sch_coverage_classify_fairness.sql', 'utf8')

test('one md5-guarded edit of the selection order; what classification decides is unchanged', () => {
  expect(m).toContain("select pg_temp.edit_n('security.scholarship_coverage_classify_v1(uuid[])', '3892bf5f123f2ec48eca72616b0015c8', array[")
  expect(m).toContain('], array[1]);')
  const news = [...m.matchAll(/\$n\$([\s\S]*?)\$n\$/g)].map((x) => x[1]).join('\n')
  expect(news).not.toContain('(l.issue_fingerprint is not null) desc')
})

test('waiting Layer 4 work and over-age providers come before integration issues and the routine order', () => {
  expect(m).toContain("when c.classified_at < v_now - make_interval(hours => security.pipeline_num_v1('sch_cov.max_age_hours', 36)::int)")
  expect(m).toContain("i.lane like 'sch%' and i.status = 'awaiting_input'")
  expect(m).toContain("r.status = 'pending') then 1")
  expect(m).toContain('when l.issue_fingerprint is not null then 2 else 3 end,')
  expect(m).toContain('c.classified_at nulls first, l.provider_id')
})

test('the longest wait and the batch are settings (G2) with their reasons', () => {
  expect(m).toContain("('pipeline', 'sch_cov.max_age_hours', ")
  expect(m).toContain("set value = '120'::jsonb")
  expect(m).toContain("key = 'batch.sch_coverage_classify' and value = '40'::jsonb")
})
