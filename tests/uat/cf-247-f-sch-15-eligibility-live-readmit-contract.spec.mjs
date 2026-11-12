// Guards: F-SCH.01 follow-up (scheduled review 12 Nov 2026 23:15 AEDT; directive 12 Nov 16:12 "Do not introduce another indefinite manual activation checkpoint"): the eligibility reader live again after every shadow decision was reviewed right; a re-admission path for proofs now valid, shipped in shadow (sch_elig.readmit_on 0)
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261113240000_cf247_sch_eligibility_live_readmit.sql', 'utf8')

test('live again with a control event; only the reviewed shadow proofs are reset', () => {
  expect(m).toContain("set value = to_jsonb(1)")
  expect(m).toContain("key = 'sch_elig.apply_on' and value is distinct from to_jsonb(1)")
  expect(m).toContain("'sch_elig.apply_on 0 -> 1 (eligibility reader live again after the shadow review)'")
  expect(m).toContain("where outcome = 'proven' and applied->>'mode' = 'shadow';")
})

test('re-admission: current rule, the award\'s own page, its own setting shipped off; the withdrawal reversed, never a new record', () => {
  expect(m).toContain("('pipeline', 'sch_elig.readmit_on',")
  expect(m).toContain("'number', '0'::jsonb, 0, 1, 'on (1) or off (0)'")
  expect(m).toContain("coalesce(r.admit_reasons, '{}'::text[]) = array['eligibility_proof_not_specific']")
  expect(m).toContain("when not security.scholarship_page_names_award_v1(r.page_url,")
  expect(m).toContain("elsif v_act = 'readmit' and not v_readmit then")
  expect(m).toContain("update scholarship.scholarships set lifecycle_status = 'active', updated_at = now() where id = s.id;")
  expect(m).toContain("if s.id is null or s.lifecycle_status <> 'inactive' or s.publication_status = 'published' then")
  expect(m).toContain('v_apply := security.scholarship_sweep_apply_v1(s.id);')
  expect(m).toContain("'45e52f66312824e4e7265814cb712728'")
})

test('the own-page check: an award page counts, a list or overview page does not', () => {
  expect(m).toContain("'Bowel Cancer Translational Research Scholarship') then raise exception 'post-check: own page not recognised'")
  expect(m).toContain("prizes-and-awards.html', 'Charles Perkins Centre Summer Scholarships') then raise exception 'post-check: a list page must not count'")
  expect(m).toContain("graduate-awards-overview', 'Graduate Entrance Research Scholarship (GERS)') then raise exception 'post-check: an overview page must not count'")
})
