// Guards: Platform Admin 19 Nov 2026 23:12 and 23:21 AEDT (chat S1-Build, s788, IQ-00053): enrich_ai has no HTTP 500 from its claim. svc_enrich_ai_next starts from the claimable rows (state in ai or leased, keyset index field_enrich_items_claim_idx) under FOR UPDATE SKIP LOCKED instead of walking every item (the cause of all 52 statement time-outs on 19 Nov 21:00-23:20 AEDT), and a claim the database refuses as busy is a structured, retryable 503, never an uncaught 500.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261119190000_cf247_s788_enrich_ai_claim_index.sql', 'utf8')
const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')

test('the claim index holds only claimable items, in the order the claim hands them out', () => {
  expect(MIG).toContain(`create index if not exists field_enrich_items_claim_idx
  on pipeline.field_enrich_items (job_id, (course_id is null), course_id, id)
  where state in ('ai', 'leased') and attempts < 3;`)
  expect(MIG).toContain("comment on index pipeline.field_enrich_items_claim_idx is")
  expect(MIG).not.toMatch(/\bconcurrently\b/i)
  expect(MIG).toContain('-- Replaces:')
  expect(MIG).toContain('-- Retires: nothing.')
})

test('both picks name the claimable states first, keep SKIP LOCKED, and the edit is md5-guarded', () => {
  expect(MIG).toContain("select pg_temp.cf_edit_def('public.svc_enrich_ai_next(integer)'::regprocedure, '91b15e0d47ea762d391f3a937b49f72c',")
  expect(MIG.match(/e\.state in \('ai', 'leased'\) and \(e\.state = 'ai' or \(e\.state = 'leased' and e\.leased_until < now\(\)\)\) and e\.attempts < 3/g)).toHaveLength(3) // two picks and the post-check
  expect(MIG).not.toMatch(/for update(?! skip locked)/i)
})

test('the post-checks prove the plan and the time without leasing anything', () => {
  expect(MIG).toContain("v_plan !~ '(field_enrich_items_claim_idx|idx_field_enrich_items_state)' or v_plan ~ 'idx_field_enrich_items_job_state'")
  expect(MIG).toContain("if v_ms > 1000 then raise exception 'post-check: svc_enrich_ai_next(40) took % ms (target under 1 s)', v_ms; end if;")
  expect(MIG).toContain("raise exception 'cf-s788-undo';") // the timed claim is rolled back in a sub-block
  expect(MIG).toContain("if sqlerrm <> 'cf-s788-undo' then raise; end if;")
})

test('enrich_ai answers a busy database with a structured 503 and keeps other errors as they were', () => {
  expect(IX).toContain('const WORKER = "coverage-sweep-worker-v1.0.41";')  // v1.0.38 from s1037  // v1.0.37 from s1029  // v1.0.36 from s1017  // v1.0.35 from s992  // v1.0.34 from s851  // the worker version only; later releases add their line before v1.0.32's
  expect(IX).toContain('// v1.0.32 (20 Nov 2026, CF-247 s815, session S1-AER')
  expect(IX).toContain('const BUSY_DB = /canceling statement due to (statement|lock) timeout|could not serialize access|deadlock detected|could not obtain lock/i;')
  expect(IX).toContain('if (BUSY_DB.test(msg)) return j({ ok: false, mode, status: "busy", retry: true, error: msg.slice(0, 200), worker: WORKER }, 503);')
  expect(IX).toContain('        throw e;\n      }\n')
  const BUSY = new RegExp(IX.match(/const BUSY_DB = \/(.*)\/i;/)[1], 'i')
  expect(BUSY.test('svc_enrich_ai_next: canceling statement due to statement timeout')).toBe(true)
  expect(BUSY.test('svc_enrich_ai_next: column "x" does not exist')).toBe(false)
})
