// Guards: SS-Programme-Control 28 Nov 2026 07:44 and 09:03 AEDT (direct read first, then the authorised Firecrawl route for a known direct-read refusal; UNE 82 fees); CLAUDE.md on-demand work opened, reported and closed; a challenge page is never bypassed
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
  expect(w).toContain('log: (p) => c.rpc("svc_fc_call_log", { p })')
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
