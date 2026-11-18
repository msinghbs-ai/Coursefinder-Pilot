// Guards: Course descriptions are 1 to 2 sentences and a description from the course's own page is admitted on its proof (Platform Admin 18 Nov 2026, chat S1-Courses, s662): prompt cdesc-source-grounded-v4 asks for 1 to 2 sentences (about 180 to 360 characters) with no intake, campus, fee or duration sentence and keeps quote grounding per sentence; the database limits are 2 sentences and 360 characters; cdesc-machine-v2 does not apply the 0.1 margin when the page proves the course by its own CRICOS or NZQA code, or its unshared exact title or title address, and no other course shares the page; the provider's first-description hold is off by setting.
// CF-247 S662. Worker coverage-sweep v1.0.25 (course-text.ts), migration 20261119060000 (md5-guarded edits of security.cdesc_prompt_version_v1, course_description_machine_check_v1, enrich_course_text_record_v1, course_description_promote_held_v1). G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import crypto from 'node:crypto'
import { CDESC_PROMPT_VERSION, CDESC_SYSTEM, CDESC_SYSTEM_SHA256, CDESC_SYSTEM_V3, courseTextLengthNote } from '../../supabase/functions/coverage-sweep/course-text.ts'

const M = fs.readFileSync('supabase/migrations/20261119060000_cf247_s662_s664_cdesc_one_two_sentences_identity_proof.sql', 'utf8')
const code = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')

test('prompt v4: 1 to 2 sentences, no intake, campus, fee or duration sentence, grounding unchanged; v3 kept as sent', () => {
  expect(CDESC_PROMPT_VERSION).toBe('cdesc-source-grounded-v4')
  expect(crypto.createHash('sha256').update(CDESC_SYSTEM).digest('hex')).toBe(CDESC_SYSTEM_SHA256)
  expect(CDESC_SYSTEM).toContain('Write 1–2 complete factual sentences, never more than 2. Aim for 180–360 characters in all;')
  expect(CDESC_SYSTEM).toContain('academic focus')
  for (const w of ['intake or start dates', 'street addresses', 'tuition fees', 'full-time or part-time']) expect(CDESC_SYSTEM).toContain(w)
  for (const kept of ['Every sentence must be supported by the spans its claims cite', 'Do not copy complete source sentences', 'Do not open with, and do not write, a sentence that only introduces the course'])
    expect(CDESC_SYSTEM).toContain(kept)
  expect(CDESC_SYSTEM).not.toContain('Write 2–4 complete factual sentences')
  // only the length line changed: putting v3's line back gives v3
  const back = CDESC_SYSTEM.replace(/Write 1–2 complete factual sentences[\s\S]*?State distinctive subject matter/, 'Write 2–4 complete factual sentences where evidence supports them. Prefer about\n55–100 words if useful facts support that length; shorter is acceptable when evidence is thin.\nState distinctive subject matter')
    .replaceAll('cdesc-source-grounded-v4', 'cdesc-source-grounded-v3')
  expect(back).toBe(CDESC_SYSTEM_V3)
  expect(IX).toContain('const WORKER = "coverage-sweep-worker-v1.0.25"')
})

test('the database releases v4 with the worker, and the limits the check applies are 2 sentences and 360 characters', () => {
  expect(code).toContain("select pg_temp.edit_all('security.cdesc_prompt_version_v1()', '46449a8715ab34d3826ec80dc9e1724b', '73f9c9cf6bec7216d20f790edcc409a1'")
  expect(code).toContain(`'${CDESC_SYSTEM_SHA256}'`)
  expect(code).toMatch(/set value = to_jsonb\(2\)[\s\S]*?key = 'enrich\.course_description_max_sentences'/)
  expect(code).toMatch(/set value = to_jsonb\(360\)[\s\S]*?key = 'enrich\.course_description_max_chars'/)
  expect(courseTextLengthNote({ min_sentences: 1, max_sentences: 2, max_chars: 360 })).toBe('Description length: 1 to 2 sentences, at most 360 characters in all (the sentences, not the quotes).\n')
})

test('identity proof: the margin is waived only for the course’s own code or unshared exact title, never for a shared page, and behind a setting', () => {
  expect(code).toContain("select pg_temp.edit_all('security.course_description_machine_check_v1(uuid)', '1be689ae7ed55af7899088257c35e331', 'b0227cfb868d9e1d56c9d1056adbbd98'")
  expect(code).toContain("v_proof := security.pipeline_num_v1('enrich.course_description_identity_proof_on', 0) >= 1")
  expect(code).toContain("and (g.identity_basis in ('cricos_code', 'nzqa_code')")
  expect(code).toContain("or ((g.identity_basis = 'exact_title'")
  // a shared page (another course bound to the same address or stored copy) never passes; nor a title another active course of the provider shares
  expect(code).toContain('and not exists (select 1 from pipeline.coverage_course_pages g3 where g3.provider_id = g.provider_id and g3.course_id <> g.course_id')
  expect(code).toContain("security.cdesc_norm_v1(c4.canonical_title) = security.cdesc_norm_v1(c.canonical_title)")
  expect(code).toContain("if not v_proof and (g.basis = 'ai_match' or")
  // degree name, title and level, field and award stay with a person
  expect(code).not.toMatch(/identity_basis in \([^)]*'degree_name'/)
  expect(code).toContain("'identity_proof', v_proof))")
  expect(code).toMatch(/'enrich\.course_description_identity_proof_on'[\s\S]*?to_jsonb\(1\), 0, 1, 'switch'/)
})

test('first-description hold: off by setting, the reading goes to the machine rule; the card reason is plain', () => {
  expect(code).toContain("if security.pipeline_num_v1('enrich.course_description_first_hold_on', 1) >= 1 and security.cdesc_provider_slots_v1(v_pid) <= 0 then")
  expect(code).toMatch(/'enrich\.course_description_first_hold_on'[\s\S]*?to_jsonb\(0\), 0, 1, 'switch'/)
  expect(code).toContain("v_slots := case when security.pipeline_num_v1('enrich.course_description_first_hold_on', 1) < 1 then security.pipeline_num_v1('enrich.course_text_items_per_day', 500)::int")
  expect(code).toContain('it waits here only when a check did not pass (the reason is shown).')
  // the old reason is only ever an edit's "before" text
  const after = [...code.matchAll(/\$n\$([\s\S]*?)\$n\$/g)].map((m) => m[1]).join('\n')
  expect(after).not.toContain("This is one of the provider''s first course descriptions")
})

test('no new table or function; no overwrite; machine switch untouched', () => {
  expect(code).not.toMatch(/create (table|or replace function (security|public|pipeline|api)\.)/i)
  expect(code).toContain("raise exception 'post-check: no function is added or removed'")
  expect(code).not.toMatch(/update catalogue\.courses/)
  expect(code).not.toMatch(/key = 'enrich\.course_description_machine_on'/)
})
