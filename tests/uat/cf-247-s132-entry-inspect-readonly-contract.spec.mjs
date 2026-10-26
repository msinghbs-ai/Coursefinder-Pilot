// Guards: CF-247 AER v1.1 tooling (Platform Admin 27 Oct 2026 05:46: D5/D4 tests "must use the stored source pages"): mode entry_inspect only reads stored entry-matrix copies (no AI, no web fetch, no write) and is service-role only
// Record: admin docs/platform/aer-v1.1-build-log.md (27 Oct 05:50 decision).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const m = fs.readFileSync('supabase/migrations/20261027002000_cf247_entry_matrix_inspect_paths.sql', 'utf8')
const block = w.slice(w.indexOf('if (mode === "entry_inspect") {'), w.indexOf('if (mode === "entry_ai") {'))

test('entry_inspect reads stored copies only: no AI call, no web fetch, no database write', () => {
  expect(block.length).toBeGreaterThan(200)
  expect(block).toContain('await rpc("svc_entry_matrix_inspect_paths", { p_source_ids: ids })')
  expect(block).toContain('c.storage.from("evidence").download(r.storage_path)')
  expect(block).not.toMatch(/openrouter|firecrawl|readDirect|fetch\(|\.upload\(|svc_entry_matrix_record|svc_entry_matrix_fetch_record/i)
  expect(block).toContain('.slice(0, 12);  // fixed: diagnostic batch cap')
  expect(block).toContain('return j({ ok: true, mode, pages: out,')
})

test('the path function is read-only and service-role only', () => {
  expect(m).toContain('create or replace function public.svc_entry_matrix_inspect_paths(p_source_ids uuid[]) returns jsonb\nlanguage plpgsql stable security definer')
  expect(m).toContain("if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;")
  expect(m).toContain('revoke all on function public.svc_entry_matrix_inspect_paths(uuid[]) from public, anon, authenticated;')
  expect(m).not.toMatch(/\b(insert|update|delete|drop|truncate)\b/i)
})
