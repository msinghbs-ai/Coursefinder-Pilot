// Guards: Website API v3 build brief WP-2.1 (register O14, REQ-55; Platform Admin 12 Nov 2026 22:37): OET and CELPIP read as English tests; a letter grade is never turned into a number; the five earlier tests read as before
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFileSync } from 'node:child_process'
import { pathToFileURL } from 'node:url'

const m = fs.readFileSync('supabase/migrations/20261113250000_cf247_english_tests_oet_celpip.sql', 'utf8')
async function parser() {
  const out = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'wp21-')), 'policy.mjs')
  execFileSync('npx', ['esbuild', 'supabase/functions/coverage-sweep/policy.ts', '--format=esm', `--outfile=${out}`, '--log-level=error'])
  return import(pathToFileURL(out).href)
}

test('two reference rows, added only; no function, setting or job', () => {
  expect(m).toContain("('OET', 'Occupational English Test', 'active', '{\"min\": 0, \"max\": 500, \"step\": 10}'::jsonb)")
  expect(m).toContain("('CELPIP', 'CELPIP', 'active', '{\"min\": 1, \"max\": 12, \"step\": 1}'::jsonb)")
  expect(m).toContain('on conflict (code) do nothing;')
  expect(m).not.toMatch(/create (or replace )?(function|table)|cron\.schedule|platform_toolset_settings\(/i)
})

test('OET: numeric score only; a letter grade stays unread', async () => {
  const { parseScore, englishPolicy } = await parser()
  expect(parseScore('OET', '350 overall, 350 in each sub-test')).toEqual({ overall: 350, comps: { listening: 350, reading: 350, writing: 350, speaking: 350 } })
  expect(parseScore('OET', 'B in each sub-test')).toBeNull()
  expect(parseScore('OET', 'Grade B')).toBeNull()
  expect(parseScore('OET', '355')).toBeNull()   // not an OET score (steps of 10)
  expect(parseScore('OET', '6.5')).toBeNull()
  const p = englishPolicy('All postgraduate coursework programs require IELTS 7.0 overall with no band below 7.0, OET minimum score of 350.')
  expect(p.defaults.postgraduate.map((r) => `${r.test_code}:${r.overall_score}`)).toEqual(['IELTS:7', 'OET:350'])
})

test('CELPIP: whole level 4 to 12, with skills', async () => {
  const { parseScore, englishPolicy } = await parser()
  expect(parseScore('CELPIP', 'Overall 8 with no skill below 7')).toEqual({ overall: 8, comps: { listening: 7, reading: 7, writing: 7, speaking: 7 } })
  expect(parseScore('CELPIP', '7.5')).toBeNull()
  expect(parseScore('CELPIP', '3')).toBeNull()
  expect(parseScore('CELPIP', '13')).toBeNull()
  const p = englishPolicy('All undergraduate programs require IELTS 6.5 overall with no band below 6.0, CELPIP overall 8.')
  expect(p.defaults.undergraduate.map((r) => `${r.test_code}:${r.overall_score}`)).toEqual(['IELTS:6.5', 'CELPIP:8'])
})

test('the add-tests job adds only tests learnt after approval, and the earlier tests read as before', async () => {
  const { ADDED_TESTS, ADD_TESTS_PARSER, POLICY_PARSER, englishPolicy } = await parser()
  expect(ADDED_TESTS).toEqual(['DET', 'OET', 'CELPIP'])
  expect(ADD_TESTS_PARSER).toBe('provider-policy-v0.3.1')
  expect(POLICY_PARSER).toBe('provider-policy-v0.3.1')
  const p = englishPolicy('All postgraduate coursework programs require IELTS 6.5 overall with no band below 6.0, TOEFL iBT 90, Duolingo English Test (DET) minimum score of 120.')
  expect(p.defaults.postgraduate.map((r) => `${r.test_code}:${r.overall_score}`)).toEqual(['IELTS:6.5', 'TOEFL_IBT:90', 'DET:120'])
})
