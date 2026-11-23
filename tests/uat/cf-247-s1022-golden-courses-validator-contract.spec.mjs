// Guards: Platform Admin 24 Nov 2026 05:54 and 06:27 AEDT (UI-UX plan v1.2 slice 6: golden-record validator for the UAT feedback-4 courses; read-only; reports in CI and the 08:00 digest)
// s1022: scripts/ci/validate-golden-courses.mjs reads the benchmark fixture, applies the pre-admission gate checks (s1020, s1021) to what is held,
// reads each test course through the Website API v3 course read, writes nothing, and never turns a data gap into a red run unless --strict.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { gaps, COURSE_SQL } from '../../scripts/ci/validate-golden-courses.mjs'

const SRC = fs.readFileSync('scripts/ci/validate-golden-courses.mjs', 'utf8')
const WF = fs.readFileSync('.github/workflows/golden-courses.yml', 'utf8')
const FX = JSON.parse(fs.readFileSync('tests/fixtures/golden-courses/feedback-4.json', 'utf8'))

test('s1022: the fixture names the feedback-4 providers and the VU EBCL test course under both VU records', () => {
  expect(FX.providers.map((p) => p.id)).toEqual(expect.arrayContaining(['bac82321-ded7-4e10-a71d-b18f3ae4d1c7', '0f5373c8-d724-4303-9267-739530a5ce53',
    'de2201a1-69ee-40ff-b6aa-0e54e535e6c0', '1822b40a-8b13-44dc-8c37-106ae31bb447', 'dce54a01-39c1-4bdf-877d-b67da3afc81e']))
  expect(FX.courses.filter((c) => c.label.startsWith('VU EBCL'))).toHaveLength(2)
})

test('s1022: the checks are the gate checks, with the fee window from the G2 setting and no year written in', () => {
  const q = COURSE_SQL('true')
  expect(q).toContain("security.pipeline_num_v1('gates.fee_year_ahead', 1)")
  expect(q).toContain("at time zone 'Australia/Melbourne'")
  expect(q).toContain("k in ('listening', 'reading', 'writing', 'speaking')")
  expect(q).toContain("t.code in ('IELTS', 'PTE', 'TOEFL_IBT')")
  expect(q).toContain('k.provider_id <> c.provider_id')
  expect(q).toContain("jsonb_typeof(k.value_json -> 'scale') = 'number'")
  expect(q).not.toMatch(/\b20[2-3][0-9]\b/)
  expect(gaps({ fee_ok: false, fee_years: [2025], ielts: true, pte_ok: false, toefl_ok: true, campuses: 0, campuses_other: 1, gpa: 3, gpa_scaled: 1 }))
    .toEqual(['fee year (held: 2025)', 'PTE with four bands', 'campus', '1 campus link(s) to another provider', '2 scholarship GPA threshold(s) without a scale'])
  expect(gaps({ fee_ok: true, fee_years: [], ielts: true, pte_ok: true, toefl_ok: true, campuses: 1, campuses_other: 0, gpa: 0, gpa_scaled: 0 })).toEqual([])
})

test('s1022: read-only, v3 read per test course, daily before the digest, never red on a data gap', () => {
  expect(SRC).toContain('public.website_v3_course(')
  expect(SRC).toContain('set transaction read only; select public.website_v3_course(')
  expect(SRC).toContain('readV3(r.stable_key)')
  expect(COURSE_SQL('true')).toContain('from search.course_documents d where d.course_id = c.id')
  expect(SRC).not.toContain("publication_status === 'published'")
  expect(SRC).toContain("from '../boost-live-lib.mjs'")
  expect(SRC).not.toMatch(/\b(insert|update|delete)\s+(into|from)?\s*[a-z_]+\.|\bset_config\(|svc_pilot_submit_nonce|worker\(/i)
  expect(WF).toContain('cron: "35 20 * * *"')
  expect(WF).toContain('if [ "$REF" != "fxcwkweaxjtknorudmwp" ]')
  expect(WF).toContain('contents: read')
  expect(WF).not.toContain('--strict')
})
