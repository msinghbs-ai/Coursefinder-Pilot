// Guards: CF-247 AER programme (Platform Admin consolidated mandate 28 Oct 2026 23:22; admin docs/platform/ENTRY-REQUIREMENTS-PROGRAMME-DECISION-2026-10-28.md P2 sources, P10 automation): the entry-matrix reader's answer length and slice size are settings, a cut-off answer is named, and a Firecrawl budget refusal neither blocks a seeded never-read entry source by the central refresh interval nor uses up the page's tries; every other gate unchanged
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261029001000_cf247_aer_reader_limits.sql', 'utf8')
const code = m.split('\n').filter(l => !/^\s*--/.test(l)).join('\n')
const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const e = fs.readFileSync('supabase/functions/coverage-sweep/entry.ts', 'utf8')
const ai = w.slice(w.indexOf('if (mode === "entry_ai") {'), w.indexOf('if (mode === "fee_ai") {'))

test('answer length and slice size are settings with a range, a unit and the functions that use them', () => {
  for (const k of ['entry.matrix_max_tokens', 'entry.matrix_slice_chars']) expect(code).toContain(`('pipeline', '${k}', `)
  expect(code).toContain("to_jsonb(16000), 4000, 32000, 'tokens', 904, 'Entry requirements', 'public.svc_entry_matrix_next, worker entry_ai'")
  expect(code).toContain("to_jsonb(12000), 4000, 24000, 'characters', 904, 'Entry requirements', 'public.svc_entry_matrix_next, worker entry_ai'")
  expect(code).toContain("'max_tokens', security.pipeline_num_v1('entry.matrix_max_tokens', 8000)::int,")
  expect(code).toContain("'slice_chars', security.pipeline_num_v1('entry.matrix_slice_chars', 24000)::int,")
})

test('worker v0.49.2 uses them and names a cut-off answer', () => {
  expect(w).toMatch(/const WORKER = "coverage-sweep-worker-v0\.(49\.([2-9]|\d{2,})|5\d\.\d+)"/)
  expect(e).toMatch(/export function entryMatrixRequest\(model: string, p: \{ provider: string; url: string; text: string; slice\?: string; cells\?: string(; note\?: string)? \}, maxTokens = 8000\)/)
  expect(e).toContain('return { model, temperature: 0, max_tokens: maxTokens,')
  expect(ai).toContain('entrySlices(page, Number(it.max_rows) || 400, Number(it.slice_chars) || 24000)')
  expect(ai).toContain('Number(it.max_tokens) || 8000)), signal: AbortSignal.timeout(90000) });')
  expect(ai).toContain('if (d?.choices?.[0]?.finish_reason === "length") throw Error(`output_truncated:')
  // the quote, scale and completeness checks are unchanged
  expect(ai).toContain('const parsed = entryMatrixParsed(JSON.parse(content), page, stored.lines);')
  expect(ai).toContain('if (it.completeness_required === true && completeness.status !== "complete") {')
})

test('a seeded entry source never read passes the central refresh interval only; a budget refusal does not use a try', () => {
  expect(code).toContain("select pg_temp.edit_n('public.svc_fc_spend(numeric,text,uuid,text)', '98aaa595c7eae2199ceac2decbfee474'")
  expect(code).toContain("and not exists (select 1 from pipeline.entry_matrix_sources es where es.provider_id = p_provider_id and es.url = p_url\n                             and es.status in ('found', 'reading') and es.read_at is null) then")
  expect(code).toContain("attempts = case when p_error in ('credits_refused', 'credits_reserve', 'no_firecrawl_key') then greatest(attempts - 1, 0) else attempts end,")
  expect(code).toContain("when p_error in ('credits_refused', 'credits_reserve', 'no_firecrawl_key') then 'found'")
  // the tries given back are bounded and only for never-read seeded sources refused for budget
  expect(code).toContain("where found_via = 'manual' and status = 'found' and error in ('credits_refused', 'credits_reserve') and read_at is null;")
  expect(code).toContain("if v_n > 20 then raise exception")
  expect(code).not.toMatch(/\b(drop|delete from|truncate)\b/i)
  expect(code).not.toMatch(/insert into pipeline\.(automation_catalogue|admin_job_kinds)|cron\.schedule/)
  expect(m).toMatch(/^-- Replaces: /m)
  expect(m).toMatch(/^-- Retires: nothing$/m)
})
