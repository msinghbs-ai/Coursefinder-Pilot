// Guards: S835 automated deterministic academic AER promotion and scheduled sweep (Platform Admin 20 Nov 2026 15:08 AEDT; Decision 276: the AI and Boost aer_entry readers stay shadow only; G1 job catalogued; G2 no number in a job command; G3 no public object; housekeeping s42; AER and English are separate)
// CF-247 S835. Migration 20261120163000_cf247_s835_aer_det_academic_promotion_and_sweep.sql, reader aer-det-v1.3, worker mode aer_det_read.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261120163000_cf247_s835_aer_det_academic_promotion_and_sweep.sql', 'utf8')
const READER = fs.readFileSync('supabase/functions/coverage-sweep/aer-det-reader.ts', 'utf8')
const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const RUN = fs.readFileSync('scripts/aer-det-read.mjs', 'utf8')
const NOCOMMENT = MIG.replace(/^--.*$/gm, '')

test('housekeeping: Replaces and Retires lines, a comment on each new table, no drop and no delete in the migration', () => {
  expect(MIG).toMatch(/^-- Replaces:/m)
  expect(MIG).toMatch(/^-- Retires:/m)
  for (const t of ['aer_det_academic_pages', 'aer_det_academic_readings', 'aer_det_sweep_calls']) expect(MIG).toContain('comment on table pipeline.' + t)
  expect(NOCOMMENT).not.toMatch(/\bdrop\s+(table|function|schema|column)\b|\bdelete\s+from\b|\btruncate\b/i)
})

test('G3: every new object is in schema pipeline or security, and none is public, an API function or a website view', () => {
  expect(NOCOMMENT).not.toMatch(/(?:create\s+(?:or\s+replace\s+)?(?:function|view|table)(?:\s+if\s+not\s+exists)?)\s+(?:public|api)\./i)
  const made = [...NOCOMMENT.matchAll(/create\s+(?:or\s+replace\s+)?(?:function|table|view)(?:\s+if\s+not\s+exists)?\s+([a-z_]+)\./gi)].map((m) => m[1])
  expect(made.length).toBeGreaterThan(5)
  for (const s of made) expect(['pipeline', 'security']).toContain(s)
  expect(NOCOMMENT).not.toMatch(/\bgrant\b/i)
})

test('academic only: no English test key in the tables, the proposer or the runner; nine academic keys only', () => {
  const keys = ['atar', 'year12', 'ncea_l3', 'university_entrance', 'ib', 'alevel', 'india_board', 'ca_secondary', 'bachelor_gpa']
  for (const k of keys) expect(MIG).toContain("'" + k + "'")
  for (const e of ['ielts', 'toefl_ibt', 'pte', 'oet', 'celpip', 'cambridge']) { expect(NOCOMMENT).not.toMatch(new RegExp("'" + e + "'")); expect(READER).not.toMatch(new RegExp('key: "' + e + '"')) }
  expect(NOCOMMENT).not.toMatch(/'english_test'/)
  expect(RUN).not.toContain('aer_det_readings ')
})

test('Decision 276 and the gates: the proposer writes proposed rows and a Layer 4 item only; it never activates, admits, overwrites or touches a lock', () => {
  const prop = NOCOMMENT.slice(NOCOMMENT.indexOf('function security.aer_det_propose_v1'), NOCOMMENT.indexOf('function security.aer_det_sweep_v1'))
  expect(prop).toContain("'proposed'")
  expect(prop).toContain("status = 'bound'")
  expect(prop).toContain('manual_locks')
  expect(prop).toContain('coverage_identity_allowed')
  expect(prop).toContain('course_entry_max_rows_v1')
  expect(prop).not.toMatch(/(?<!lifecycle_)status\s*=\s*'active'\s*(?:,|where)/)
  expect([...prop.matchAll(/update\s+catalogue\.[a-z_]+\s+set\s+(\w+)/gi)].map((m) => m[1])).toEqual(['provenance'])  // only the review_item_id of its own proposed rows
  expect(prop).not.toMatch(/search\.course_documents|aer_machine_admit|course_entry_review_apply/i)
  expect(prop).toContain("'det_other_requirement'")
  expect(NOCOMMENT).not.toMatch(/openrouter|firecrawl_|ai_instruction/i)
})

test('G1 and G2: the job is catalogued and registered, its command holds no number, and every value is a setting with a label, range and unit', () => {
  expect(MIG).toContain("insert into pipeline.automation_catalogue")
  expect(MIG).toContain("'aer-det-sweep'")
  expect(MIG).toContain("pipeline.component_register")
  const cmd = MIG.match(/cron\.schedule\('aer-det-sweep', '[^']+', '([^']+)'\)/)
  expect(cmd?.[1]).toBe('select security.aer_det_sweep_v1()')
  for (const k of ['aer_det.sweep_on', 'aer_det.sweep_calls', 'aer_det.sweep_max_open', 'aer_det.call_lost_minutes', 'aer_det.propose_on', 'aer_det.propose_max_pending', 'aer_det.propose_per_run', 'aer_det.confidence_stated', 'aer_det.confidence_mentioned']) {
    const row = MIG.split('\n').find((l) => l.startsWith(" ('pipeline', '" + k + "'"))
    expect(row, k).toBeTruthy()
    expect(row).toMatch(/'number', to_jsonb\([0-9.]+\), [0-9.]+, [0-9.]+, '[a-z ]+', 6[0-9]{2}, 'Admission checks'/)
  }
  expect(MIG).toMatch(/batch\.aer_det_read[^;]*value = to_jsonb\(20\)/s)
  expect(MIG).toContain("security.pipeline_num_v1('batch.aer_det_read', 40)")
  for (const l of MIG.split('\n').filter((l) => /^\s*v_ext constant text/.test(l))) expect(l).toContain('-- fixed:')
})

test('the sweep sends only the academic reader version, refuses a worker on another version, and collects answers through pg_net', () => {
  const sw = NOCOMMENT.slice(NOCOMMENT.indexOf('function security.aer_det_sweep_v1'))
  expect(sw).toContain("pipeline.svc_pilot_submit_nonce('coverage-sweep'")
  expect(sw).toContain("'aer_det_read'")
  expect(sw).toContain('net._http_response')
  expect(sw).toContain("'wrong_extractor'")
  expect(sw).toContain('security.maintenance_hold_v1()')
  expect(sw).toContain('security.aer_det_propose_v1()')
  const ver = READER.match(/AER_DET_VERSION = "([^"]+)"/)[1]
  for (const m of MIG.matchAll(/v_ext constant text := '([^']+)'/g)) expect(m[1]).toBe(ver)
  expect(RUN).toContain("const V = '" + ver + "'")
})

test('the worker returns the other requirement lines beside the readings and writes nothing', () => {
  expect(IX).toContain('uncovered: detUncovered(text, rd)')
  const mode = IX.slice(IX.indexOf('if (mode === "aer_det_read")'), IX.indexOf('if (mode === "entry_inspect")'))
  expect(mode).not.toMatch(/\.insert\(|\.update\(|\.upsert\(|\.rpc\(|rpc\(/)
})

test('the migration post-check proves the proposal is rolled back and the consumer API stays at 75 functions and 48 relations', () => {
  expect(MIG).toContain("errcode = 'P0099'")
  expect(MIG).toContain("(v_api->>'functions')::int <> 75")
  expect(MIG).toContain("(v_api->>'relations')::int <> 48")
})
