// Guards: CF-247 AER programme Step C (Platform Admin consolidated mandate 28 Oct 2026 23:22; admin docs/platform/ENTRY-REQUIREMENTS-PROGRAMME-DECISION-2026-10-28.md P5 and section 4): a JavaScript-only entry page is read once rendered through Firecrawl, robots.txt respected, within the Firecrawl budget check, named by setting (entry.render_hosts, empty until the worker is live); no minimum on the rendered page gives no rows (contact provider), never an endless retry
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261029002000_cf247_aer_steps_b_c_pdf_and_rendered.sql', 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const ai = w.slice(w.indexOf('if (mode === "entry_ai") {'), w.indexOf('if (mode === "fee_ai") {'))
const render = ai.slice(ai.indexOf('if (it.render === true) {'), ai.indexOf('const d1 = await readDirect(it.url);'))

test('settings name the rendered sites and the wait; empty in the change that brings the worker', () => {
  expect(code).toContain("('pipeline', 'entry.render_hosts', ")
  expect(code).toContain("'[]'::jsonb, null, null, 'hosts', 923, 'Entry requirements'")
  expect(code).toContain("to_jsonb(5000), 1000, 30000, 'milliseconds', 924,")
  expect(code).toContain("if jsonb_array_length(coalesce(security.toolset_setting('pipeline', 'entry.render_hosts'), '[]'::jsonb)) <> 0 then raise exception")
  expect(code).toContain("'render', coalesce(security.toolset_setting('pipeline', 'entry.render_hosts'), '[]'::jsonb) ? lower(substring(u.url from '^https?://(?:www\\.)?([^/:?#]+)')),")
})

test('worker: robots first, the Firecrawl budget check, rawHtml with the set wait, stored and read as HTML', () => {
  expect(render).toContain('if (!robotsAllows(await robotsFor(u), u.pathname + u.search)) { await frec({ p_status: "robots_disallowed" });')
  expect(render).toContain('const g = await useFcWhy("provider_facts_scrape", it.provider_id, it.url, true);')
  expect(render).toContain('if (!g.ok) { await frec({ p_error: g.why });')
  expect(render).toContain('scrapeBody(it.url, { read_formats: ["rawHtml"], read_proxy: FC_PROXY, read_wait_ms: Number(it.render_wait_ms) || 5000 }, String(it.country || ""))')
  expect(render).toContain('await frec({ p_status: "read", p_via: "firecrawl", p_http: http, p_storage_path: path, p_sha256: sha, p_mime: "text/html" });')
  expect(render.indexOf('robotsAllows')).toBeLessThan(render.indexOf('useFcWhy'))
  // a refusal or an empty render is recorded and retried only within entry.matrix_attempts (a budget refusal does not use a try)
  expect(render).toContain('await frec({ p_http: http, p_error: d?.error || "no rendered content" });')
})
