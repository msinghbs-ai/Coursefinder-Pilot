// Guards: CF-247 AER programme acceptance reports open evidence gates with their exact reasons (Platform Admin consolidated mandate 28 Oct 2026 23:22; admin docs/platform/ENTRY-REQUIREMENTS-PROGRAMME-DECISION-2026-10-28.md section 5): an entry-matrix model call that answers with no text records why (provider error, finish reason, slice); and on the HTML Firecrawl-fallback route the page's own HTML is kept (not markdown) so its tables are read and quoted row by row like a direct read; the read, its gates and its retries are unchanged
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { entryNoAnswerWhy } from '../../supabase/functions/coverage-sweep/entry.ts'

test('the reason is named from what OpenRouter returns', () => {
  expect(entryNoAnswerWhy({ choices: [{ message: { content: '' }, finish_reason: 'error', error: { message: 'Upstream timeout' } }], provider: 'OpenAI' }, 2, 3))
    .toBe(' (error: Upstream timeout; finish: error; provider: OpenAI; slice 2 of 3)')
  expect(entryNoAnswerWhy({ error: { message: 'Provider returned error', code: 502 } }, 1, 1)).toBe(' (error: Provider returned error; no choices)')
  expect(entryNoAnswerWhy({ choices: [{ message: { content: '' } }] }, 1, 1)).toBe('')
})

test('worker v0.50.2 uses it where the entry read finds no text; nothing else in the read changes', () => {
  const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  const ai = w.slice(w.indexOf('if (mode === "entry_ai") {'), w.indexOf('if (mode === "fee_ai") {'))
  expect(w).toMatch(/const WORKER = "coverage-sweep-worker-v0\.(50\.([2-9]|\d{2,})|5[1-9]\.\d+)"/)
  expect(ai).toContain('if (!content.trim()) throw Error(`the model returned no answer${entryNoAnswerWhy(d, i + 1, slices.length)}`);')
  expect(ai).toContain('const parsed = entryMatrixParsed(JSON.parse(content), page, stored.lines);')
  expect(ai).toContain('if (it.completeness_required === true && completeness.status !== "complete") {')
})

test('Firecrawl fallback for an entry page keeps the page HTML, through the budget check, never markdown', () => {
  const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  const f = w.slice(w.indexOf('const d1 = await readDirect(it.url);'), w.indexOf('fetchTally[via] = (fetchTally[via] || 0) + 1;'))
  expect(f).toContain('const g = await useFcWhy("provider_facts_scrape", it.provider_id, it.url, true);')
  expect(f).toContain('body: JSON.stringify(scrapeBody(it.url, { read_formats: ["rawHtml"], read_proxy: FC_PROXY }, String(it.country || ""))), signal: AbortSignal.timeout(90000) });')
  expect(f).toContain('body1 = pageHtml(d); via = "firecrawl"; mime = "text/html";')
  expect(f).not.toContain('"markdown"')
  expect(f).toContain('if (d1.status === "robots_disallowed")')
})
