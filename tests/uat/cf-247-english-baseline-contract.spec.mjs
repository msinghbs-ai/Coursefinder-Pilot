// Guards: decision 19:14 §8 (Platform Admin 5 Nov 2026) for English requirements (Platform Admin 6 Nov 2026 08:12): today's English behaviour on stored evidence and the production-parity manifest of the English path, as the regression base for the English requirements PR
// Agent H, 6 Nov 2026. Plan: admin docs/platform/work-packages/2026-11-06-english-requirements-implementation-plan.md.
// Stored evidence only: tests/fixtures/english-requirements/stored-outcomes.json was read from production with SELECT; no page was fetched.
// The database round trip (fixture from the manifest, production constraints, svc_provider_policy_record) is tests/fixtures/english-requirements/run.sh.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import crypto from 'node:crypto'
import os from 'node:os'
import path from 'node:path'
import { spawnSync } from 'node:child_process'
import { STORED, provider, source, UNSW_MAIN, unswStoredCells, loadParser, recordInputs } from '../fixtures/english-requirements/baseline.mjs'

const M = JSON.parse(fs.readFileSync('tests/fixtures/english-requirements/manifests/english-path.json', 'utf8'))
const md5 = (s) => crypto.createHash('md5').update(s, 'utf8').digest('hex')
const fn = (sig) => M.functions.find((f) => f.sig === sig)

test('the English round trip fails before any parity PASS on a fixture producer or SQL execution error', () => {
  // Exercise the actual shell entry point with failing local executables. This
  // reproduces the masked-pipeline defect without connecting to any database.
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'english-fail-closed-'))
  const bin = path.join(dir, 'bin')
  fs.mkdirSync(bin)
  const executable = (name, source) => fs.writeFileSync(path.join(bin, name), source, { mode: 0o755 })
  executable('dropdb', '#!/bin/sh\nexit 0\n')
  executable('createdb', '#!/bin/sh\nexit 0\n')
  executable('node', `#!/bin/sh
case "$2" in
  fixture|check-sql)
    if [ "$EN_TEST_FAILURE" = "$2-generator" ]; then echo "INJECTED $EN_TEST_FAILURE" >&2; exit 39; fi
    echo 'select 1;';;
esac
exit 0
`)
  executable('psql', `#!/bin/sh
case "$*" in
  *'/fixture.sql'*) if [ "$EN_TEST_FAILURE" = fixture-sql ]; then echo 'INJECTED fixture-sql' >&2; exit 37; fi;;
  *'/check.sql'*) if [ "$EN_TEST_FAILURE" = parity-sql ]; then echo 'INJECTED parity-sql' >&2; exit 38; fi;;
esac
exit 0
`)
  try {
    for (const phase of ['fixture-generator', 'check-sql-generator', 'fixture-sql', 'parity-sql']) {
      const result = spawnSync('bash', ['tests/fixtures/english-requirements/run.sh'], {
        encoding: 'utf8', timeout: 10000,
        env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, PGHOST: '/tmp', EN_TEST_FAILURE: phase },
      })
      expect(result.status, phase).not.toBe(0)
      expect(result.stdout + result.stderr, phase).toContain(`INJECTED ${phase}`)
      expect(result.stdout, phase).not.toContain('PASS fixture built from the production manifest')
      expect(result.stdout, phase).not.toContain('english-requirements fixture round trip: passed')
    }
    const workflow = fs.readFileSync('.github/workflows/english-requirements-test.yml', 'utf8')
    expect(workflow).toMatch(/shell: bash/)
    expect(workflow).toMatch(/set -euo pipefail\s+bash tests\/fixtures\/english-requirements\/run\.sh 2>&1 \| tee/)
  } finally {
    fs.rmSync(dir, { recursive: true, force: true })
  }
})

