// Guards: Platform Admin 20 Nov 2026 22:58 AEDT (S1-CourseLink-2027-CRICOS s893): worker mode link_year_rollover reads each candidate address by a plain read
// only (robots.txt respected, an API time-out, never Firecrawl, never a model), proves the course with the platform's identity rule, keeps the proved page as a
// stored copy in the read lane's own path and format, and writes nothing else; the database decides.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const start = IX.indexOf('if (mode === "link_year_rollover") {'), end = IX.indexOf('if (mode === "fid_det_read") {')
const MODE = IX.slice(start, end)

test('s893: the mode is a plain read with robots.txt, an API time-out and the identity rule; no Firecrawl, no model, no database write', () => {
  expect(start).toBeGreaterThan(0); expect(end).toBeGreaterThan(start)
  expect(MODE).toContain('robotsAllows(await robotsFor(u), u.pathname + u.search)')
  expect(MODE).toContain('signal: AbortSignal.timeout(20000) });  // fixed: API time-out')
  expect(MODE).toContain('identity(html, text, it.title, it.code, false, it.country || "")')
  expect(MODE).toContain('strongIdentity(basis, it.country || "")')
  expect(MODE).toContain('`layer2/${["NZ", "CA"].includes(it.country) ? it.country : "AU"}/coverage/${it.provider_id}/${it.course_id}/${sha}.html.gz`')
  expect(MODE).not.toMatch(/fcx\.|useFc\(|firecrawl|cascadeFetch|openrouter|rpc\(/i)
  expect(MODE).toContain('rule: LINK_ROLLOVER_VERSION')
  expect(IX).toContain('["read", "fc_run", "link_year_rollover"].includes(mode)')
})
