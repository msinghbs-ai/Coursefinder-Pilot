// CF-247 Phase 3 (Platform Admin 9 Oct 2026): the merged adapter step runs side by side with Layer 3 and admits nothing.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFileSync } from 'node:child_process'

let shadowInput
test.beforeAll(async () => {
  const out = path.join(os.tmpdir(), `adapter-shadow-${process.pid}.mjs`)
  execFileSync('npx', ['esbuild', 'supabase/functions/_shared/cf247-adapter-shadow.ts', '--bundle', '--format=esm', '--platform=node', `--outfile=${out}`, '--log-level=error'])
  ;({ shadowInput } = await import(out))
})

const page = '<html><body><h1>Bachelor of Things</h1><p>Overview text about the course.</p><h2>Entry requirements</h2><p>IELTS 6.5 overall, no band below 6.0.</p><h2>Intakes</h2><p>February and July each year.</p></body></html>'

test('merged step input: the adapter section first, the whole page when the adapter names nothing', () => {
  const sec = shadowInput({ sections: { english: 'Entry requirements', intakes: 'Intakes' }, section_chars: 300 }, page, 'english')
  expect(sec.basis).toBe('adapter_section')
  expect(sec.text).toContain('IELTS 6.5')
  expect(sec.text).not.toContain('Overview text')
  const none = shadowInput({ sections: {} }, page, 'intake')
  expect(none.basis).toBe('page')
  expect(none.text).toContain('Overview text')
  const missing = shadowInput({ sections: { intakes: 'Commencement dates' } }, page, 'intake')
  expect(missing.basis).toBe('page')
})

test('merged step input: a JSON path in the page data is used when it holds the field', () => {
  const html = '<html><body><script id="__NEXT_DATA__" type="application/json">{"props":{"course":{"intakes":"March, September"}}}</script><p>Other text</p></body></html>'
  const j = shadowInput({ json_source: '__NEXT_DATA__', json_paths: { intakes: 'props.course.intakes' } }, html, 'intake')
  expect(j.basis).toBe('adapter_json')
  expect(j.text).toContain('March, September')
})

test('worker: shadow mode uses the Layer 3 contract and checks, records only, and leaves the routing version alone', () => {
  const w = fs.readFileSync('supabase/functions/layer3-model-routing/index.ts', 'utf8')
  expect(w).toContain('if (mode === "shadow") {')
  expect(w).toContain('const SHADOW_V = "cf247-adapter-shadow-v1.0.0";')
  expect(w).toContain('rpc("svc_adapter_shadow_claim"')
  expect(w).toContain('rpc("svc_adapter_shadow_complete"')
  expect(w).toContain("if (!isPinnedModel(model)) throw new Error(\"the adapter's model is not a pinned model\");")
  const shadow = w.slice(w.indexOf('if (mode === "shadow") {'), w.indexOf('if (mode === "work") {'))
  expect(shadow).not.toMatch(/layer3_fact_complete|fact_admit|svc_coursefacts_apply_record/)
  const routing = fs.readFileSync('supabase/functions/_shared/cf247-model-routing.ts', 'utf8')
  expect(routing).toContain('export const ROUTING_VERSION = "cf247-l3-model-routing-v1.0.0";')
})

test('migration: limits, retire test reported only, nothing deleted, nothing admitted', () => {
  const m = fs.readFileSync('supabase/migrations/20261008005300_cf247_phase3_adapter_shadow.sql', 'utf8')
  expect(m).toContain('daily_usd_max numeric not null default 15')
  expect(m).toContain('daily_reads_max int not null default 1000')
  expect(m).toContain('retire_match numeric not null default 0.95')
  expect(m).toContain("and t.agree_n::numeric / t.both_found >= s.retire_match and t.shadow_found_n >= t.layer3_found_n")
  expect(m).toContain("if v_spent >= s.daily_usd_max then")
  expect(m).not.toMatch(/delete\s+from|drop\s+(table|function|schema)|truncate/i)
  expect(m).not.toMatch(/svc_coursefacts_apply_record|layer3_fact_admit/)
  expect(m).toContain("cron.schedule('adapter-shadow-intake'")
  expect(m).toContain("cron.schedule('adapter-shadow-english'")
})
