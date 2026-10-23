// CF-247 read lane capacity (Platform Admin 23 Oct 2026 22:57 "How do increase the capacity ... configured by UI?", 23:13 "Go").
// Contracts: the worker and the picker take up to the setting's maximum (200) instead of a 60 fixed in code; pages fetched at once
// is a setting (reading.pages_at_once, 1 to 32) the worker reads through svc_worker_settings_v1.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const read = f => fs.readFileSync(f, 'utf8')

test('migration: reading.pages_at_once setting with a range; worker settings include reading.*; picker cap 200 (md5-guarded edits)', () => {
  const m = read('supabase/migrations/20261023027000_cf247_read_lane_settings.sql')
  expect(m).toMatch(/^-- Replaces: /m); expect(m).toMatch(/^-- Retires: /m); expect(m).not.toMatch(/^\s*(drop|truncate|delete\s+from)\b/im)
  expect(m).toContain("values ('pipeline', 'reading.pages_at_once', 'Read course pages: pages fetched at once',")
  expect(m).toContain("'number', '8'::jsonb, '1', '32', 'pages', 103, 'Job sizes', 'job coverage-read, coverage-read-2; worker coverage-sweep read',")
  expect(m).toContain("select pg_temp.edit_once('public.svc_worker_settings_v1()', '2b5b30d2c25bf540f76419a33c48be34', array[")
  expect(m).toContain("$n$or (s.toolset_key = 'pipeline' and (s.key like 'enrich.%' or s.key like 'reading.%'))$n$")
  expect(m).toContain("select pg_temp.edit_once('public.svc_coverage_read_next(integer)', '8c70024ba4b6db0c02362d28c6e947d0', array[")
  expect(m).toContain("$n$limit greatest(1,least(coalesce(p_limit,20),200))$n$")
})

test('worker v0.44.0: read mode takes up to 200 pages a call and fetches reading.pages_at_once at the same time (no 60 or 8 fixed)', () => {
  const w = read('supabase/functions/coverage-sweep/index.ts')
  expect(w).toContain('const WORKER = "coverage-sweep-worker-v0.44.0";')
  expect(w).toContain('await rpc("svc_coverage_read_next", { p_limit: Math.min(Number(body.limit || 24), 200) });')
  expect(w).not.toContain('await rpc("svc_coverage_read_next", { p_limit: Math.min(Number(body.limit || 24), 60) });')
  expect(w).toContain('await pool(items, Math.min(Math.max(1, wsNum("reading.pages_at_once", 8)), 32), async (it) => {')
})
