// Guards: F-CDESC rejection memory counts person decisions only (Platform Admin 16 Nov 2026 11:32): the course description machine rule's rejected_before_course, rejected_before_page and rejected_before_text tests leave out 'superseded' (the platform's own decision), and the rule version is cdesc-machine-v2 so every waiting item is evaluated again
// CF-247 S558. Migration 20261116080000_cf247_cdesc_rejection_memory_person_only. md5-guarded edits in place of five live functions.
// G2, G3 and housekeeping are guarded centrally by s32, s57 and s42; this spec guards the rule change itself.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations-archive/20261116080000_cf247_cdesc_rejection_memory_person_only.sql', 'utf8')
const code = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const edits = [...code.matchAll(/select pg_temp\.edit_all\('([^']+)', '([0-9a-f]{32})', '([0-9a-f]{32})',/g)].map((m) => ({ sig: m[1], before: m[2], after: m[3] }))

test('the three rejection-memory tests leave out superseded, and nothing else in the rule changes', () => {
  const check = code.slice(code.indexOf("edit_all('security.course_description_machine_check_v1(uuid)'"), code.indexOf("edit_all('security.course_description_machine_admit_v1"))
  expect(check).toContain("$o$status not in ('pending', 'approved', 'edited_approved')$o$")
  expect(check).toContain("$n$status not in ('pending', 'approved', 'edited_approved', 'superseded')$n$")
  expect(check).toMatch(/array\[3, 1, 1\]\)/)
  // person decisions still count: no status a person sets is added to the list
  expect(code).not.toMatch(/'(rejected|edited_rejected|returned)'\s*\)\$n\$/)
  expect(code).toContain("raise exception 'post-check: the three rejection-memory tests leave out superseded'")
})

test('the rule version moves to cdesc-machine-v2 in the five functions that name it, each edit md5-guarded before and after', () => {
  expect(edits.map((e) => e.sig).sort()).toEqual([
    'security.cdesc_prompt_supersede_v1()',
    'security.course_description_machine_admit_v1(uuid,text)',
    'security.course_description_machine_check_v1(uuid)',
    'security.course_description_machine_policy_stamp_v1()',
    'security.course_description_machine_shadow_v1(integer,integer)',
  ])
  for (const e of edits) expect(e.before, e.sig).not.toBe(e.after)
  expect(code).toContain("$n$md5('cdesc-machine-v2|' ||$n$")
  expect((code.match(/\$n\$[^$]*cdesc-machine-v1/g) || []).length).toBe(0)
  expect(code).toContain("raise exception 'post-check: the rule version is cdesc-machine-v2 in every function that names it'")
})

test('no setting, job or consumer API object moves; G3 is checked before and after', () => {
  expect(code).not.toMatch(/\b(update|insert into|delete from)\s+pipeline\.platform_toolset_settings/i)
  expect(code).not.toMatch(/cron\.(schedule|unschedule|alter_job)/)
  expect(code).not.toMatch(/\b(drop|truncate)\s/i)
  expect(code).toContain("security.consumer_api_check_v1() - 'checked_at'")
  expect(code).toContain("security.pipeline_num_v1('enrich.course_description_pending_global_max', 0) <> 1500")
  expect(M).toMatch(/^-- Replaces: /m)
  expect(M).toMatch(/^-- Retires: nothing/m)
})
