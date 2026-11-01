// Guards: Layer 4 settlement recovery (Platform Admin mandate 1 Nov 2026 11:28; incident 2026-11-01-layer4-all-kinds-settlement-timeout-stop.md; admin record §35): the Evidence search by page address uses an indexed prefix match instead of a contains-search of every stored copy, the fee schedules list works out each document's proposal rows once, and fee rows are matched to courses through an index, so the central-page approvals and evidence lookups used in Layer 4 review load within the 8 s limit.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261101040000_cf247_l4_timeout_recovery.sql', 'utf8')
const code = (s) => s.replace(/--[^\n]*/g, '')

test('md5-guarded edits; indexes; nothing dropped; consumer API untouched', () => {
  expect(m).toContain("select pg_temp.edit_once('security.admin_evidence_page(jsonb)', 'fc04124f37acf248e0afdfe63bd043e8', '7ab917871c6161dc3449d6625ebb2350', array[")
  expect(m).toContain("select pg_temp.edit_once('public.admin_provider_fee_schedules_read(uuid,integer)', '8f21ca127c6773f4abeb2690c96b90f2', '9ca85971fea06c9dae930c44bd88475d', array[")
  expect(m).toContain('create index if not exists evidence_artifacts_source_url_pattern_idx on pipeline.evidence_artifacts (lower(source_url) text_pattern_ops);')
  expect(m).toContain("create index if not exists courses_provider_code_trim_active_idx on catalogue.courses (provider_id, upper(btrim(course_code))) where lifecycle_status = 'active';")
  expect(m).toMatch(/^-- Replaces: security\.admin_evidence_page, public\.admin_provider_fee_schedules_read/m)
  expect(m).toMatch(/^-- Retires: nothing/m)
  expect(code(m)).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(code(m)).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|function\s+api\./)
})

test('an address search is a prefix match through the index; other searches keep the full text search', () => {
  expect(m).toContain("if v_query ~* '^https?://[^[:space:]]+$' then")
  expect(m).toContain("where lower(e.source_url) ~>=~ v_url and lower(e.source_url) ~<~ (v_url || chr(1114111))")
  expect(m).toContain("(v_query is null or e.id = any(v_url_ids) or (v_url_ids is null and (e.id::text ilike '%'||v_query||'%' or")
})

test('fee schedules: one pass of proposal rows per document', () => {
  expect(m).toContain("cross join lateral (select count(*) n, count(*) filter (where x.outcome = 'new') n_new")
  expect(m).toContain("'rows', k.n, 'new', k.n_new, 'same', k.n_same, 'differs', k.n_differs, 'no_course', k.n_no_course) d")
})
