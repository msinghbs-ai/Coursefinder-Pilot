// Guards: CF-247 s895 and s896 (session S1-ELR-Central-Policy, Platform Admin 21 Nov 2026 07:48 AEDT): elr-central-v1.1 reads tables whose columns are study levels, values written before the test name, and reports values without a study level (English bands) instead of spreading them across levels; every university's stored central page without an elr-central reading is read again by v1.1 with no provider excluded, the route's parser name and its approval, plan and apply stay unchanged, and no job, table or setting is added
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { centralRead, ELR_CENTRAL_VERSION } from '../../supabase/functions/coverage-sweep/elr-central-reader.ts'

const MIG = fs.readFileSync('supabase/migrations/20261121080000_cf247_s895_s896_elr_central_v11.sql', 'utf8')
const tiers = (t) => Object.fromEntries(Object.entries(centralRead(t).defaults).map(([k, v]) => [k, v.map((x) => [x.test_code, x.overall_score])]))

test('v1.1 reads a table whose columns are study levels and whose rows are tests, quoting each row', () => {
  expect(ELR_CENTRAL_VERSION).toMatch(/^elr-central-v1\.[1-9]\d*$/)  // s904: v1.2 keeps every v1.1 reading
  const t = ['| Test | Undergraduate | Postgraduate coursework | Higher degree by research |', '|---|---|---|---|',
    '| IELTS Academic | 6.0 (no band below 5.5) | 6.5 (no band below 6.0) | 6.5 (6.0) |', '| TOEFL iBT | 79 | 90 | 90 |', '| PTE Academic | 58.5 | 64 | 64 |'].join('\n')
  expect(tiers(t)).toEqual({ undergraduate: [['IELTS', 6], ['TOEFL_IBT', 79], ['PTE', 58.5]], postgraduate: [['IELTS', 6.5], ['TOEFL_IBT', 90], ['PTE', 64]], research: [['IELTS', 6.5], ['TOEFL_IBT', 90], ['PTE', 64]] })
  expect(centralRead(t).defaults.undergraduate[2].quote).toBe('| PTE Academic | 58.5 | 64 | 64 |')
})

test('v1.1 reads a value written before the test name, quoted by the original line', () => {
  const t = ['## Undergraduate', 'Applicants need an overall band score of 6.5 in IELTS Academic, with no band below 6.0.'].join('\n')
  const r = centralRead(t)
  expect(tiers(t)).toEqual({ undergraduate: [['IELTS', 6.5]] })
  expect(r.defaults.undergraduate[0].quote).toBe('Applicants need an overall band score of 6.5 in IELTS Academic, with no band below 6.0.')
})

test('values without a study level (English bands) are reported, never spread across levels', () => {
  const t = ['English language bands', '| Band | IELTS | TOEFL iBT | PTE |', '|---|---|---|---|', '| Band A | 6.0 | 79 | 50 |', '| Band B | 6.5 | 85 | 58 |'].join('\n')
  const r = centralRead(t)
  expect(r.defaults).toEqual({})
  expect(r.values_found).toBe(6)
  expect(r.bands).toBe(true)
  // s904 (v1.2): rows labelled with a band are band definitions (kept for band-to-course matching), so they are no longer reported as untiered lines
  expect(Object.keys(r.band_defs)).toEqual(['band A', 'band B'])
})

test('s896: pages are read again by v1.1 with no provider excluded; the route name, approval, plan and apply are unchanged', () => {
  for (const h of ['5de9b03b618cf19646faf37c692e3857', 'a0e81d9b786d3af6fef39f2be1106dd8', '95d5c8546cb84604189b9dba0697c272']) expect(MIG).toContain(`'${h}'`)
  expect(MIG).toContain("r.extractor = 'elr-central-v1.1' and r.outcome <> 'lost'")
  expect(MIG).toContain("v_route constant text := 'elr-central-v1.0';")
  expect(MIG).toContain("jsonb_build_object('parser', v_route, 'reader', v_x,")
  expect(MIG).toContain("then 'values without a study level: the page sorts courses into English bands or levels'")
  expect(MIG).toContain("v_res->>'extractor' in ('elr-central-v1.0', 'elr-central-v1.1') then")
  expect(MIG).not.toMatch(/create or replace function security\.(policy_auto_approve_v1|provider_english_plan_v1|provider_english_apply_v1|provider_english_apply_all_v1)\(/)
  // no provider is excluded by name, type or list in the claim
  const claim = MIG.slice(MIG.indexOf('create or replace function security.elr_central_claim_v1('), MIG.indexOf('revoke all on function security.elr_central_claim_v1('))
  expect(claim).not.toMatch(/provider_type|institution|p\.name|not in \(|<> all|legal_name/i)
})

test('housekeeping and safety: no new job, table or setting; consumer API, locks and cron count checked; no drop; no spend', () => {
  expect(MIG).toMatch(/^-- Replaces: .+\.$/m)
  expect(MIG).toMatch(/^-- Retires: nothing\./m)
  expect(MIG).not.toMatch(/^(drop|delete|truncate)\b/im)
  expect(MIG).not.toMatch(/cron\.schedule\(|create table|platform_toolset_settings/i)
  expect((MIG.match(/security\.consumer_api_check_v1\(\)/g) || []).length).toBe(2)
  expect(MIG).toContain("raise exception 'post-check: the manual locks changed'")
  expect(MIG).toContain("raise exception 'post-check: the number of active cron jobs changed'")
  expect(MIG).toContain("if v_ms > 300 then raise exception 'post-check: the central claim took % ms (limit 300 ms)'")
  expect(MIG).not.toMatch(/openrouter|firecrawl_|fc_run|enrich_ai/i)
})
