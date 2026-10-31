// Guards: StudySearch decision D4 / SS-009 (Platform Admin 31 Oct 2026 13:30; admin 2026-10-31-studysearch-transformation.md §16.1, §28): the course detail entry object gains an additive min_scores[] of every admitted score as printed (no inferred score or scale), min_score and min_score_basis unchanged; G3 approval recorded and the baseline re-taken
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261031070000_cf247_d4_entry_min_scores.sql', 'utf8')
const code = (s) => s.replace(/--[^\n]*/g, '')

test('G3: approved, additive only, baseline re-taken', () => {
  expect(m).toMatch(/^-- Consumer API change approved: Platform Admin, 31 Oct 2026 13:30 \(StudySearch decision D4/m)
  expect(m).toContain("select security.consumer_api_rebaseline_v1('D4 (31 Oct 2026): additive entry.min_scores[]")
  expect(m).toContain("select pg_temp.edit_once('security.entry_course_payload_v1(uuid,text)', '80fdfabb84a90fab25df36970dea696a', '691bbba7958ebcd35ac332879c27d341', array[")
  expect(code(m).match(/select pg_temp\.edit_once\(/g)).toHaveLength(1)
})

test('the items: as admitted, scale only as recorded, identical rows once, stable order; min_score untouched', () => {
  expect(m).toContain("'min_scores', coalesce((select jsonb_agg(jsonb_build_object('score', m.min_entry_score, 'basis', m.min_entry_score_basis, 'audience', m.audience,")
  expect(m).toContain("'scale', m.grade_scale, 'quote', m.quote, 'source_url', m.source_url, 'as_at', m.as_at)")
  expect(m).toContain("order by case m.audience when 'international' then 0 when 'all' then 1 else 2 end, m.min_entry_score_basis, m.min_entry_score, m.quote)")
  expect(m).toContain("from (select distinct on (r.audience, r.min_entry_score_basis, r.min_entry_score, r.quote) r.* from r where r.min_entry_score is not null")
  expect(m).toContain("), '[]'::jsonb),$n$]],")
  // the edit keeps the existing min_score_basis line and adds after it
  expect(m).toContain("array[$o$'min_score_basis', (select s.min_entry_score_basis from s),$o$, $n$'min_score_basis', (select s.min_entry_score_basis from s),")
})

test('nothing else: no removal, rename or retype; no data, schedule or setting', () => {
  const c = code(m)
  expect(c).not.toMatch(/\b(drop|delete|truncate|insert|update)\b/i)
  expect(c).not.toMatch(/cron\.|platform_toolset_settings|statement_timeout/)
  expect(c).not.toMatch(/'min_score',|'min_score_basis', \(select s\.min_entry_score_basis from s\)[^,]/)
})
