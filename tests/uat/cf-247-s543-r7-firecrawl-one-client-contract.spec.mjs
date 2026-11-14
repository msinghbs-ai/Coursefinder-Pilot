// Guards: CF-247 R7 (admin docs/audits/studysearch-ingestion-validation-report.md §5.3 R7, §7 recommendations 4 and 8): one Firecrawl client; a rendered 4xx/5xx page is never a read; the page's own status is kept with the evidence
// 7 days to 14 Nov 2026: pipeline.firecrawl_calls held 74 calls against 29,695 credits of Firecrawl use, because 35 inline call sites in
// coverage-sweep/index.ts bypassed the governed client, and the course read fallback, view render and entry_ai renders took a rendered error page
// as the page. Worker v0.94.0 sends every call through fcClient (firecrawl.ts); migration 20261114193000 keeps page_status in the evidence metadata.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFileSync } from 'node:child_process'

const DIR = 'supabase/functions/coverage-sweep'
const ix = fs.readFileSync(`${DIR}/index.ts`, 'utf8')
const mig = fs.readFileSync('supabase/migrations/20261114193000_cf247_r7_firecrawl_page_status.sql', 'utf8')

async function loadFc() {
  const out = path.join(os.tmpdir(), `firecrawl-s543-${process.pid}.mjs`)
  execFileSync('node_modules/.bin/esbuild', [`${DIR}/firecrawl.ts`, '--format=esm', '--platform=node', `--outfile=${out}`, '--log-level=error'])
  return import(out)
}
// a Firecrawl stand-in: each call answers with the next reply (or throws it when it is an Error)
function mockFetch(replies) {
  const calls = []
  globalThis.fetch = async (url, init) => {
    calls.push({ url: String(url), body: JSON.parse(init.body) })
    const r = replies.shift()
    if (r instanceof Error) throw r
    return new Response(JSON.stringify(r.json), { status: r.status ?? 200, headers: { 'content-type': 'application/json' } })
  }
  return calls
}
const page = (statusCode, html, extra = {}) => ({ json: { success: true, data: { rawHtml: html, metadata: { statusCode, scrapeId: 's1', creditsUsed: 1, sourceURL: 'https://u.example/p', ...extra } } } })
const BIG = '<html><title>Course</title><body>' + 'Bachelor of Things. '.repeat(40) + '</body></html>'

