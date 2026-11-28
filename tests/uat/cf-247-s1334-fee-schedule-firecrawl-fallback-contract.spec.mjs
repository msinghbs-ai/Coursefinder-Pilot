// Guards: SS-Programme-Control 28 Nov 2026 07:44 and 09:03 AEDT (direct read first, then the authorised Firecrawl route for a known direct-read refusal; UNE 82 fees); CLAUDE.md on-demand work opened, reported and closed; a challenge page is never bypassed ; s1334 v0.9.4: column labels written into cells by the browser are read as the plain page
// CF-247 s1334. supabase/functions/fee-schedule-etl/index.ts (v0.9.1), scripts/fee-schedule-run.mjs
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const w = fs.readFileSync('supabase/functions/fee-schedule-etl/index.ts', 'utf8')
const run = fs.readFileSync('scripts/fee-schedule-run.mjs', 'utf8')

test('the direct read comes first; only an HTML schedule the site refuses goes to Firecrawl, through the one client and the spend gate', () => {
  expect(w).toContain('import { fcClient } from "../coverage-sweep/firecrawl.ts";')
  const i = w.indexOf('const rr = await fetch(su,'), k = w.indexOf('fcx.scrape(')
  expect(i).toBeGreaterThan(0); expect(k).toBeGreaterThan(i)
  expect(w).toContain('sc.format === "html" && [401, 403, 406, 429].includes(rr.status)')
  expect(w.indexOf('rpc("svc_fc_spend"')).toBeLessThan(k)
  expect(w).toContain('log: async (p) => { await c.rpc("svc_fc_call_log", { p }) }')
  expect(w).toContain('proxy: "basic"')
  expect(w).not.toMatch(/proxy: "(stealth|enhanced|auto)"/)
  expect(w).toMatch(/Pardon Our Interruption\|Just a moment/)
})

test('the run opens one on-demand window only when the worker asks for it, and always closes it', () => {
  expect(run).toContain('FIRECRAWL_NEEDS_PROVIDER')
  expect(run).toContain("security.on_demand_open_v1('claude_session'")
  expect(run).toContain("array['firecrawl']")
  expect(run).toContain('security.on_demand_close_v1(')
  expect(run.indexOf('on_demand_open_v1')).toBeGreaterThan(run.indexOf('let { r, res } = await callWorker(null)'))
})

test('a page drawn by the browser (column labels written into the cells) reads the same rows as the plain page', async () => {
  const { transformSync } = await import('esbuild')
  const src = fs.readFileSync('supabase/functions/fee-schedule-etl/html-rows.ts', 'utf8')
  const { htmlRows } = await import('data:text/javascript;base64,' + Buffer.from(transformSync(src, { loader: 'ts', format: 'esm' }).code).toString('base64'))
  const head = '<tr><th>Course</th><th>Intakes</th><th>CRICOS</th><th>Fee</th></tr>'
  const plain = `<table>${head}<tr><td>Bachelor of Arts</td><td>1 &amp; 2</td><td>054919F</td><td>31,632*</td></tr></table>`
  const drawn = `<table>${head}<tr><td><span>Course</span> Bachelor of Arts</td><td><span>Intakes</span> 1 &amp; 2</td><td><span>CRICOS</span> 054919F</td><td><span>Fee</span> 31,632*</td></tr></table>`
  const want = ['Bachelor of Arts | 1 & 2 | 054919F | $31,632']
  expect(htmlRows(plain, /\bCRICOS\b.*\bFee\b/i, true).rows).toEqual(want)
  expect(htmlRows(drawn, /\bCRICOS\b.*\bFee\b/i, true).rows).toEqual(want)
  // a cell that only equals its header, or merely contains it later, is left as it is
  expect(htmlRows(`<table>${head}<tr><td>Course</td><td>x</td><td>Fee CRICOS 054919F</td><td>31,632</td></tr></table>`, /\bCRICOS\b.*\bFee\b/i, true).rows).toEqual(['Course | x | Fee CRICOS 054919F | $31,632'])
})
