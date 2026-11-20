// Guards: S861 automated deterministic course structure promotion and scheduled sweep (Platform Admin 20 Nov 2026 15:19 AEDT, S1-Structure-Outcomes, $0; no overwrite, manual locks kept, page identity, shared pages and disagreements to Layer 4; G1 job catalogued; G2 no number in a job command; G3 no public object; housekeeping s42)
// CF-247 S861. Migration 20261120161000_cf247_s861_struct_det_promotion_and_sweep.sql, reader struct-det-v1.0, worker mode struct_det_read.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261120161000_cf247_s861_struct_det_promotion_and_sweep.sql', 'utf8')
const NOCOMMENT = MIG.replace(/^--.*$/gm, '')
const PROMOTE = NOCOMMENT.slice(NOCOMMENT.indexOf('function security.struct_det_promote_v1'), NOCOMMENT.indexOf('function security.struct_det_sweep_v1'))

test('housekeeping: Replaces and Retires lines, a comment on each new table, no drop and no delete in the migration', () => {
  expect(MIG).toMatch(/^-- Replaces:/m)
  expect(MIG).toMatch(/^-- Retires:/m)
  for (const t of ['struct_det_pages', 'struct_det_readings', 'struct_det_outcomes', 'struct_det_sweep_calls']) expect(MIG).toContain('comment on table pipeline.' + t)
  expect(NOCOMMENT).not.toMatch(/\bdrop\s+(table|function|schema|column)\b|\bdelete\s+from\b|\btruncate\b/i)
})

test('G3: every new object is in schema pipeline or security, none is public or api, nothing is granted, and the consumer API is checked before and after', () => {
  expect(NOCOMMENT).not.toMatch(/(?:create\s+(?:or\s+replace\s+)?(?:function|view|table)(?:\s+if\s+not\s+exists)?)\s+(?:public|api|search|catalogue)\./i)
  const made = [...NOCOMMENT.matchAll(/create\s+(?:or\s+replace\s+)?(?:function|table|view)(?:\s+if\s+not\s+exists)?\s+([a-z_]+)\./gi)].map((m) => m[1])
  expect(made.length).toBe(7)
  for (const s of made) expect(['pipeline', 'security']).toContain(s)
  expect(NOCOMMENT).not.toMatch(/\bgrant\b/i)
  expect(NOCOMMENT.match(/security\.consumer_api_check_v1\(\)/g)?.length).toBe(2)
  expect(NOCOMMENT).not.toMatch(/alter\s+table\s+(catalogue|search|public|api)\./i)
})

test('no overwrite and manual locks: every write is guarded by an empty target and the lock fields of its column', () => {
  const ups = [...PROMOTE.matchAll(/update\s+catalogue\.courses\s+set\s+([\s\S]*?);/gi)].map((m) => m[1])
  expect(ups.length).toBe(3)
  expect(ups[0]).toMatch(/where id = c\.id and duration_value is null and duration_unit is null$/)
  expect(ups[1]).toMatch(/study_load_source = 'provider_page', study_load_evidence_id = pg\.evidence_id[\s\S]*where id = c\.id and study_load is null$/)
  expect(ups[2]).toMatch(/where id = c\.id and nullif\(btrim\(delivery_mode\), ''\) is null$/)
  for (const f of ["'duration', 'duration_value', 'duration_unit', 'all'", "'study_load', 'study_load_source', 'study_load_evidence_id', 'all'", "'delivery_mode', 'delivery', 'all'"]) expect(PROMOTE).toContain(f)
  expect(PROMOTE).toContain("v_out := 'has_value'")
  expect(PROMOTE).not.toMatch(/manual_locks[^;]*\b(insert|update|delete)\b/i)
  expect(PROMOTE).not.toMatch(/cf\.manual_edit/)
})

test('page identity, shared pages and agreement: only the bound page, an identity that admits course facts, one agreed value, no collapsed line', () => {
  expect(PROMOTE).toContain("p.status = 'bound'")
  expect(PROMOTE).toContain("v_page_out := 'page_changed'")
  expect(PROMOTE).toContain("security.coverage_identity_allowed(c.provider_id, g.identity_basis, 'description')")
  expect(PROMOTE).toContain('and not r.collapsed')
  expect(PROMOTE).toContain('v_n > 1 or v_shared')
  expect(PROMOTE).toContain('insert into pipeline.layer4_review_items')
  expect(PROMOTE).toMatch(/'The course page states more than one '/)
  expect(PROMOTE).toMatch(/'This page is shared with other courses/)
  expect(PROMOTE).toContain("insert into search.course_refresh_requests (course_id, requested_at, requested_by) values (c.id, now(), 's861_struct_det')")
  expect(NOCOMMENT).not.toMatch(/openrouter|firecrawl_|ai_instruction/i)
})

test('G1 and G2: the job is catalogued and registered, its command holds no number, and every value is a setting with a label, range and unit', () => {
  expect(MIG).toContain('insert into pipeline.automation_catalogue')
  expect(MIG).toContain("'struct-det-sweep'")
  expect(MIG).toContain('pipeline.component_register')
  const cmd = MIG.match(/cron\.schedule\('struct-det-sweep', '[^']+', '([^']+)'\)/)
  expect(cmd?.[1]).toBe('select security.struct_det_sweep_v1()')
  const keys = ['struct_det.sweep_on', 'struct_det.sweep_calls', 'struct_det.sweep_max_open', 'struct_det.pages_per_call', 'struct_det.call_lost_minutes', 'struct_det.promote_on', 'struct_det.promote_per_run', 'struct_det.admit_stated', 'struct_det.layer4_max_pending']
  for (const k of keys) {
    const row = MIG.split('\n').find((l) => l.startsWith(" ('pipeline', '" + k + "'"))
    expect(row, k).toBeTruthy()
    expect(row).toMatch(/'number', to_jsonb\([0-9.]+\), [0-9.]+, [0-9.]+, '[a-z ]+', 6[0-9]{2}, 'Admission checks', 'security\.struct_det_/)
    expect(NOCOMMENT).toContain("security.pipeline_num_v1('" + k + "'")
  }
})

test('post-checks: a rolled-back synthetic promotion admits the agreed duration, sends disagreeing modes to Layer 4, and leaves nothing behind', () => {
  const pc = NOCOMMENT.slice(NOCOMMENT.indexOf('-- 6. post-checks') > 0 ? NOCOMMENT.indexOf('do $c$') : 0)
  expect(pc).toContain("raise exception 'rollback of the synthetic read' using errcode = 'P0099'")
  expect(pc).toContain('post-check: the agreed duration was not admitted')
  expect(pc).toContain('post-check: a disagreeing delivery mode was admitted')
  expect(pc).toContain('post-check: the synthetic read was not rolled back')
  expect(pc).toContain("raise notice 's861 send query: % ms'")
})
