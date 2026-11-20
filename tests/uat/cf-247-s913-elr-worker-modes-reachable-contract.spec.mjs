// Guards: CF-247 s913 (session S1-ELR-Bands-And-Crawl, 21 Nov 2026): the coverage-sweep worker modes of the English requirement sweep (elr_band_read, elr_central_fetch, elr_det_read, elr_central_read) are reachable: none sits inside another mode's block; a fetch call the worker refuses with HTTP 422 returns its pages to the queue (nothing fetched), and pages lost to such calls are queued again
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const W = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const MIG = fs.readFileSync('supabase/migrations/20261121140000_cf247_s913_elr_worker_modes_reachable.sql', 'utf8')
// brace depth at a position, ignoring braces in strings, template text, regular expressions and comments as far as a line scan allows
const depthAt = (pos) => {
  let d = 0
  for (const line of W.slice(0, pos).split('\n')) {
    const code = line.replace(/\/\/.*$/, '').replace(/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`(?:[^`\\]|\\.)*`/g, '""').replace(/\/(?:[^/\\\n]|\\.)+\/[gimsuy]*/g, '""')
    for (const ch of code) { if (ch === '{') d++; else if (ch === '}') d-- }
  }
  return d
}

test('the sweep worker modes are all at the same depth as the other top-level modes', () => {
  const ref = depthAt(W.indexOf('if (mode === "page_text") {'))
  for (const m of ['elr_band_read', 'elr_central_fetch', 'elr_det_read', 'elr_central_read']) {
    const at = W.indexOf(`if (mode === "${m}") {`)
    expect(at, m).toBeGreaterThan(0)
    expect(depthAt(at), m).toBe(ref)
  }
})

test('the read mode closes before the band mode starts (the #1447 fault)', () => {
  const ret = W.indexOf('return j({ ok: true, mode, items: items.length, tally, firecrawlRemainingAboveReserve: fcRemaining')
  const between = W.slice(ret, W.indexOf('if (mode === "elr_band_read") {'))
  expect(between).toMatch(/\n    \}\n/)
})

test('a refused fetch call returns its pages to the queue; the pages already lost to one are queued again', () => {
  expect(MIG).toContain("if q.status_code = 422 then\n        update pipeline.elr_central_fetches set status = 'queued', request_id = null, sent_at = null, done_at = null, result = null where request_id = q.id and status = 'sent';")
  expect(MIG).toContain("where r.id = f.request_id and r.status = 'failed' and (r.result->>'http')::int = 422 and f.status = 'lost';")
  expect(MIG).toContain("'ee7bf0f231e8ab785032a3363b3987e4'")
  expect(MIG).toMatch(/^-- Retires: nothing\./m)
  expect(MIG).not.toMatch(/^(drop|delete|truncate)\b/im)
  expect((MIG.match(/security\.consumer_api_check_v1\(\)/g) || []).length).toBe(2)
})
