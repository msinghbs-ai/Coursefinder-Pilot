// Guards: S750 AER v2 chunked matrix smoke test, MiMo v2.6 Flash only at 12 rows a call on 20 gate-held tables (Platform Admin 19 Nov 2026 13:05 AEDT, session S2-BOOST-AER): worker and script only (no schema migration), spend at most US$0.05 in a bounded on-demand window closed whatever happens, each call's duration reported against the 90 s time-out, a failed row returned with the model's own answer, an inspect path with no model call and no spend, and nothing admitted or promoted.
// CF-247 S750. Worker coverage-sweep v1.0.29 mode aer_chunk_smoke; scripts/aer-chunk-smoke.mjs; workflow aer-chunk-smoke.yml; tests/fixtures/aer-chunks/smoke-tables-20.json.
// G2, G3 and housekeeping are guarded centrally by s32, s57 and s42; the S747 mode itself by s747.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import zlib from 'node:zlib'
import { entryChunks, entryChunkGroups } from '../../supabase/functions/coverage-sweep/entry-chunks.ts'
import { htmlToText } from '../../supabase/functions/coverage-sweep/extract.ts'

const W = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const S = fs.readFileSync('scripts/aer-chunk-smoke.mjs', 'utf8')
const Y = fs.readFileSync('.github/workflows/aer-chunk-smoke.yml', 'utf8')
const block = W.split('if (mode === AER_CHUNK_MODE) {')[1].split('    if (mode === "entry_inspect") {')[0]

test('worker v1.0.29: call duration, the model answer for a failed row, inspect only before any credential or spend', () => {
  expect(W).toContain('// v1.0.29 (19 Nov 2026, CF-247 S750')
  expect(block).toContain('res.call_ms = Date.now() - tc;')
  expect(block).toContain("res.misses = res.verified.checks.filter((k: any) => !k.answered || k.quote_in_row === false || k.minimum_in_quote === false)")
  const insp = block.indexOf('if (body.inspect_only === true) return j(')
  expect(insp).toBeGreaterThan(0)
  for (const later of ['const maxUsd = Math.min(Number(body.max_usd) || 0, 0.10);', 'let key = Deno.env.get("OPENROUTER_API_KEY")', 'await cascadeFetch(']) expect(block.indexOf(later), later).toBeGreaterThan(insp)
  expect(block).toContain('AbortSignal.timeout(Math.max(5000, Math.min(90000,')
})

test('the run takes one model, a rows-a-call figure and a table set; spend is capped below US$0.10 with one call of margin; an inspect list opens no window', () => {
  expect(S).toContain("const MODEL = String(process.argv[3] || 'all')")
  expect(S).toContain('const ROWS = Math.max(0, Math.min(40, Math.floor(Number(process.argv[4]) || 0)))')
  expect(S).toContain("const SET = /^[a-z0-9-]+\\.json$/.test(String(process.argv[5] || '')) ? String(process.argv[5]) : 'smoke-tables.json'")
  expect(S).toContain('if (spent >= CAP - Math.min(0.01, CAP / 10))')
  expect(S).toContain('rows_per_call: ROWS || Number(v.spec?.rows_per_call) || 25')
  const insp = S.indexOf('if (INSPECT.length) {'), open = S.indexOf("security.on_demand_open_v1('claude_session'")
  expect(insp).toBeGreaterThan(0); expect(insp).toBeLessThan(open)
  expect(S.slice(insp, open)).toContain("inspect_only: true"); expect(S.slice(insp, open)).toContain('process.exit(0)')
  expect(S).toContain('max_call_ms: callMs.length ? Math.max(...callMs) : null')
  expect(S.split('} finally {')[1].split('\n}\n')[0]).toContain('security.on_demand_close_v1(')
  for (const k of ['MODEL: ${{ inputs.model }}', 'ROWS: ${{ inputs.rows_per_call }}', 'TABLES: ${{ inputs.tables }}', 'INSPECT: ${{ inputs.inspect }}']) expect(Y).toContain(k)
  expect(Y).toContain('run: node scripts/aer-chunk-smoke.mjs "$MAXUSD" "$MODEL" "$ROWS" "$TABLES" "$INSPECT"')  // S751 adds "$PV" after it
})

test('the 20 tables are the S747 rule with the character bound at 16,000, one per provider, keeping the S747 ten; 12 rows a call never mixes tables', () => {
  const B = 'tests/fixtures/aer-chunks/held/'
  const man = JSON.parse(fs.readFileSync(`${B}manifest.json`, 'utf8')).pages
  const quals = JSON.parse(fs.readFileSync('tests/fixtures/entry-cells/qualifications.json', 'utf8')).qualifications
  const sel = JSON.parse(fs.readFileSync('tests/fixtures/aer-chunks/smoke-tables-20.json', 'utf8')).tables
  const ten = JSON.parse(fs.readFileSync('tests/fixtures/aer-chunks/smoke-tables.json', 'utf8')).tables
  const cand = []
  for (const m of man.filter((x) => x.rule === 'gate_incomplete')) {
    const s = entryChunks(zlib.gunzipSync(fs.readFileSync(B + m.file)).toString('utf8'), htmlToText, { qualifications: quals })
    const by = {}; for (const c of s.chunks) if (c.kind === 'table_row') (by[c.table] ||= []).push(c)
    const ok = Object.entries(by).map(([k, v]) => ({ table: Number(k), rows: v.length, chars: v.reduce((a, c) => a + c.quote.length, 0), first: v[0].quote, groups: entryChunkGroups(v, 12) }))
      .filter((t) => t.rows >= 8 && t.rows <= 70 && t.chars <= 16000).sort((a, b) => b.rows - a.rows || a.table - b.table)
    if (ok.length) cand.push({ file: m.file, source_id: m.source_id, host: new URL(m.url).hostname.replace(/^www\./, ''), lost: m.dropped_lost, ...ok[0] })
  }
  cand.sort((a, b) => b.lost - a.lost || a.file.localeCompare(b.file))
  const seen = new Set(), pick = []
  for (const c of cand) { if (seen.has(c.host)) continue; seen.add(c.host); pick.push(c); if (pick.length === 20) break }
  expect(pick.map((p) => [p.source_id, p.table, p.rows, p.first])).toEqual(sel.map((t) => [t.source_id, t.table, t.rows, t.first]))
  expect(new Set(pick.map((p) => p.host)).size).toBe(20)
  expect(sel.reduce((a, t) => a + t.rows, 0)).toBe(645)
  for (const t of ten) expect(sel.some((x) => x.source_id === t.source_id && x.table === t.table), t.file).toBe(true)
  for (const p of pick) for (const g of p.groups) { expect(g.length).toBeLessThanOrEqual(12); expect(new Set(g.map((c) => c.table)).size).toBe(1) }
})
