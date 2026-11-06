// Guards: Platform Admin 6 Nov 2026 09:44 §3 (verbatim stored source pages for regression testing) and §4 (realistic source fixtures) for English requirements: each of the six stored pages is
// present, is byte-for-byte the page the platform stored (sha256 = content_hash), and the v0.3.0 parser reads it without inventing a requirement.
// All six extracts are present. The missing/changed-file guard still fails clearly, never skips; their original acquisition was governed read-only provider_facts_inspect (no write or paid read).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import crypto from 'node:crypto'
import { STORED, loadParser } from '../fixtures/english-requirements/baseline.mjs'

const DIR = 'tests/fixtures/english-requirements/pages'
const IDS = ['a1a0f40d-001a-4df2-848e-0a49812a0ac8', '002ff3bb-4106-4844-b682-b2b6b0b90a27', '1214c1b4-8f19-4b55-b4a6-08a098bbaac4', '55d9b299-d974-4db5-8ec1-ec0af352f67f', 'a65734e6-d5f8-487b-9979-8b7708de4ccd', '8e0fc6c9-9d45-4d16-87cc-12b13513dc29']
const sources = STORED.providers.flatMap((p) => p.english_sources.map((s) => ({ provider: p.provider, ...s })))
const TESTS = new Set(['IELTS', 'PTE', 'TOEFL_IBT', 'CAE', 'DET'])

for (const id of IDS) {
  test(`stored page ${id}: present, matches its content hash, and reads without an invented requirement`, async () => {
    const src = sources.find((s) => s.fact_source_id === id)
    expect(src, `stored-outcomes.json lists fact source ${id}`).toBeTruthy()
    const file = `${DIR}/${id}.md`
    expect(fs.existsSync(file), `MISSING ${file} (${src.provider}). Run the read-only provider_facts_inspect call from the PR description for fact source ${id} and save the text there; until then this governed fixture is absent and this test is red on purpose.`).toBe(true)
    const text = fs.readFileSync(file, 'utf8')
    expect(crypto.createHash('sha256').update(text, 'utf8').digest('hex'), `${file} must be the stored page byte for byte`).toBe(src.content_hash)
    const { englishPolicy, POLICY_PARSER } = await loadParser()
    const r = englishPolicy(text)
    expect(r.parser).toBe(POLICY_PARSER)
    for (const reqs of [...Object.values(r.defaults || {}), ...(r.groups || []).map((g) => g.reqs)])
      for (const q of reqs) { expect(TESTS.has(q.test_code), q.test_code).toBe(true); expect(Number(q.overall_score)).toBeGreaterThan(0) }
    for (const g of r.groups || []) expect(g.group_name.trim().length).toBeGreaterThan(1)
  })
}

test('UNSW main English page: faculty rows are course groups and never a university default', async () => {
  const id = 'a1a0f40d-001a-4df2-848e-0a49812a0ac8'
  expect(fs.existsSync(`${DIR}/${id}.md`), `MISSING ${DIR}/${id}.md: run the provider_facts_inspect call from the PR description`).toBe(true)
  const { englishPolicy } = await loadParser()
  const r = englishPolicy(fs.readFileSync(`${DIR}/${id}.md`, 'utf8'))
  expect(r.groups.length, 'the faculty table is read as groups').toBeGreaterThan(0)
  expect(r.defaults, 'a faculty score is not the university default').toEqual({})
})

test('UNSW main English page, full text: 7 faculties x 2 levels with IELTS, TOEFL iBT, PTE and Cambridge scores, and the courses the cells list as exceptions keep their own score', async () => {
  const { englishPolicy } = await loadParser()
  const r = englishPolicy(fs.readFileSync(`${DIR}/a1a0f40d-001a-4df2-848e-0a49812a0ac8.md`, 'utf8'))
  expect(r.style).toBe('course_groups')
  expect(r.defaults).toEqual({})
  expect(r.groups.length).toBe(14)
  const score = (name, level, code) => r.groups.find((g) => g.group_name === name && g.level === level).reqs.find((q) => q.test_code === code).overall_score
  const FAC = { 'Arts, Design & Architecture': [6.5, 90, 64, 176], Business: [7, 94, 65, 185], Engineering: [6.5, 90, 64, 176], 'Law & Justice': [7, 94, 65, 185], 'Medicine & Health': [6.5, 90, 64, 176], Science: [6.5, 90, 64, 176], 'UNSW Canberra': [6.5, 90, 64, 176] }
  for (const [name, want] of Object.entries(FAC)) for (const level of ['undergraduate', 'postgraduate'])
    expect(['IELTS', 'TOEFL_IBT', 'PTE', 'CAE'].map((c) => score(name, level, c)), `${name} ${level}`).toEqual(want)
  const ex = (name, level, code) => r.exceptions.find((e) => e.name === name && e.level === level && e.reqs[0]?.test_code === code)?.reqs[0].overall_score
  expect(ex('Bachelor of Education (Secondary) (Honours)', 'undergraduate', 'IELTS')).toBe(7.5)
  expect(ex('Bachelor of Criminology & Criminal Justice', 'undergraduate', 'IELTS')).toBe(6.5)
  expect(ex('Master of Teaching (Primary & Secondary)', 'postgraduate', 'IELTS')).toBe(7.5)
  expect(ex('Bachelor of Pharmaceutical Medicine/Master of Pharmacy', 'undergraduate', 'IELTS')).toBe(7)
})

test('UNSW international entry-requirements page: it sends the reader to each course page, so it gives no rule', async () => {
  const { englishPolicy } = await loadParser()
  const r = englishPolicy(fs.readFileSync(`${DIR}/002ff3bb-4106-4844-b682-b2b6b0b90a27.md`, 'utf8'))
  expect(r.defaults).toEqual({})
  expect(r.groups ?? []).toEqual([])
  expect(r.style).toBe('course_specific')
})

