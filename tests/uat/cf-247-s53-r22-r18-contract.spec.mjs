// CF-247 (S53): developer requests R22 (fewer full-load calls) and R18 (Duolingo English Test). Platform Admin 16 Oct 2026 23:44: "Start planning
// developer latest request & create feature number for each of them"; 17 Oct 2026 00:29: "Proceed with next steps".
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFileSync } from 'node:child_process'

const r22 = fs.readFileSync('supabase/migrations/20261017010000_cf247_r22_sync_pages.sql', 'utf8')
const r18 = fs.readFileSync('supabase/migrations/20261017020000_cf247_r18_duolingo.sql', 'utf8')
const worker = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')

async function parser() {
  const out = path.join(os.tmpdir(), `policy-s53-${process.pid}.mjs`)
  execFileSync('npx', ['esbuild', 'supabase/functions/coverage-sweep/policy.ts', '--format=esm', `--outfile=${out}`, '--log-level=error'])
  return import(out)
}

test('R22: sync pages up to 600 units by setting (range to 1000); only the value changes', () => {
  expect(r22).toContain("set max_value = 1000, value = to_jsonb(600)")
  expect(r22).toContain("where toolset_key = 'pipeline' and key = 'website.sync_page_max' and value = to_jsonb(200);")
  expect(r22).not.toMatch(/create or replace function/i)
})

test('R18 parser: Duolingo read as DET, overall only, 10 to 160 in steps of 5', async () => {
  const { englishPolicy, parseScore, POLICY_PARSER } = await parser()
  expect(POLICY_PARSER).toBe('provider-policy-v0.2.3')
  expect(parseScore('DET', '110 (no band less than 95)')).toEqual({ overall: 110, comps: {} })
  expect(parseScore('DET', 'Minimum score of 115')).toEqual({ overall: 115, comps: {} })
  expect(parseScore('DET', '92')).toBeNull()       // not a DET score (steps of 5)
  expect(parseScore('DET', '6.5')).toBeNull()
  const p = englishPolicy('All postgraduate coursework programs require IELTS 6.5 overall with no band below 6.0, TOEFL iBT 90, Duolingo English Test (DET) minimum score of 120.')
  expect(p.defaults.postgraduate.map((r) => `${r.test_code}:${r.overall_score}`)).toEqual(['IELTS:6.5', 'TOEFL_IBT:90', 'DET:120'])
  const t = englishPolicy('## Undergraduate\n\n| Test | Minimum |\n|---|---|\n| IELTS Academic | 6.5 overall, no band below 6.0 |\n| Duolingo English Test | 115 |\n')
  expect(t.defaults.undergraduate.find((r) => r.test_code === 'DET')).toMatchObject({ overall_score: 115, component_scores: {} })
  // existing tests unchanged
  expect(englishPolicy('Deakin’s current minimum IELTS requirement is 6.0 (CEFR B2) for undergraduate courses and 6.5 (CEFR C1) for postgraduate coursework courses.').defaults.undergraduate[0].overall_score).toBe(6)
})

test('R18: DET added to approved policies only where the IELTS matches, only to level-default courses, once per parser version; hourly job catalogued', () => {
  expect(r18).toContain("values ('DET', 'Duolingo English Test', 'active'")
  expect(r18).toContain("if v_ia is null or v_ip is distinct from v_ia then")
  expect(r18).toContain("where r.source_requirement_key = 'policy:' || x.id || ':ielts' and r.status = 'active' and r.overall_score = v_ia")
  expect(r18).toContain("and r.notes like 'Default for %'")
  expect(r18).toContain("on conflict (course_id, english_test_id) do nothing")
  expect(r18).toContain("coalesce(pp.proposal->'added_tests'->>'parser', '') is distinct from p_parser")
  expect(r18.indexOf("('policy-add-tests', 'Enrichment'")).toBeLessThan(r18.indexOf("select cron.schedule('policy-add-tests'"))
  expect(r18).toContain("security.pipeline_num_v1('batch.policy_add_tests', 40)")
  expect(worker).toContain('if (mode === "provider_facts_add_tests") {')
  expect(worker).toContain('rpc("svc_provider_english_add_tests_v1", { p_proposal_id: it.id, p_parser: POLICY_PARSER, p_parsed: parsed, p_error: err })')
})
