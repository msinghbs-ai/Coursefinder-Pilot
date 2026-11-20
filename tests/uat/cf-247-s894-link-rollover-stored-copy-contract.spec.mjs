// Guards: Platform Admin 21 Nov 2026 07:35 AEDT (S1-CourseLink-2027-CRICOS s894): rule course_link_year_rollover_v1 keeps the old-year fallback; worker calls carry
// 8 items (setting link_rollover.items_per_call, so one call stays inside the 120-second limit); when no live read proves the course, the stored copy already bound to
// the held address ($0, the evidence store) admits the held address only by the platform's identity rule and without "not found / no longer offered" words.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { storedCopyAnswer } from '../../supabase/functions/coverage-sweep/link-rollover.ts'

const MIG = fs.readFileSync('supabase/migrations/20261121080000_cf247_s894_link_rollover_stored_copy_tuning.sql', 'utf8')
const code = MIG.split('\n').filter(l => !l.trimStart().startsWith('--')).join('\n')
const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const MODE = IX.slice(IX.indexOf('if (mode === "link_year_rollover") {'), IX.indexOf('if (mode === "read") {'))

test('s894 migration: 8 items a call, claim v2 with the stored copy, md5-guarded edits, G3 and locks, nothing dropped', () => {
  expect(code).toContain("set value = '8'::jsonb")
  expect(code).toContain("if security.pipeline_num_v1('link_rollover.items_per_call', 15) <> 8 then raise exception")
  expect(code).toContain("p.read_status = 'read' and lower(p.url) = lower(u.url) and nullif(ea.storage_path, '') is not null")
  expect(code).toContain("'268b27dbf8a73ffffd15ba9aa2cbf0e6'"); expect(code).toContain("'09ed30fe1960f5ecc5d3c4afb550e502'")
  expect(code).toContain("from security.link_rollover_claim_v2(v_batch) c;")
  expect(code).toContain("set status = 'retiring', replaced_by = 'security.link_rollover_claim_v2', retire_after = date '2026-12-05'")
  expect(code).toContain("where outcome = 'not_proved';")
  expect((MIG.match(/consumer_api_check_v1/g) || []).length).toBeGreaterThanOrEqual(2)
  expect((MIG.match(/pipeline\.manual_locks\) <> 7585/g) || []).length).toBe(2)
  expect(MIG).toMatch(/^-- Replaces:/m); expect(MIG).toMatch(/^-- Retires:/m)
  expect(code).not.toMatch(/create\s+(or replace\s+)?function\s+public\.|create\s+(table|view)\b|\b(drop|delete|truncate)\b|cron\.schedule\(/i)
})

test('s894 worker: the stored copy is read from the evidence store only when no live read proved the course, and proves only by identity', () => {
  expect(MODE).toContain('if (!chosen && heldCand && it.stored_path) {')
  expect(MODE).toContain('await readEvidenceCopy(c, it.stored_path)')
  expect(MODE).toContain('if (ans.ok && strongIdentity(basis, it.country || "")) {')
  expect(MODE).toContain('storage_path: null, sha256: it.stored_sha ?? null, source: "stored_copy"')
  expect(MODE).not.toMatch(/fcx\.|useFc\(|firecrawl|cascadeFetch|openrouter|rpc\(/i)
  expect(storedCopyAnswer({ text: 'Doctor of Philosophy CRICOS 0100697 ' + 'x'.repeat(300), year: 2023, markers: ['no longer offered'] }).ok).toBe(true)
  expect(storedCopyAnswer({ text: 'This course is no longer offered. ' + 'x'.repeat(300), year: 2023, markers: ['no longer offered'] }).reason).toBe('says: no longer offered')
  expect(storedCopyAnswer({ text: 'short', year: 2023, markers: [] }).reason).toBe('empty')
})
