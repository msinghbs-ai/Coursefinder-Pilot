// Guards: Platform Admin 24 Nov 2026 15:10 AEDT (P1 Item 2, UAT feedback-4: PTE and TOEFL with each band score inherited from the university's approved English policy where its IELTS agrees; insert only; locks and gates apply)
// s1047: security.provider_english_inherit_tests_v1 and its run for the feedback-4 universities.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261124234000_cf247_s1047_english_test_inheritance.sql', 'utf8')
const fn = MIG.slice(MIG.indexOf('CREATE OR REPLACE FUNCTION security.provider_english_inherit_tests_v1'), MIG.indexOf('$function$;', MIG.indexOf('CREATE OR REPLACE FUNCTION security.provider_english_inherit_tests_v1') + 40))

test('s1047: only an approved policy, only level defaults at the agreeing IELTS, only tests with all four bands', () => {
  expect(fn).toContain("x.status <> 'approved' then return jsonb_build_object('skipped', 'not an approved English policy')")
  expect(fn).toContain("r.source_requirement_key = 'policy:' || x.id || ':ielts' and r.status = 'active' and r.overall_score = v_ia")
  expect(fn).toContain("r.notes like 'Default for %'")
  expect(fn).toContain("where k in ('listening', 'reading', 'writing', 'speaking')) = 4 loop")
  expect(fn).toContain("e->>'test_code' <> 'IELTS'")
})

test('s1047: insert only (a course keeps its own value), the policy row\'s source and stored copy, logged, search refreshed', () => {
  expect(fn).toContain('on conflict (course_id, english_test_id) do nothing')
  expect(fn).toContain("and not exists (select 1 from catalogue.course_english_requirements o where o.course_id = r.course_id and o.english_test_id = t.id and o.status = 'active')")
  expect(fn).toContain('r.source_id, r.evidence_id, r.confidence')
  expect(fn).toContain("insert into pipeline.admin_control_events")
  expect(fn).toContain('search.refresh_course_enrichment_scoped_v1')
  expect(fn).not.toMatch(/update catalogue\.course_english_requirements|delete from|manual_locks/i)
})

test('s1047: run for the three feedback-4 universities; post-checks; nothing dropped', () => {
  for (const id of ['bac82321-ded7-4e10-a71d-b18f3ae4d1c7', 'de2201a1-69ee-40ff-b6aa-0e54e535e6c0', '1822b40a-8b13-44dc-8c37-106ae31bb447']) expect(MIG).toContain(id)
  expect(MIG).toContain("raise exception 'post-check: a row was added without its four band scores'")
  expect(MIG.replace(/on commit drop/g, '')).not.toMatch(/\bdrop\s+(table|function|trigger|index|view)|truncate |cron\.schedule/i)
  for (const s of ['post-check: the consumer API moved', 'post-check: manual locks changed', 'post-check: the number of active cron jobs changed']) expect(MIG).toContain(s)
})
