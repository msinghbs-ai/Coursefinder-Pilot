// Guards: G3 and Website API v2 additive-only rule (CLAUDE.md); F-SCH developer field contract step 2 (Platform Admin 12 Nov 2026 20:19), release held until the developer communication and release authorisation (standing rule 12 Nov 2026 11:50)
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261113069000_cf247_website_api_v2_scholarship_fields.sql', 'utf8')
const edit = m.slice(m.indexOf("select pg_temp.edit_n('api.website_v2_scholarship_item(uuid)'"), m.indexOf('-- the approved consumer change'))
const [oldText, newText] = edit.split('$o$')[1] !== undefined ? [edit.split('$o$')[1], edit.split('$n$')[1]] : ['', '']

test('approved, gated on release authorisation, one md5-guarded edit, baseline re-taken', () => {
  expect(m).toMatch(/^-- Consumer API change approved: Platform Admin, 12 Nov 2026 20:19 AEDT/m)
  expect(m).toContain("s.key = 'api.v2_scholarship_fields_released'), 0) < 1 then")
  expect(m.indexOf('do $gate$')).toBeLessThan(m.indexOf("select pg_temp.edit_n("))
  expect(m).toContain("'d1792cc7161101ce8c22abad70ecbd36'")
  expect(m).toContain("select security.consumer_api_rebaseline_v1(")
})

test('additive only: the old object is kept whole and the new keys are appended beside it', () => {
  expect(newText.startsWith(oldText.replace(/\n  from s, p$/, ''))).toBe(true) // every existing key stays, unchanged and in place
  for (const k of ['description', 'award_type', 'sponsor', 'programme', 'award_code', 'benefits', 'application', 'award_duration', 'academic_year',
    'nationality_eligibility_status', 'excluded_nationality_codes', 'nationality_regions']) expect(newText).toContain(`'${k}', `)
  expect(newText).toContain("else 'unknown' end") // an empty list is never unrestricted
  expect(newText).not.toMatch(/'(scholarship_id|name|citizenship_eligibility|scholarship_type)', /) // no existing key redefined
})
