// Guards: course page check false positives (Platform Admin 16 Nov 2026 20:14, Layer 4 report §7): a campus named like the provider is not "another campus"; an address whose remaining words name this course (double degrees, Dean's Scholar) is not a sibling course's; the fix never accepts a page by itself
// CF-247 S562. Migration 20261116150000_cf247_finder_campus_sibling_false_positives (md5-guarded edit of security.course_page_check_v1).
// G2, G3 and housekeeping are guarded centrally by s32, s57 and s42.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261116150000_cf247_finder_campus_sibling_false_positives.sql', 'utf8')

test('the edit is md5-guarded before and after, each text edit applies exactly once, and the post-check reads the recorded body', () => {
  expect(M).toContain("select pg_temp.edit_all('security.course_page_check_v1(uuid,text,text,text)', '38c776ca90378d866167390f7d40d42b', 'c0183b440fa7feb8dee1d624b1ff2224',")
  expect(M).toContain("if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)'")
  expect((M.match(/c0183b440fa7feb8dee1d624b1ff2224/g) || []).length).toBe(2)
})

test('campus rule: a campus whose name is within the provider canonical, display or short name is not another campus', () => {
  expect(M).toContain('unnest(array[p2.canonical_name, p2.display_name, p2.short_name]) pn(nm)')
  expect(M).toContain("position(' ' || security.course_title_key(k2.name) || ' ' in ' ' || security.course_title_key(pn.nm) || ' ') > 0)")
})

test('sibling rule: the rest of the address must carry a word of this title the sibling lacks and no long foreign word; the limit is a setting', () => {
  expect(M).toContain("security.pipeline_num_v1('binding.sibling_tail_abbrev_max_chars', 4)::int abbrev_max")
  expect(M).toContain('where length(w) > (select s.abbrev_max from s)')
  expect(M).toContain("regexp_split_to_array(security.course_title_key(replace(t.ctitle, '''', '')), ' ')")
  expect(M).toContain("'binding.sibling_tail_abbrev_max_chars', 'Course page check: abbreviation length after a sibling course''s name'")
})

test('nothing is accepted, dropped or deleted by this change', () => {
  const code = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
  expect(code).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(code).not.toMatch(/'bind'|'accept'/)
})
