// Guards: CF-247 AER programme Platform Admin decision 29 Oct 2026 09:57 item 1 (parked reader settings and HTML refetch approved; admin docs/platform/AER-OPERATIONS-WORKSPACE-DECISION-2026-10-29.md W12): slices read at once and slice size are settings with a label, range, unit and used_by; the worker is told through svc_entry_matrix_next (md5-guarded); Read again is one mechanism (security.aer_reread_v1, owner only) behind the Platform Admin check, which fetches a markdown-stored web page again as HTML after superseding its proposed rows and pending item, and keeps every earlier refusal; nothing dropped, no job, status or consumer API change
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261029020000_cf247_aer_reader_settings_html_refetch.sql', 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('settings: slices read at once (6, range 1-12) and slice size 8,000, each labelled with unit, range and used_by; the worker is told (md5-guarded)', () => {
  expect(code).toContain("('pipeline', 'entry.matrix_slice_concurrency', 'Entry matrices: slices read at once',")
  expect(code).toContain("to_jsonb(6), 1, 12, 'slices', 905, 'Entry requirements', 'public.svc_entry_matrix_next, worker entry_ai',")
  expect(code).toContain("update pipeline.platform_toolset_settings set value = to_jsonb(8000), updated_at = now(),")
  expect(code).toContain("where toolset_key = 'pipeline' and key = 'entry.matrix_slice_chars';")
  expect(code).toContain("select pg_temp.edit_n('public.svc_entry_matrix_next(integer)', 'dc1bab7a54fb4d4c0651e6be2fefe289'")
  expect(code).toContain("'slice_concurrency', security.pipeline_num_v1('entry.matrix_slice_concurrency', 1)::int,$n$]], array[1]);")
  // worker v0.51.0 already reads it within its fixed safety bound
  const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(w).toContain('Math.max(1, Math.min(Number(it.slice_concurrency) || 1, 12))')
})

test('Read again: one mechanism behind the Platform Admin check; every earlier refusal kept; nothing waiting is asked twice', () => {
  expect(code).toContain("select pg_temp.edit_n('public.admin_aer(text,jsonb)', 'd582b0c2c4ecf70cac9a3615a6899f7a'")
  expect(code).toContain("return security.aer_reread_v1((a->>'source_id')::uuid, v_reason, auth.uid());")
  expect(code).toContain('revoke all on function security.aer_reread_v1(uuid, text, uuid) from public, anon, authenticated;')
  for (const r of ["this provider is outside the reading scope (entry.providers)", "AI reading is stopped (AI limits); nothing was asked",
    "a read of this source is already waiting or running", "this page is waiting to be fetched again; its read follows",
    "if v_run.state = 'failed' and v_run.error like 'held_unparsed%' then", "give a reason (kept in the history)"]) expect(code).toContain(r)
  expect(code).toContain("return public.admin_entry_matrix_reread(array[v_src.id], v_reason);")
})

test('a markdown-stored web page is fetched again as HTML: rows and pending item superseded first, robots respected, logged; markdown copy kept', () => {
  expect(code).toContain("if v_mime = 'text/markdown' and v_src.url !~* '\\.pdf($|[?#])' then")
  expect(code).toContain("if v_src.status = 'robots_disallowed' then raise exception")
  expect(code).toContain("update catalogue.provider_entry_matrix m set status = 'superseded', status_reason = 'read again as HTML: ' || v_reason, updated_at = now()")
  expect(code).toContain("update pipeline.layer4_review_items li set status = 'superseded'")
  expect(code).toContain("where li.status = 'pending' and li.id in")
  expect(code).toContain("update pipeline.entry_matrix_sources set status = 'found', attempts = 0, error = null, read_at = null, updated_at = now() where id = v_src.id;")
  expect(code).toContain("values ('entry_matrix', 'refetch_html', 'pipeline.entry_matrix_sources',")
  // an approved row is never touched; nothing dropped or deleted; no job, status or consumer API change
  expect(code).not.toMatch(/status = 'active'|li\.status in \('pending', 'approved'\)/)
  expect(code).not.toMatch(/\b(drop|delete from|truncate)\b/i)
  expect(code).not.toMatch(/cron\.schedule|insert into pipeline\.(automation_catalogue|admin_job_kinds)/)
  expect(code).not.toMatch(/create or replace function (public\.website_|public\.zoho_|api\.|security\.entry_resolve_v1)/)
  expect(m).toMatch(/^-- Replaces: public\.svc_entry_matrix_next and public\.admin_aer/m)
  expect(m).toMatch(/^-- Retires: nothing/m)
})
