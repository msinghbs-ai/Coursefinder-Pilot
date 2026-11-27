// Guards: SS-Programme-Control 27 Nov 2026 21:08 AEDT, approved scoped exception 1 (DOT structured-data intake through the existing writers, evidence verification and admission rules); CLAUDE.md "A passing qualification never switches anything on by itself", Layer 4 human decisions, no drop or delete by an applied migration
// CF-247 s1321. supabase/migrations/20261130200000_cf247_s1321_structured_intake.sql, supabase/functions/coverage-sweep/intake.ts (mode intake_verify), scripts/structured-intake.mjs, .github/workflows/structured-intake.yml
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { transformSync } from 'esbuild'

const sql = fs.readFileSync('supabase/migrations/20261130200000_cf247_s1321_structured_intake.sql', 'utf8')
const ix = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const wf = fs.readFileSync('.github/workflows/structured-intake.yml', 'utf8')
const ops = fs.readFileSync('scripts/structured-intake.mjs', 'utf8')
const SRC = fs.readFileSync('supabase/functions/coverage-sweep/intake.ts', 'utf8')
const { foldText, quoteOnPage, INTAKE_VERIFY } = await import('data:text/javascript;base64,' + Buffer.from(transformSync(SRC, { loader: 'ts', format: 'esm' }).code).toString('base64'))

test('a quote counts only when it is printed on the stored copy: white space and typographic forms folded, nothing else', () => {
  expect(INTAKE_VERIFY).toBe('intake-quote-v1')
  const page = foldText('Entry requirements\n a minimum of 24 points\n in the International Baccalaureate (IB) Diploma. CRICOS Code:059850D')
  expect(quoteOnPage(page, 'a minimum of 24 points in the International Baccalaureate (IB) Diploma').found).toBe(true)
  expect(quoteOnPage(page, 'CRICOS Code: 059850D').found).toBe(true)
  expect(quoteOnPage(page, 'a minimum of 25 points in the International Baccalaureate (IB) Diploma')).toEqual({ found: false, reason: 'quote_not_on_stored_copy' })
  expect(quoteOnPage(page, 'A MINIMUM OF 24 POINTS').found).toBe(false)   // case is compared as printed
  expect(quoteOnPage(page, '24 pts').reason).toBe('quote_too_short')
  expect(quoteOnPage(foldText('15 November 2026 – Research Fee Scholarship applications close'), '15 November 2026Research Fee Scholarship - applications close'.replace(' - ', ' ')).found).toBe(false)
  expect(quoteOnPage(foldText('It’s a 75% average'), "It's a 75% average").found).toBe(true)
})

test('the worker proves on stored copies, reads a page with none once directly ($0, robots respected) and leaves the decision to the database', () => {
  expect(ix).toContain('const WORKER = "coverage-sweep-worker-v1.0.62"')
  const m = ix.slice(ix.indexOf('if (mode === "intake_verify") {'), ix.indexOf('if (mode === "burst_read") {'))
  expect(m).toContain('rpc("svc_structured_intake_v1", { p_action: "next"')
  expect(m).toContain('p_action: "record"')
  expect(m).toContain('p_action: "store"')
  expect(m).toContain('await readDirect(p.url)')
  expect(m).toContain('fetched.set(p.url, f)')
  expect(m).not.toMatch(/cascadeFetch|fcx\.|useFc|openrouter|insert|\.from\("[a-z_]+"\)\.(insert|update|upsert)/)
})

test('submit is a closed list keyed twice; the course must be the provider\'s course with that code', () => {
  expect(sql).toContain('unique (submitter, candidate_key)')
  expect(sql).toContain('unique (content_key)')
  expect(sql).toContain("c.id = v_cid and c.provider_id = v_pid and upper(coalesce(c.course_code, '')) = v_code")
  expect(sql).toContain("'^https://[a-z0-9.-]+(/|$)'")
  expect(sql).toContain("on conflict do nothing returning id into v_id")
  expect(sql).toMatch(/comment on table pipeline\.structured_intake_items is/)
})

test('decisions use the existing writer and Layer 4; active rows, locks, waiting reads and a person\'s decision are never overridden', () => {
  for (const s of ["'HELD:IDENTITY", "'HELD:BOUND_PAGE_DIFFERS", "'COMPARED", "'HELD:MANUAL_LOCK'", "'HELD:READ_WAITING", "'HELD:PERSON_DECISION", "'REJECTED:QUOTE_NOT_ON_STORED_COPY", "'HELD:VALUE_NOT_IN_QUOTE", "'HELD:SCHOLARSHIP: "]) expect(sql).toContain(s)
  expect(sql).toContain("insert into catalogue.course_entry_requirements(course_id, kind, audience, description, min_grade, min_entry_score, min_entry_score_basis, quote, source_url, evidence_id, confidence, as_at, status, provenance)")
  expect(sql).toContain("'proposed',\n                  jsonb_build_object('reader', 'structured_intake'")
  expect(sql).toContain("values ('course', i.course_id, 'course_entry_first_read', v_req_ev")
  expect(sql).toContain("'dropped', case when coalesce((v_f->>'complete')::boolean, false) then '[]'::jsonb")
  expect(sql).not.toMatch(/status\s*=\s*'active'\s*,|set status = 'active'|update pipeline\.layer4_review_items/)
  expect(sql).not.toMatch(/insert into scholarship\./)
})

test('settings, no job, no drop or delete, consumer API and guards checked', () => {
  for (const k of ['on', 'verify_batch', 'confidence_verified', 'max_items_per_submit', 'max_proofs', 'fetch_on']) expect(sql).toContain(`'structured_intake.${k}'`)
  expect(sql).not.toMatch(/\bdrop\s+(table|function|view|column|index|schema|policy)\b|\bdelete\s+from\b|\btruncate\s+/i)
  expect(sql).not.toMatch(/cron\.schedule/)
  expect(sql).toContain("(v->>'functions')::int <> 75 or (v->>'relations')::int <> 48")
  expect(sql).toMatch(/-- Replaces: nothing\.\n-- Retires: nothing\./)
  expect(sql).toContain("grant execute on function public.svc_structured_intake_v1(text, jsonb, text) to service_role;")
})

test('the operations workflow is hand-started, reads the file at a named admin commit and calls only the governed writer', () => {
  expect(wf).toContain('workflow_dispatch:')
  expect(wf).not.toMatch(/\bpush:|\bschedule:|pull_request/)
  expect(ops).toContain('https://raw.githubusercontent.com/msinghbs-ai/coursefinder-admin/${ref}/${file}')
  expect(ops).toContain("select public.svc_structured_intake_v1(${lit(a)}, ${lit(JSON.stringify(args))}::jsonb, ${lit(by)}) as r")
  expect(ops).toContain('/^[0-9a-f]{40}$/')
})
