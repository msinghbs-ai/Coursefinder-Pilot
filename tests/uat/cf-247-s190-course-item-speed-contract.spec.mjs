// Guards: StudySearch decision D6 / SS-012 (Platform Admin 31 Oct 2026 13:30; admin 2026-10-31-studysearch-transformation.md §26): api.website_v2_course_item is sped up with output-identical edits only (display code computed once; a keyed published check), approved under G3 and re-baselined; the search function and every response key, value and order are unchanged
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261031050000_cf247_d6_course_item_speed.sql', 'utf8')
const code = (s) => s.replace(/--[^\n]*/g, '')

test('G3: the consumer change is approved, recorded and re-baselined', () => {
  expect(m).toMatch(/^-- Consumer API change approved: Platform Admin, 31 Oct 2026 13:30 \(StudySearch decision D6/m)
  expect(m).toContain("select security.consumer_api_rebaseline_v1('D6 (31 Oct 2026): api.website_v2_course_item output-identical speed-up")
})

test('one md5-guarded edit of the item builder: display code once, keyed published check', () => {
  expect(m).toContain("select pg_temp.edit_once('api.website_v2_course_item(uuid,text[],text[])', '151293140767d73fdcc1243d9d9e9ad0', '8f2a0ac921c4507673c1232cf2ecc8aa', array[")
  expect(code(m).match(/select pg_temp\.edit_once\(/g)).toHaveLength(1)
  expect(m).toContain("dc := security.course_display_code_v1(d.course_id);")
  expect(m).toContain("$o$security.course_display_code_v1(d.course_id)->>'$o$, $n$dc->>'$n$]")
  expect(m).toContain("case when exists (select 1 from security.provider_hidden_v1 h where h.provider_id = d.provider_id) then 'unpublished' else 'published' end")
  expect(m).toContain('array[1, 1, 3, 1]);')
})

test('nothing else changes: no other consumer function, no key renamed, no data, schedule or setting', () => {
  const c = code(m)
  expect(c).not.toMatch(/website_v2_course_search|zoho_|website_edge_/)
  expect(c).not.toMatch(/\b(drop|truncate|delete|insert|update)\b/i)
  expect(c).not.toMatch(/cron\.|platform_toolset_settings|statement_timeout/)
  expect(m).toContain('-- Replaces: api.website_v2_course_item')
  expect(m).toContain('-- Retires: nothing')
})
