// Guards: S741 AER matrix machine row rules (Platform Admin 19 Nov 2026 05:42 AEDT, session S2-BOOST-AER, item 2): a completion requirement is read without the English-language clause the reader carried into its quote (an age, a duration in weeks, a CRICOS or training package code is not a score); a course row links to exactly one active course by printed title or printed award, never a stream, two candidates, a twin (Decision 276) or a label a person decided has no catalogue course; no AER v1 threshold changes.
// CF-247 S741. Migration 20261119075000_cf247_s741_aer_matrix_completion_clauses_course_link; database scenarios tests/fixtures/aer-matrix-s741 (workflow aer-matrix-s741-test.yml).
// G2, G3 and housekeeping are guarded centrally by s32, s57 and s42.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261119075000_cf247_s741_aer_matrix_completion_clauses_course_link.sql', 'utf8')
const run = fs.readFileSync('tests/fixtures/aer-matrix-s741/run.sh', 'utf8')
const sc = fs.readFileSync('tests/fixtures/aer-matrix-s741/scenarios.sql', 'utf8')
const live = fs.readFileSync('tests/fixtures/aer-matrix-s741/live-functions.sql', 'utf8')
const wf = fs.readFileSync('.github/workflows/aer-matrix-s741-test.yml', 'utf8')
const code = (t) => t.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')
const block = (tag) => M.split(`do $${tag}$`)[1].split(`end $${tag}$;`)[0]

test('three functions are edited in place under their live md5 of 19 Nov, each edit exactly once, with the after md5 recorded', () => {
  for (const [tag, sig, md5] of [['ex', 'security.aer_matrix_machine_exclusions_v1(uuid)', '51e0eb454501a4b87e419b1125bcf8c3'],
    ['ch', 'security.aer_matrix_machine_check_v1(uuid)', '80636b9af550a5896cfbb95ab1bd264c'], ['ad', 'security.aer_matrix_machine_admit_v1(uuid, text)', 'debe928ff881340e4712606d34e3e61d']]) {
    const b = block(tag)
    expect(b).toContain(`v_sig constant text := '${sig}'; v_before constant text := '${md5}'`)
    expect(b).toContain('must apply exactly once')
    expect(b).toContain('already applied')
    expect(M).toMatch(new RegExp(`--   ${sig.replace(/[().]/g, '\\$&')}\\s+${md5} -> [0-9a-f]{32}\\n`))
  }
  expect(M).toMatch(/-- Replaces: security\.aer_matrix_machine_exclusions_v1, security\.aer_matrix_machine_check_v1, security\.aer_matrix_machine_admit_v1/)
  expect(M).toContain('-- Retires: nothing')
  // G3: CREATE OR REPLACE of existing functions only (through execute of their own edited definition); no new function, table, view or trigger
  expect(code(M)).not.toMatch(/create\s+(or\s+replace\s+)?(function|table|view|trigger|materialized)/i)
  expect(live).toContain('CREATE OR REPLACE FUNCTION "security"."aer_matrix_machine_exclusions_v1"')
  expect(run).toContain('exclusions_v1 differs from live')
  expect(run).toContain('51e0eb454501a4b87e419b1125bcf8c3 -> $AFTER')
})

test('the completion rule reads the academic part only; a score after the English clause, or no completion words, keeps the row held', () => {
  const b = block('ex')
  expect(b).toContain("security.pipeline_num_v1('aer.matrix_completion_clauses_on', 0) >= 1 cl_on")
  expect(b).toContain(String.raw`\m(english\s+(language\s+)?(requirements?|proficiency)|ielts|toefl|pte|duolingo)\M`)
  expect(b).toContain(String.raw`\d+[\s-]*(years?|semesters?|months?|terms?|sessions?|weeks?)`)
  expect(b).toContain(String.raw`cricos(\s+course)?\s+code\s*:?\s*\d{5,6}[a-z]?|\m[a-z]{3}\d{5}\M`)
  expect(b).toContain(String.raw`(not cfg.cl_on or (`)
  for (const n of ['CP1 ', 'CP2 ', 'CP3 ', 'CP4 ', 'CP5 ', 'CP6 ', 'TP1 ']) expect(sc).toContain(`'${n}`)
  expect(sc).toContain('a percentage after the English clause keeps the row held')
})