test('no lane calls Firecrawl itself: the API address appears only in firecrawl.ts', () => {
  for (const f of fs.readdirSync(DIR).filter((x) => x.endsWith('.ts') && x !== 'firecrawl.ts')) {
    expect(fs.readFileSync(`${DIR}/${f}`, 'utf8'), f).not.toContain('api.firecrawl.dev')
  }
  expect(ix).toContain('const fcx = fcClient({ headers: fcHeaders, log: (p) => rpc("svc_fc_call_log", { p })')
  // the shared readers and the paths R7 named go through the client
  expect(ix).toMatch(/const fcMap = async[\s\S]{0,400}fcx\.map\(/)
  expect(ix).toMatch(/const readSch = async[\s\S]{0,1600}fcx\.scrape\(/)
  for (const lane of ['course_read', 'course_read_view', 'course_read_priority', 'entry_render', 'entry_fallback', 'entry_pdf_render', 'provider_description', 'provider_facts_read', 'adapter_builder', 'probe']) {
    expect(ix, lane).toContain(`use_case: "${lane}"`)
  }
  // fc_run keeps the use_case names other reports read (read_page / find_page) and writes its own row after the identity check
  expect(ix).toMatch(/fcx\.scrape\(reqBody, \{ \.\.\.ctx, url: ctx\.url \|\| null \}, \{ timeoutMs, estimate, defer: true \}\)/)
  expect(ix).not.toMatch(/use_case: "(read_page|find_page)"/)
})

test('a page Firecrawl rendered with its own 4xx/5xx status is not accepted; a good page is, and every call is logged', async () => {
  const { fcClient, fcFailed } = await loadFc()
  const logs = []
  const fcx = fcClient({ headers: {}, log: async (p) => { logs.push(p) } })
  mockFetch([page(200, BIG), page(404, BIG), page(503, BIG), page(418, BIG), page(403, BIG), new Error('The signal has been aborted')])
  const ok = await fcx.scrape({ url: 'https://u.example/p', formats: ['rawHtml'] }, { use_case: 'course_read', provider_id: 'p1', course_id: 'c1' }, { timeoutMs: 1000 })
  expect(ok.accepted).toBe(true); expect(ok.html).toBe(BIG); expect(ok.outcome).toBe('read'); expect(ok.page_status).toBe(200); expect(ok.soft_error).toBe(false)
  const nf = await fcx.scrape({ url: 'https://u.example/gone' }, { use_case: 'course_read' }, { timeoutMs: 1000 })
  expect([nf.accepted, nf.html, nf.soft_error, nf.outcome, nf.page_status]).toEqual([false, '', true, 'not_found', 404])
  const se = await fcx.scrape({ url: 'https://u.example/err' }, { use_case: 'entry_render' }, { timeoutMs: 1000 })
  expect([se.accepted, se.html, se.outcome]).toEqual([false, '', 'server_error'])
  const pe = await fcx.scrape({ url: 'https://u.example/tea' }, { use_case: 'entry_render' }, { timeoutMs: 1000 })
  expect([pe.accepted, pe.outcome]).toEqual([false, 'page_error'])
  const bl = await fcx.scrape({ url: 'https://u.example/no' }, { use_case: 'site_check' }, { timeoutMs: 1000 })
  expect([bl.accepted, bl.outcome]).toEqual([false, 'blocked'])
  const to = await fcx.scrape({ url: 'https://u.example/slow' }, { use_case: 'course_read' }, { timeoutMs: 1000 })
  expect(fcFailed(to)).toBe(true); expect(to.outcome).toBe('timeout'); expect(to.rec.credits_used).toBe(0)
  // one row per call, with the lane, the page's own status and the outcome; the address is kept in url, not in request
  expect(logs.map((l) => [l.use_case, l.endpoint, l.page_status, l.outcome])).toEqual([
    ['course_read', 'scrape', 200, 'read'], ['course_read', 'scrape', 404, 'not_found'], ['entry_render', 'scrape', 503, 'server_error'],
    ['entry_render', 'scrape', 418, 'page_error'], ['site_check', 'scrape', 403, 'blocked'], ['course_read', 'scrape', null, 'timeout']])
  expect(logs[0]).toMatchObject({ provider_id: 'p1', course_id: 'c1', url: 'https://u.example/p', http: 200, success: true, scrape_id: 's1', credits_used: 1 })
  expect(logs[0].request).toEqual({ formats: ['rawHtml'] })
})

test('map and search go through the same client; a deferred call is not logged by the client', async () => {
  const { fcClient } = await loadFc()
  const logs = []
  const fcx = fcClient({ headers: {}, log: async (p) => { logs.push(p) } })
  const calls = mockFetch([
    { json: { success: true, links: ['https://u.example/a', { url: 'https://u.example/b', title: 'B' }] } },
    { json: { success: true, data: { web: [{ url: 'https://u.example/c', title: 'C' }] } } },
    { json: { success: true, data: [{ url: 'https://u.example/d' }] } },
    { status: 429, json: { success: false, error: 'rate limited' } },
    page(200, BIG),
  ])
  const m = await fcx.map({ url: 'https://u.example', limit: 10 }, { use_case: 'central_map', provider_id: 'p1' }, { timeoutMs: 1000 })
  expect([m.ok, m.outcome, m.raw.length]).toEqual([true, 'mapped', 2])
  const s2 = await fcx.search({ query: 'x site:u.example', limit: 5 }, { use_case: 'find_site' }, { timeoutMs: 1000 })
  expect([s2.ok, s2.outcome, s2.raw[0].url]).toEqual([true, 'results', 'https://u.example/c'])
  const s1 = await fcx.search({ query: 'y', limit: 5 }, { use_case: 'link_search' }, { timeoutMs: 1000, version: 'v1' })
  expect(s1.raw[0].url).toBe('https://u.example/d')
  const rl = await fcx.search({ query: 'z' }, { use_case: 'provider_facts_search' }, { timeoutMs: 1000, version: 'v1' })
  expect([rl.ok, rl.outcome, rl.rec.credits_used]).toEqual([false, 'rate_limited', 0])
  const df = await fcx.scrape({ url: 'https://u.example/p' }, { use_case: 'read_page', run_id: 'r1', item_id: 'i1' }, { timeoutMs: 1000, defer: true })
  expect(df.log).toMatchObject({ use_case: 'read_page', run_id: 'r1', item_id: 'i1', outcome: 'read' })
  expect(calls.map((c) => c.url)).toEqual(['https://api.firecrawl.dev/v2/map', 'https://api.firecrawl.dev/v2/search', 'https://api.firecrawl.dev/v1/search', 'https://api.firecrawl.dev/v1/search', 'https://api.firecrawl.dev/v2/scrape'])
  expect(logs.map((l) => [l.use_case, l.endpoint, l.outcome])).toEqual([['central_map', 'map', 'mapped'], ['find_site', 'search', 'results'], ['link_search', 'search', 'results'], ['provider_facts_search', 'search', 'rate_limited']])
  expect(logs[1].request).toEqual({ limit: 5, query: 'x site:u.example' })
})

test('the course read, view render and entry renders no longer take a rendered error page as the page', () => {
  // the view render and the course read fallback take the client's accepted page only (sc.html), never pageHtml(d) of the raw reply
  expect(ix).toMatch(/use_case: "course_read_view"[\s\S]{0,200}\n\s*if \(sc\.html\) \{ html = sc\.html; via = "firecrawl"/)
  expect(ix).toMatch(/use_case: "course_read", provider_id[\s\S]{0,200}\n\s*if \(fcFailed\(sc\)\) throw[\s\S]{0,80}\n\s*if \(sc\.html\) \{ html = sc\.html; via = "firecrawl"/)
  for (const lane of ['entry_render', 'entry_fallback', 'entry_pdf_render', 'provider_description', 'provider_facts_read']) {
    expect(ix, lane).toMatch(new RegExp(`use_case: "${lane}"[\\s\\S]{0,900}!?sc\\.accepted`))
  }
  // pageHtml(d) of a raw reply remains only in fc_run (judged by readOutcome before anything is stored) and the probe (stores nothing)
  expect((ix.match(/pageHtml\(d\)/g) || []).length).toBe(2)
})

test('the page status is kept in evidence_artifacts.metadata for course pages, About pages and provider facts', () => {
  expect(mig).toMatch(/^-- Replaces: /m); expect(mig).toMatch(/^-- Retires: /m)
  expect(mig).toContain("pg_temp.edit_once('public.svc_coverage_read_record(uuid,text,integer,text,text,text,text,jsonb)', 'ebbdc4e45af01c473fd5b681d2237011'")
  expect(mig).toContain("jsonb_build_object('page_status', p_http_status)")
  expect(mig).toContain("jsonb_build_object('page_status', (x->'fetch'->>'http')::int)")
  expect(mig).toContain("jsonb_build_object('page_status', p_http)")
  expect(mig).toContain("if v_c <> 1 then raise exception")
  expect(mig).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})