// The live definitions the English requirements PR will replace or read (6 Nov 2026 08:31 AEDT). The PR's migration guards each on this md5.
const GUARDED = {
  'svc_provider_policy_record(uuid,jsonb)': '16b04b3170fae3fc97a5c632d7111fe5',
  'security.policy_auto_approve_v1()': '7b8f780d78c439546bcd4fc29da3bdb3',
  'security.central_pages_attach_v1()': '0e930780d50cbb65bea581d25a583356',
  'security.english_level_apply_v1(uuid,boolean)': '271a9600d80d8e6e3aa1e5644bd7ae80',
  'security.provider_english_plan_v1(uuid)': '60f5892657ef976634b12914d91f24a9',
  'admin_provider_policies_read(text,uuid)': 'fd6fdad2d073a4530d61e4f7d274ef31',
  'security.english_policy_in_force_all_v1(boolean)': 'bf32beb9bb284d4130101ffdaeb8eb40',
  'security.english_level_apply_all_v1(boolean)': 'c568deddebc50ce2482362f73e5e2af1',
}

test('the English path manifest is production parity: every definition matches its captured md5, and the guarded md5s are the live ones', () => {
  expect(M.tool).toBe('prod-parity-capture v1')
  expect(M.missing).toEqual([])
  for (const f of M.functions) expect(md5(f.def), f.sig).toBe(f.md5)
  for (const [sig, want] of Object.entries(GUARDED)) expect(fn(sig)?.md5, sig).toBe(want)
  const t = (fq) => M.tables.find((x) => x.fq === fq)
  // the production shapes the intake releases taught us to reproduce: checks, keys and grants, not a simplified table
  expect(t('pipeline.provider_policy_proposals').constraints.map((c) => c.name)).toEqual(expect.arrayContaining(['provider_policy_proposals_status_check', 'provider_policy_proposals_key']))
  expect(t('pipeline.provider_policy_proposals').constraints.find((c) => c.name === 'provider_policy_proposals_status_check').def).toContain("'proposed'::text, 'no_values'::text, 'approved'::text, 'rejected'::text, 'superseded'::text")
  expect(t('pipeline.provider_fact_sources').constraints.find((c) => c.name === 'provider_fact_sources_found_via_check').def).toContain("'search'::text, 'manual'::text")
  expect(t('catalogue.course_english_requirements').constraints.find((c) => c.name === 'course_english_requirements_course_id_english_test_id_key').def).toBe('UNIQUE (course_id, english_test_id)')
  expect(t('catalogue.course_english_requirements').triggers.map((g) => g.name)).toEqual(['evidence_entity_links_sync', 'evidence_lineage_stats_sync', 'manual_lock_guard'])
  expect(t('pipeline.layer4_review_items').triggers.length).toBe(9)
})

test('today: the policy route has no provider-type scope, and deterministic readings are never approved automatically', () => {
  // the university wording is in comments only: the attach, AI queue and record functions take every provider type
  for (const sig of ['security.central_pages_attach_v1()', 'security.central_ai_enqueue_v1(uuid)', 'svc_provider_policy_record(uuid,jsonb)'])
    expect(fn(sig).def, sig).not.toMatch(/provider_type|provider_types/)
  const auto = fn('security.policy_auto_approve_v1()').def
  expect(auto).toContain("and (x.parser like 'ai:%'")
  expect(auto).toContain("s.key = 'central.auto_approve_english_all'")
  // a group rule (Decision 265) is a proposal's levels and level_rules, matched by title pattern, only on courses whose page was read
  const lv = fn('security.english_level_apply_v1(uuid,boolean)').def
  expect(lv).toContain("jsonb_typeof(proposal->'levels') = 'object'")
  expect(lv).toContain("from jsonb_array_elements(coalesce(x.proposal->'level_rules', '[]'::jsonb)) with ordinality t(q, n)")
  expect(lv).toContain("where co.provider_id = x.provider_id and co.lifecycle_status = 'active' and g.read_status = 'read'")
  // a course's own reading is never replaced by a policy row (gaps only)
  expect(lv).toContain("and coalesce(e.source_requirement_key, '') not like 'policy:%'))::int;")
})