test('course links: exactly one active course, by printed title less a training package code or by printed award; never a stream, a twin, two candidates or a person-rejected label', () => {
  const b = block('ex')
  expect(b).toContain("security.pipeline_num_v1('aer.matrix_course_link_rules_on', 0) >= 1 clk_on")
  expect(b).toContain("'aer.matrix_course_link_awards'")
  expect(b).toContain("security.entry_course_title_key_v1(regexp_replace(m0.course_label, '^\\s*[A-Za-z]{3}[0-9]{5}\\s*[–-]\\s*', ''))")
  expect(b).toContain("m0.course_label !~ '[\\[\\]()]'")
  expect(b).toContain("c.lifecycle_status = 'active'")
  expect(b).toContain("x.state = 'rejected'")
  expect(b).toContain("like lower(c.canonical_title) || ' (%'")
  expect(b).toContain('having count(distinct course_id) = 1')
  expect(b).toContain("when cfg.link_on and m.course_label is not null and m.course_id is null and m.link is null then 'course_unlinked'")
  for (const n of ['LK1 ', 'LK2 ', 'LK3 ', 'LK4 ', 'LK5 ', 'LK6 ', 'LK7 ', 'LK8 ', 'LK9 ', 'LK10 ', 'TP2 ']) expect(sc).toContain(`'${n}`)
  // the admit function writes the course only on a row with none (no overwrite)
  expect(block('ad')).toContain('and m.course_id is null and not (m.id = any(v_ex));')
  expect(block('ch')).toContain("'course_linked', jsonb_array_length(coalesce(v_inf->'course_links', '[]'::jsonb))")
})

test('both switches are settings created at 1, and 0 restores 18 Nov exactly; AER v1 stays frozen and the edited rule is validated before it stands', () => {
  expect(M).toMatch(/'aer\.matrix_completion_clauses_on', [^\n]+\n[^\n]+\n\s+'number', '1'::jsonb, 0, 1, 'on\/off'/)
  expect(M).toMatch(/'aer\.matrix_course_link_rules_on', [^\n]+\n[^\n]+\n\s+'number', '1'::jsonb, 0, 1, 'on\/off'/)
  expect(sc).toContain("'OFF both switches at 0 restore the 18 Nov result for every case exactly'")
  // no setting is changed (the mode stays as it is): the only setting rows are the three new ones, inserted with on conflict do nothing
  expect(code(M)).not.toMatch(/update\s+pipeline\.platform_toolset_settings|aer_machine_set_mode|set\s+value\s*=/i)
  expect(code(M)).toContain('on conflict (toolset_key, key) do nothing')
  expect(M).toContain("raise exception 'post-check: AER v1 thresholds must stay unchanged (Decision 276)'")
  expect(M).toContain("raise exception 'post-check: G3 must stay 75 functions and 48 relations'")
  expect(M).toContain("raise exception 'S741: the matrix validation did not pass on the edited rule: %'")
  expect(code(M)).not.toMatch(/delete from|drop (table|function)|truncate|website_v2_|zoho_edge_|create (or replace )?(view|function) (public|api)\./i)
})

test('the database scenarios run on an isolated PostgreSQL in CI, taking the settings and the edit from the migration byte for byte', () => {
  expect(run).toContain('refusing a Supabase project database')
  expect(run).toContain("sed -n '/^do \\$ex\\$$/,/^end \\$ex\\$;$/p'")
  expect(run).toContain('exclusions edit applied twice')
  expect(code(run + sc)).not.toMatch(/openrouter|firecrawl|curl /i)
  expect(wf).toContain('supabase/migrations/20261119075000_cf247_s741_aer_matrix_completion_clauses_course_link.sql')
  expect(wf).toContain('tests/fixtures/aer-matrix-s741/**')
  expect(wf).toContain('bash tests/fixtures/aer-matrix-s741/run.sh')
  expect(wf).toContain('postgres:16-alpine')
})
