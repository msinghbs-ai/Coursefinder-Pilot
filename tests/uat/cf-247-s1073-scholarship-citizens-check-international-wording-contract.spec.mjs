// Guards: Platform Admin 24 Nov 2026 18:02 AEDT (S1-RM-Design s1073, scholarship publication recovery from existing data, no relaxation of rules): the "provider page limits it to citizens and residents" publication check accepts precise international phrases (worker INTL_WORDS vocabulary), never bare "overseas" or "foreign", and still holds an excerpt that excludes international students; no other check changes; G3 frozen
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261125030000_cf247_s1073_scholarship_citizens_check_international_wording.sql', 'utf8')
// the clearing and excluding patterns exactly as the migration writes them into the function (SQL string escapes undone)
const unq = (s) => s.replace(/\\\\/g, '\\')
const clear = new RegExp(unq(MIG.match(/~\* ''(\\\\m\(foreign nationals[^']+)''\\n/)[1]).replace(/\\m|\\M/g, '\\b'), 'i')
const exclude = new RegExp(unq(MIG.match(/!~\* ''(\(not\|never[^']+)''\)\\n/)[1]), 'i')
const holds = (ex) => /citizen|permanent resident|domestic student/i.test(ex) && !/international/i.test(ex) && !(clear.test(ex) && !exclude.test(ex))

test('s1073: excerpts that admit international students in other words are not held as citizens-only', () => {
  for (const ex of ['Open to Canadian citizens. Open to permanent residents. Open to foreign nationals holding Canadian study permits.',
    'You must be a: Canadian Citizen studying at a Canadian or foreign institution, or Permanent resident of Canada or foreign national enrolled in a doctoral program',
    'Canadian citizen or permanent resident of Canada* ... Visa Students. Foreign students who are studying in Ontario under a temporary resident visa are eligible',
    'To be eligible for a GUIPRS, an applicant must: not be a domestic student, as defined as being a student who is an Australian citizen']) expect(holds(ex), ex).toBe(false)
})

test('s1073: citizens-only excerpts, bare "overseas" and excluding wording still hold', () => {
  for (const ex of ['be an Australian citizen or permanent resident, be born overseas, recently migrated to Australia',
    'Applicants must be Australian Citizens or Permanent Residents.',
    'You must be an Australian citizen and must not hold a student visa',
    'Open to Australian citizens; overseas students are not eligible',
    'Be a Canadian citizen studying at a foreign institution']) expect(holds(ex), ex).toBe(true)
})

test('s1073: one line changed in place from the pinned definition; nothing else may move', () => {
  expect(MIG).toContain("'557adb0a40cd99edb4623bd4dbd1eebc'")
  expect(MIG).toContain("expected exactly one citizens-and-residents line")
  expect(MIG).toContain('records changed a reason other than the citizens-and-residents check')
  expect(MIG).toContain('records newly held by the citizens-and-residents check')
  expect(MIG).toMatch(/^-- Replaces: /m)
  expect(MIG).toMatch(/^-- Retires: /m)
  expect((MIG.match(/\(v->>'functions'\)::int <> 75|\(v_api->>'functions'\)::int <> 75/g) || []).length).toBe(2)
  expect(MIG).not.toMatch(/website_v[23]_|zoho_edge|cron\.(schedule|unschedule|alter_job)|\bdrop (table|function|index|schema|view|trigger)|delete from |truncate |update scholarship\./i)
})
