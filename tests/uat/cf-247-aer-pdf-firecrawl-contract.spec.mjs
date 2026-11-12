// Guards: Platform Admin 12 Nov 2026 20:23 ("use firecrawl for http is refused and store the artifact as evidence in storage"): a refused PDF is fetched once through Firecrawl within the budget check, stored in the evidence bucket and read as text
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

test('a refused PDF (401, 403, 406, 429) goes to Firecrawl only with its switch and the budget check, and is stored as evidence before it is recorded read', () => {
  const ix = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  const i = ix.indexOf('if (!p.bytes && p.status === "blocked_pdf" && Number(ws["reading.entry_pdf_firecrawl_on"]) >= 1)')
  expect(i).toBeGreaterThan(0)
  const block = ix.slice(i, ix.indexOf('fetchTally.pdf_firecrawl', i))
  expect(block).toContain('await useFcWhy("provider_facts_scrape", it.provider_id, it.url, true)')
  expect(block).toContain('read_formats: ["markdown"]')
  expect(block).toMatch(/c\.storage\.from\("evidence"\)\.upload\(path, await gzip\(md\)/)
  expect(block.indexOf('storage.from("evidence")')).toBeLessThan(block.indexOf('p_status: "read", p_via: "firecrawl"'))
  expect(block).toContain('.md.gz')
  expect(ix).toMatch(/(const WORKER = "coverage-sweep-worker-v0\.80\.0"|\/\/ was v0\.80\.0 \/\/ v0\.80\.0 \(12 Nov 2026, CF-247 AER source recovery)/)  // v0.80.0 or later (v0.81.0: calendar reader v2.4)
  const m = fs.readFileSync('supabase/migrations/20261113123100_cf247_aer_pdf_firecrawl_fallback.sql', 'utf8')
  expect(m).toContain("'reading.entry_pdf_firecrawl_on'")
  expect(m).toMatch(/where s\.error = 'blocked_pdf' and s\.status in \('failed', 'found'\)/)
  expect(m).not.toMatch(/^\s*(delete|drop|truncate)\b/im)
})
