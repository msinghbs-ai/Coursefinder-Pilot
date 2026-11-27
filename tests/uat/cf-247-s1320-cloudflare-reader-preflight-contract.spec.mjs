// Guards: SS-Programme-Control 27 Nov 2026 20:45 AEDT (Cloudflare Containers deployment preflight): the preflight is read only, deploys nothing, spends nothing, never prints the token and leaves the frontend Worker untouched
// CF-247 s1320. .github/workflows/cloudflare-reader-preflight.yml
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const wf = fs.readFileSync('.github/workflows/cloudflare-reader-preflight.yml', 'utf8')

test('the preflight starts only by hand and maps the reader token into one step', () => {
  expect(wf).toContain('workflow_dispatch:')
  expect(wf).not.toMatch(/\bpush:|\bschedule:|pull_request/)
  expect(wf.match(/secrets\.[A-Z_]+/g)).toEqual(['secrets.CLOUDFLARE_READER_API_TOKEN'])
  expect(wf).toContain('contents: read')
})

test('it only reads: GET requests, no wrangler deploy, no write verbs', () => {
  expect(wf).not.toMatch(/-X\s*(POST|PUT|PATCH|DELETE)|--request\s*(POST|PUT|PATCH|DELETE)|--data|-d '/)
  expect(wf).not.toMatch(/wrangler\s+(deploy|publish|containers\s+(push|build|delete)|secret)/)
  for (const p of ['/user/tokens/verify', '/accounts?per_page=50', '/workers/scripts', '/subscriptions', '/containers/applications']) expect(wf).toContain(p)
})

test('the token is never printed and the frontend Worker configuration is unchanged', () => {
  expect(wf).not.toMatch(/echo[^\n]*\$\{?CF_TOKEN/)
  expect(wf).toContain('value not shown')
  const fe = JSON.parse(fs.readFileSync('wrangler.jsonc', 'utf8'))
  expect(fe.name).toBe('coursefinder-pilot')
  expect(fe.containers).toBeUndefined()
  expect(fe.durable_objects).toBeUndefined()
})
