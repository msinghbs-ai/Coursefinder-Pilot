// Guards: SS-Programme-Control 27 Nov 2026 20:45 AEDT (Cloudflare Containers deployment preflight; M3 Cloudflare Containers runbook v1.0): the preflight is read only, deploys nothing, spends nothing, never prints the token and leaves the frontend Worker untouched; the prepared reader Worker is isolated, signed, offline, one slot, and reuses the existing PDF reader modules
// CF-247 s1320. .github/workflows/cloudflare-reader-preflight.yml, cloudflare/reader-burst/
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const wf = fs.readFileSync('.github/workflows/cloudflare-reader-preflight.yml', 'utf8')
const rb = (p) => fs.readFileSync(`cloudflare/reader-burst/${p}`, 'utf8')

test('the preflight starts only by hand and maps the reader token into one step', () => {
  expect(wf).toContain('workflow_dispatch:')
  expect(wf).not.toMatch(/\bpush:|\bschedule:|pull_request/)
  expect(wf.match(/secrets\.[A-Z_]+/g)).toEqual(['secrets.CLOUDFLARE_READER_API_TOKEN'])
  expect(wf).toContain('contents: read')
})

test('it only reads: GET requests, no wrangler deploy, no write verbs', () => {
  expect(wf).not.toMatch(/-X\s*(POST|PUT|PATCH|DELETE)|--request\s*(POST|PUT|PATCH|DELETE)|--data|-d '/)
  expect(wf).not.toMatch(/wrangler(@[\d.]+)?\s+(publish|containers\s+(push|build|delete)|secret|versions)/)
  for (const m of wf.matchAll(/wrangler(@[\d.]+)?\s+deploy[^\n]*/g)) expect(m[0]).toContain('--dry-run')
  expect(wf).toContain('npx --yes wrangler@4.161.0 deploy --dry-run')
  expect(wf.split('build-check:')[1]).toContain('CLOUDFLARE_API_TOKEN: ""')
  expect(wf.split('build-check:')[1]).not.toContain('secrets.')
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

test('the prepared reader Worker: isolated, not reachable until approved, signature checked before any container starts', () => {
  const cfg = JSON.parse(rb('wrangler.jsonc').replace(/^\s*\/\/.*$/gm, ''))
  expect(cfg.name).toBe('studysearch-reader-burst')
  expect(cfg.workers_dev).toBe(false)
  expect(cfg.routes).toBeUndefined()
  expect(cfg.containers[0].scheduling_policy).toBe('durable_object')
  expect(cfg.containers[0].max_instances).toBeUndefined()
  expect(cfg.vars.READER_SLOTS).toBe('reader-01')
  expect(cfg.vars.IDLE_MS).toBe('300000')
  const src = rb('src/index.ts')
  expect(src.indexOf('same(want, sig)')).toBeLessThan(src.indexOf('getByName(slot)'))
  expect(src.indexOf('BODY_HASH')).toBeLessThan(src.indexOf('getByName(slot)'))
  expect(src).toContain('enableInternet: false')
  expect(src).toContain('"REPLAYED"')
  expect(src).toContain('"SLOT_BUSY"')
  expect(src).not.toMatch(/SUPABASE_[A-Z]|service_role|fetch\(\s*["'`]https:/)
})

test('the container reuses the existing reader modules byte for byte, is offline and writes nothing', () => {
  const df = rb('container/Dockerfile'), srv = rb('container/server.ts')
  expect(df).toContain('COPY supabase/functions/coverage-sweep/pdf.ts supabase/functions/coverage-sweep/entry-pdf-scope.ts ./reader/')
  expect(df).toMatch(/^FROM --platform=linux\/amd64 denoland\/deno:debian-\d+\.\d+\.\d+$/m)
  expect(df).toContain('USER deno')
  expect(df).toContain('--cached-only')
  expect(srv).toContain('import { pdfPages, pdfTables, PDF_METHOD } from "./reader/pdf.ts"')
  expect(srv).toContain('npm:unpdf@0.12.1')
  expect(fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')).toContain('npm:unpdf@0.12.1')
  expect(srv).toContain('SOURCE_HASH_MISMATCH')
  expect(srv).not.toMatch(/fetch\(|Deno\.writeFile|createClient|storage\./)
  expect(fs.existsSync('cloudflare/reader-burst/package-lock.json')).toBe(false)
})
