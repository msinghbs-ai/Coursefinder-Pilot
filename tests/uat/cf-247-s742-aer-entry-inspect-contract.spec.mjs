// Guards: S742 AER entry-matrix stored pages export (Platform Admin 19 Nov 2026 05:42 AEDT item 3, session S2-BOOST-AER; standing rule 17 Nov 2026: database runs through GitHub Actions and the Management API, no confirmation prompt): the export is read only (Management API reads with read_only, the worker's read-only mode entry_inspect), dispatch only, and writes nothing but its artifact.
// CF-247 S742. Script scripts/aer-entry-inspect.mjs; workflow aer-entry-inspect.yml.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const S = fs.readFileSync('scripts/aer-entry-inspect.mjs', 'utf8')
const W = fs.readFileSync('.github/workflows/aer-entry-inspect.yml', 'utf8')
const LIB = fs.readFileSync('scripts/boost-live-lib.mjs', 'utf8')

test('the export reads through the read-only Management API call and asks only the read-only worker mode entry_inspect', () => {
  expect(S).toContain("import { need, read, lit, worker, summary } from './boost-live-lib.mjs'")
  expect(LIB).toContain('export const read = (query) => call(query, true)')
  expect(S).toContain("jsonb_build_object('mode', 'entry_inspect'")
  expect(S).toContain("if (res.mode !== 'entry_inspect') throw Error")
  // no other worker mode, no write statement, no model or fetch route
  expect((S.match(/'mode', '/g) || []).length).toBe(1)
  expect(S).not.toMatch(/\b(insert|update|delete|truncate|alter|create)\s+(into|table|from|or)\b/i)
  expect(S).not.toMatch(/openrouter|firecrawl|on_demand_open/i)
  expect(S).toContain("fs.writeFileSync('out/aer-entry-pages.json'")
  // the read-only role cannot run security functions: the list is read from the tables
  expect(S).not.toMatch(/security\.[a-z_]+\(/)
})

test('the workflow is dispatch only, holds no write permission and keeps the result as an artifact', () => {
  expect(W).toMatch(/^on:\n  workflow_dispatch:/m)
  expect(W).not.toMatch(/^\s+schedule:|^\s+push:|^\s+pull_request:/m)
  expect(W).toContain('contents: read')
  expect(W).not.toMatch(/contents: write|pull-requests: write/)
  expect(W).toContain('node scripts/aer-entry-inspect.mjs "${{ inputs.rules }}"')
  expect(W).toContain('name: aer-entry-pages')
})