test('UNSW faculty rows: the stored cells are read as course groups by v0.3.0 (v0.2.5 dropped them), with no university default', async () => {
  const { englishPolicy, POLICY_PARSER } = await loadParser()
  expect(POLICY_PARSER).toBe('provider-policy-v0.3.1')
  const cells = unswStoredCells()
  expect(cells.faculty).toBe('Arts, Design & Architecture')
  expect(cells.ugCell).toBe('6.5 overall (min. 6.0 in each subtest)')
  const r = englishPolicy(cells.md)
  expect(r.style).toBe('course_groups')
  expect(r.signals).toEqual(['by_faculty'])
  expect(r.caveats).toEqual(['course_groups'])
  expect(r.defaults).toEqual({})  // a faculty's requirement is never a university default
  expect(r.exceptions).toEqual([])
  expect(r.groups.map((g) => [g.group_name, g.level, g.reqs[0].test_code, g.reqs[0].overall_score])).toEqual([
    ['Arts, Design & Architecture', 'undergraduate', 'IELTS', 6.5], ['Arts, Design & Architecture', 'postgraduate', 'IELTS', 6.5]])
})

test('today, recorded in production: UNSW, Auckland, Canterbury and Massey have no English rule, for four different reasons', () => {
  // UNSW: the main page was read by the deterministic parser as by_faculty with level conflicts; the AI reading of one faculty row was rejected
  const main = source('UNSW Sydney', UNSW_MAIN)
  expect(main.content_hash).toMatch(/^[0-9a-f]{64}$/)
  expect(main.storage_path).toContain(main.content_hash)
  const det = main.proposals.filter((x) => x.parser.startsWith('provider-policy-v0.2'))
  expect(det.every((x) => x.style === 'by_faculty' && x.status === 'superseded')).toBe(true)
  expect(det.at(-1).proposal.conflicts).toContain('undergraduate IELTS: 6 / 6.5')
  expect(main.proposals.find((x) => x.parser.startsWith('ai:')).status).toBe('rejected')
  expect(provider('UNSW Sydney').english_sources.some((s) => s.proposals.some((x) => x.status === 'approved'))).toBe(false)
  // Auckland: three stored pages, each read by the AI as course-specific with no values
  const auck = provider('University of Auckland').english_sources
  expect(auck.length).toBe(3)
  for (const s of auck) expect(s.proposals.find((x) => x.parser.startsWith('ai:'))).toMatchObject({ status: 'no_values', style: 'course_specific' })
  // Canterbury: the only stored page is the IELTS test centre of the Education faculty, not an admission rule (a page-finding gap)
  const cant = provider('University of Canterbury').english_sources
  expect(cant.map((s) => s.url)).toEqual(['https://www.canterbury.ac.nz/about-uc/our-structure/faculties/education-faculty/centre-for-assessment-and-monitoring/ielts'])
  // Massey: no English page stored; the only candidate (an English language courses page) scored under the attach threshold
  expect(provider('Massey University').english_sources).toEqual([])
  expect(provider('Massey University').central_search.english_candidates.every((c) => c.score < 4)).toBe(true)
})

test('today, through the live copy of svc_provider_policy_record: the stored cases file as run.sh checks them', async () => {
  const cases = await recordInputs()
  expect(cases.map((c) => [c.case, c.expect])).toEqual([
    ['unsw-faculty-table-today-parser', 'no_values'], ['unsw-stored-ai-reading-17-oct', 'proposed'],
    ['auckland-stored-ai-reading-1', 'no_values'], ['auckland-stored-ai-reading-2', 'no_values'], ['auckland-stored-ai-reading-3', 'no_values'],
  ])
  // the rule run.sh exercises in the database, read from the captured definition
  const rec = fn('svc_provider_policy_record(uuid,jsonb)').def
  expect(rec).toContain("when f.kind = 'english_policy' and (coalesce(p_parsed->'defaults', '{}'::jsonb) <> '{}'::jsonb")
  expect(rec).toContain("else 'no_values' end;")
  expect(STORED.source).toContain('read only')
})

