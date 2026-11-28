// Guards: Admin #1048 (Platform Admin 25 Nov 2026 05:55 AEDT: fix extension-less PDF acquisition using verified HTTP Content-Type and PDF file signatures, not URL extensions or the #.pdf workaround; preserve spending controls)
// s1110: an entry-matrix page served as a PDF at an address with no ".pdf" is read as a PDF, proven by its Content-Type and its own "%PDF-" signature; the CQU "#.pdf" copy is retired; runs failed by the historical weekly key limit are read again from their stored copies.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFileSync } from 'node:child_process'

async function load(file, name) {
  const out = path.join(os.tmpdir(), `${name}-${process.pid}.mjs`)
  execFileSync('node_modules/.bin/esbuild', [file, '--bundle', '--format=esm', '--platform=node', `--outfile=${out}`, '--log-level=error'])
  return import(out)
}
const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const MIG = fs.readFileSync('supabase/migrations/20261126090000_cf247_s1110_entry_pdf_by_content_type.sql', 'utf8')
const bytes = (s) => new TextEncoder().encode(s)

test('s1110: the Content-Type and the file signature decide a PDF, never the address', async () => {
  const m = await load('supabase/functions/coverage-sweep/entry-pdf-sniff.ts', 'sniff1110')
  for (const t of ['application/pdf', 'Application/PDF; charset=binary', 'application/x-pdf', 'text/pdf']) expect(m.pdfHint(t), t).toBe('pdf')
  for (const t of ['application/octet-stream', 'binary/octet-stream', 'application/force-download', '', null]) expect(m.pdfHint(t), String(t)).toBe('unnamed')
  for (const t of ['text/html; charset=utf-8', 'application/json', 'image/png', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document']) expect(m.pdfHint(t), t).toBe('other')
  expect(m.hasPdfSignature(bytes('%PDF-1.7\n%âãÏÓ'))).toBe(true)
  expect(m.hasPdfSignature(bytes('\r\n﻿%PDF-1.4'))).toBe(true)  // a few bytes before the header are allowed
  expect(m.hasPdfSignature(bytes(' '.repeat(1100) + '%PDF-1.4'))).toBe(false)  // only the first 1,024 bytes count
  expect(m.hasPdfSignature(bytes('<!doctype html><title>PDF</title>'))).toBe(false)
  expect(m.hasPdfSignature(bytes('%PDF'))).toBe(false)
  expect(m.hasPdfSignature(null)).toBe(false)
})

test('s1110: which direct reads are fetched again as a PDF', async () => {
  const m = await load('supabase/functions/coverage-sweep/entry-pdf-sniff.ts', 'sniff1110b')
  // CQUniversity: HTTP 200, a PDF type, no HTML kept (the read the worker used to record as not_html)
  expect(m.retryAsPdf({ status: 'not_html', ctype: 'application/pdf', html: '' })).toBe(true)
  expect(m.retryAsPdf({ status: 'not_html', ctype: 'application/octet-stream', html: '' })).toBe(true)
  expect(m.retryAsPdf({ status: 'not_html', ctype: null, html: '' })).toBe(true)
  // a PDF mislabelled as a page: the text it sent starts like a PDF
  expect(m.retryAsPdf({ status: 'read', ctype: 'text/html', html: '%PDF-1.6\n1 0 obj' })).toBe(true)
  // a page, an image, a refusal, a missing page and robots stay as they were
  expect(m.retryAsPdf({ status: 'read', ctype: 'text/html', html: '<html><body>entry requirements</body></html>' })).toBe(false)
  expect(m.retryAsPdf({ status: 'too_thin', ctype: 'text/html', html: '<html></html>' })).toBe(false)
  expect(m.retryAsPdf({ status: 'not_html', ctype: 'image/png', html: '' })).toBe(false)
  for (const s of ['blocked', 'gone', 'robots_disallowed', 'fetch_failed']) expect(m.retryAsPdf({ status: s, ctype: 'application/pdf', html: '' }), s).toBe(false)
})

test('s1110: the worker reads such an address as a PDF directly, stores it as application/pdf and counts it as a PDF', () => {
  expect(IX).toContain('const WORKER = "coverage-sweep-worker-v1.0.64"')
  expect(IX).toContain('import { hasPdfSignature, retryAsPdf } from "./entry-pdf-sniff.ts";')
  expect(IX).toContain('ctype = r.headers.get("content-type");')
  expect(IX).toContain('return { status, http, html, finalUrl, ctype };')
  expect(IX).toContain('if (!hasPdfSignature(b)) return { status: "not_pdf", http, bytes: null };')
  const at = IX.indexOf('if (retryAsPdf(d1)) {')
  expect(at).toBeGreaterThan(0)
  const branch = IX.slice(at, IX.indexOf('if (d1.status === "read") body1 = d1.html;', at))
  expect(branch).toContain('const p = await readPdf(it.url, Number(it.pdf_max_bytes) || 20000000);')  // robots.txt and the size cap of any PDF source
  expect(branch).toContain('await keepPdf({ http: p.http, bytes: p.bytes }, "pdf_by_type"); return')
  expect(branch).toContain('no PDF signature')
  expect(branch).not.toMatch(/fcx\.|useFc|cascadeFetch|openrouter/i)  // no Firecrawl, no model
  expect(IX).toContain('p_mime: "application/pdf" }); fetchTally[key]')
  expect(IX).toContain('|| isPdfCopy(it.mime, String(it.storage_path || ""))) && pdfTaken++ >=')
})

test('s1110: the CQU workaround copy is retired only when it holds nothing, and the key-limit runs go through the existing re-read', () => {
  expect(MIG).toContain("v_c.url <> v_o.url || '#.pdf'")
  expect(MIG).toContain("if v_rows > 0 or v_wait > 0 or v_o.status not in ('failed', 'found') then")
  // an expired-claim hand-back: the existing fetch takes it 20 minutes later, so worker v1.0.40 (deployed after the migration) makes the first fetch
  expect(MIG).toContain("update pipeline.entry_matrix_sources set status = 'reading', attempts = 0, error = null, updated_at = now() where id = v_orig;")
  expect(MIG).toContain("update pipeline.entry_matrix_sources set status = 'inactive'")
  expect(MIG).toContain("r.state = 'failed' and r.error ~* 'key limit exceeded' and s.status = 'read'")
  expect(MIG).toContain('v_out := public.admin_entry_matrix_reread(v_src,')
  expect(MIG).not.toMatch(/platform_toolset_settings|ai_service_routes|svc_fc_spend|daily_budget|\bdelete from\b|\bdrop\s+(table|function|trigger|index|view)|truncate |cron\.schedule|cron\.alter_job/i)
  for (const s of ['post-check: the consumer API moved', 'post-check: manual locks changed', 'post-check: the number of active cron jobs changed']) expect(MIG).toContain(s)
})
