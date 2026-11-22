// Guards: REQ-34 (Platform Admin consolidated batch, 22 Nov 2026 14:22 AEDT): OET requirements carry their letter grades, so the Zoho v3 OET grade columns hold live values
// s975: the active OET requirements get score_grade from their overall score and subtest_grades from each sub-test score, on OET's published
// scale; only empty grades are filled, a course whose English a person locked is left alone, nothing is read from a page and nothing costs.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261122180000_cf247_s975_oet_letter_grades.sql', 'utf8')

test('the OET scale is the published one: A, B, C+, C, D, E', () => {
  expect(MIG).toContain("insert into s975_oet_scale values ('A', 450, 500), ('B', 350, 449), ('C+', 300, 349), ('C', 200, 299), ('D', 100, 199), ('E', 0, 99);")
})

test('only empty grades of active OET requirements are filled; locked English is left alone; checked after', () => {
  expect(MIG).toContain("where upper(t.code) = 'OET' and r.status = 'active' and r.score_grade is null")
  expect(MIG).toContain("not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.field = 'english' and l.entity_id::text = r.course_id::text)")
  expect(MIG).toContain('subtest_grades = coalesce(r.subtest_grades, g.subtests)')
  expect(MIG).toContain("raise exception 'post-check: % OET requirements still have no letter grade', v_left")
  expect(MIG).toContain('post-check: the manual locks changed')
  expect(MIG).toContain('security.consumer_api_check_v1()')
  expect(MIG).toMatch(/^-- Replaces: /m)
  expect(MIG).toMatch(/^-- Retires: /m)
  expect(MIG).not.toMatch(/cron\.schedule|\bdrop (table|function|index|schema|view|trigger)|alter table [^;]* drop |delete from |truncate |create or replace function/i)
})
