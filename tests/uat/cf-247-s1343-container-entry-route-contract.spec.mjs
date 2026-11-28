// Guards: SS-Programme-Control 28 Nov 2026 08:39, 09:03 and 10:11 AEDT (route qualified Cloudflare reads into the existing entry reader with the smallest change; Supabase stays the validation and admission authority); Decision 2 limits (one container, compute caps) unchanged; no drop or delete by an applied migration
// CF-247 s1343. supabase/functions/coverage-sweep/index.ts (v1.0.63 burstEntryPages, storedText), supabase/migrations/20261201033000_cf247_s1343_container_entry_route.sql
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const ix = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const sql = fs.readFileSync('supabase/migrations/20261201033000_cf247_s1343_container_entry_route.sql', 'utf8')

test('the entry reader asks the gate first, sends a signed copy, and uses only hash-matched pages; anything else reads here as before', () => {
  expect(ix).toContain('const WORKER = "coverage-sweep-worker-v1.0.67"')
  const h = ix.slice(ix.indexOf('const burstEntryPages = async'), ix.indexOf('const robots = new Map'))
  expect(h.indexOf('p_action: "gate"')).toBeLessThan(h.indexOf('await fetch('))
  expect(h).toContain('route: "entry_matrix"')
  expect(h).toContain('"x-ss-signature": sig')
  expect(h).toContain('out?.source_sha256 === g.content_hash && Array.isArray(out?.pdfPages)')
  expect(h).toContain('p_action: "record"')
  expect(h).not.toMatch(/SUPABASE_SERVICE_ROLE_KEY|Authorization|apikey/)
})

test('the routed pages go through the same table reader and scope retry, cut to the read\'s own page cap', () => {
  const st = ix.slice(ix.indexOf('const storedText = async'), ix.indexOf('const storedText = async') + 4000)
  expect(st).toContain('const routed = await burstEntryPages(path, b).catch(() => null);')
  expect(st).toContain('routed.filter((q: any) => Number(q?.p) >= 1 && Number(q.p) <= pdfMaxPages)')
  expect(st).toContain('return pdfPages(doc, OPS, pdfMaxPages)')
  expect(st.indexOf('const routed')).toBeLessThan(st.indexOf('t = pdfTables(pages)'))
  expect(st).toContain('entryTablePageScope(pages)')
})

test('the gate: a stored copy by its path, a routing switch as a setting, every other rule unchanged; nothing dropped', () => {
  expect(sql).toContain("md5(d) <> 'c7c20af099c61eff6dd6843c6df4a42f'")
  expect(sql).toContain("storage_path = p_args->>''storage_path'' and evidence_type = ''source_snapshot''")
  expect(sql).toContain("HELD:ROUTE_OFF")
  expect(sql).toMatch(/'cloudflare_reader\.route_entry_pdf'[\s\S]{0,400}?to_jsonb\(1\), 0, 1, 'switch'/)
  expect(sql).toContain("(v->>'functions')::int <> 75 or (v->>'relations')::int <> 48")
  expect(sql).not.toMatch(/\bdrop\s+(table|function|view|column|index|schema|policy)\b|\bdelete\s+from\b|cron\.schedule/i)
  expect(sql).toMatch(/-- Retires: nothing\./)
})
