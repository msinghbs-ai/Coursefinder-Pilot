// Guards: S831 Layer 4 AER hold reasons and rule checks (Platform Admin 20 Nov 2026 11:55 AEDT, item 4; Decision 276 kept: read only, no gate changed, no bulk approval; G3: no new public function, table or view).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261120130000_cf247_s831_l4_aer_hold_reasons.sql', 'utf8')
const HOLD = fs.readFileSync('src/Layer4HoldReasons.jsx', 'utf8')
const CHECKS = fs.readFileSync('src/AerRuleChecks.jsx', 'utf8')
const INBOX = fs.readFileSync('src/Layer4Inbox.jsx', 'utf8')
const GRID = fs.readFileSync('src/Layer4Grid.jsx', 'utf8')

test('migration: read only, two security functions, one edited public wrapper, guarded by the live definition, nothing dropped, housekeeping lines present', () => {
  expect(MIG).toMatch(/^-- Replaces: public\.admin_layer4_aer_queue\(jsonb\)/m)
  expect(MIG).toMatch(/^-- Retires: nothing$/m)
  expect(MIG).toContain('800198d6264c08f088f672adbdaa26a5')
  expect(MIG).not.toMatch(/\b(insert|update|delete)\s+(into|from)?\s*(pipeline|catalogue|search)\./i)
  expect(MIG).not.toMatch(/\bdrop\s+(table|function|view|schema)\b/i)
  expect([...MIG.matchAll(/create or replace function (public\.[a-z0-9_]+)/g)].map((m) => m[1])).toEqual(['public.admin_layer4_aer_queue'])
  expect(MIG).toMatch(/revoke all on function security\.layer4_aer_hold_reasons_v1\(jsonb\) from public, anon, authenticated/)
  expect(MIG).toContain('{hold_reasons: true}')
  expect(MIG).toContain("least(100, greatest(1, coalesce(nullif(p_args->>'limit', '')::int, 25))); -- fixed:")
  expect(MIG).toMatch(/consumer_api_functions_v1\(\)\) <> 75 or \(select count\(\*\) from security\.consumer_api_relations_v1\(\)\) <> 48/)
})

test('the wrapper keeps the role check and every earlier branch', () => {
  const w = MIG.slice(MIG.indexOf('create or replace function public.admin_layer4_aer_queue'))
  expect(w).toContain("coalesce(security.current_role_rank(), 0) < 4")
  expect(w.indexOf('hold_reasons')).toBeLessThan(w.indexOf('summary_provider_id'))
  expect(w).toContain('security.layer4_aer_university_summary_v1')
  expect(w).toContain('security.layer4_aer_queue_v1(coalesce(p_args')
})

test('screen: the breakdown names the counts, filters to the audit sample, opens the existing Source quote drawer, and (s1090) lists the two reasons a person decides open, with a bulk bar through the Inbox decide action', () => {
  expect(HOLD).toContain('Why items are held (')
  expect(HOLD).toContain('Show the audit sample')
  expect(HOLD).toContain("hold_reasons:true")
  expect(HOLD).toContain("from'./Layer4Grid'")
  expect(HOLD).not.toMatch(/Approve the verified batch/i) // s1090: Approve Selected is the Platform Admin's request; each item is decided on its own through the Inbox's decide action
  expect(HOLD).toContain("p_action:'decide'")
  expect(HOLD).toContain('data-l4-hold-bulk')
  expect(INBOX).toContain("kind==='aer_review'&&(view==='university'||view==='kind'||focus)&&<Layer4HoldReasons")
  expect(GRID).toContain('export function Drawer')
  expect(GRID).toContain("target.kind==='aer_review'&&<section data-l4g-rule-checks>")
})

test('rule checks: four checks, worded as states (never colour only), and the overwrite check is left to the server', () => {
  for (const k of ["key:'quote'", "key:'identity'", "key:'completeness'", "key:'overwrite'"]) expect(CHECKS).toContain(k)
  for (const w of ['Passes', 'Does not pass', 'Checked on approval']) expect(CHECKS).toContain(w)
  expect(CHECKS).toContain('layer4_aer_review_read')
  expect(CHECKS).not.toMatch(/\.rpc\('(?!layer4_aer_review_read)/)
})
