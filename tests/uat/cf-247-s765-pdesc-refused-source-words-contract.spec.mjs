// Guards: Provider description source words F-PDESC.01/.02 (Platform Admin 19 Nov 2026 08:17): a page whose address has dates, calendar or timetable as a part is never a description source; the words are kept in the refused list pdesc.refused_path_words (there is no allow list), a missing word is put back, no word is removed, and the migration fails if any of the three is not refused.
// CF-247 S765. Migration 20261119090000_cf247_pdesc_route_gpt41_mini_stored_page_drain. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const code = fs.readFileSync('supabase/migrations/20261119090000_cf247_pdesc_route_gpt41_mini_stored_page_drain.sql', 'utf8').split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const seed = fs.readdirSync('supabase/migrations-archive').concat(fs.readdirSync('supabase/migrations')).filter((f) => f.endsWith('.sql'))
  .map((f) => fs.readFileSync((fs.existsSync('supabase/migrations/' + f) ? 'supabase/migrations/' : 'supabase/migrations-archive/') + f, 'utf8')).filter((t) => t.includes('pdesc.refused_path_words'))

test('the three words are put back when missing and never taken out', () => {
  expect(code).toContain("from unnest(array['dates', 'calendar', 'timetable']) w where not s.value ? w),")
  expect(code).toContain("where s.toolset_key = 'pipeline' and s.key = 'pdesc.refused_path_words' and not s.value ?& array['dates', 'calendar', 'timetable'];")
  expect(code).toContain('set value = s.value || (select coalesce(jsonb_agg(w)')
  expect(code).not.toMatch(/refused_path_words'[^;]*value\s*-\s|value\s*#-/)
})

test('the migration fails unless all three are refused source words', () => {
  expect(code).toContain("raise exception 'post-check: dates, calendar or timetable is not a refused source word';")
})

test('the list is a refuse list in the checked-in history: a page address with one of its words is never a description source', () => {
  expect(seed.length).toBeGreaterThan(0)
  expect(seed.some((t) => /"dates", "calendar", "timetable"|'dates', 'calendar', 'timetable'|dates.{0,12}calendar.{0,12}timetable/.test(t))).toBe(true)
  expect(seed.some((t) => /is never a description source/.test(t))).toBe(true)
})
