// Guards: CF-247 v2.15.260 (S25): Platform Admin, 12 Oct 2026 20:00: "Increase the limit to read course pages if found.
// CF-247 v2.15.260 (S25): Platform Admin, 12 Oct 2026 20:00: "Increase the limit to read course pages if found. Keep moving to the next
// wave if a course page is not found. ... the same mechanism ... using Firecrawl in finding course pages and not burned by direct HTTP."
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const sql = fs.readFileSync('supabase/migrations/20261012011700_cf247_course_pages_firecrawl_reads.sql', 'utf8')
const worker = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const outside = s => s.slice(0, s.indexOf('CREATE OR REPLACE FUNCTION')) + s.slice(s.lastIndexOf('$function$;'))

test('worker v0.21.3: a found page is read directly first, Firecrawl only when blocked or needing a browser; basic proxy', () => {
  // v2.15.261 (Platform Admin, 12 Oct 2026 21:21) replaced the v0.21.2 Firecrawl-first read of found pages
  expect(worker).toMatch(/const WORKER = "coverage-sweep-worker-v0\.(?:2[1-9]|[3-9]\d)\.\d+"/)
  expect(worker).toContain('const searchFound = ["title_search", "cricos_search", "firecrawl_search", "serper_search"].includes(it.basis || "");')
  expect(worker).not.toContain('else if (searchFound && await useFc("scrape", it.provider_id, it.url)) {')
  expect(worker).toContain('(!searchCandidate || searchFound) && !(adDirect?.json_found && adDirect.identity) && (!html || thin) && (it.status === "bound" || it.priority === true || searchFound)')
  const scrapes = worker.match(/fetch\("https:\/\/api\.firecrawl\.dev\/v2\/scrape", \{ method: "POST", headers: fcHeaders, body: JSON\.stringify\(\{ [^}]*/g) || []
  // v2.15.269: the proxy is a setting (Toolsets › Firecrawl › Proxy for every Firecrawl read, today "basic")
  for (const s of scrapes) expect(s).toContain('proxy: FC_PROXY')
})

test('11800: basic proxy setting, second reader paused (not removed)', () => {
  const m = fs.readFileSync('supabase/migrations/20261012011800_cf247_firecrawl_fallback_basic_proxy.sql', 'utf8')
  expect(m).toContain("set value = '\"basic\"'::jsonb")
  expect(m).toContain("cron.alter_job(j.jobid, active := false)")
  expect(m).not.toMatch(/cron\.unschedule|^\s*(drop|delete|truncate)\b/im)
})

test('11700: reads more, re-reads the found pages that failed, keeps moving; nothing dropped', () => {
  expect(sql).toContain('pick as (select course_id from due where rk<=20 order by')
  expect(sql).toContain("cron.schedule('coverage-read-2', '30 seconds'")
  expect(sql).toContain("values ('coverage-read-2', 'Course pages'")
  expect(sql).toContain("p.read_status in ('needs_render', 'blocked', 'fetch_failed')")
  expect(sql).toContain("pg.read_at > now() - interval '60 minutes'")
  expect(sql).toContain("where ob.status = 'stopped' and ob.stop_reason = 'too_few_pages'")
  expect(sql).toContain("where ob.status = 'stopped' and ob.stop_reason = 'ai_allowance'")
  expect(sql).toContain("when sqlerrm ilike '%no website is recorded%' then 'no_website'")
  expect(sql).toContain('live % differs from the definition this change replaces')
  expect(sql).toContain('v2.15.260 post-check: % not as intended')
  expect(outside(sql)).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(sql).not.toMatch(/cron\.unschedule/)
})

test.describe('mocked browser', () => {
  test('a stopped row explains that Too few course pages carries on by itself', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#layer-2-discovery?tab=onboarding') // v2.15.300: opens Layer 2/3 › Universities, where each stopped row says what to do
    await expect(page.locator('[data-adapters-workspace]')).toBeVisible()
    const src = fs.readFileSync('src/ProviderOnboarding.jsx', 'utf8')
    expect(src).toContain("ai_allowance:['AI allowance used'")
    expect(src).toContain('carries on by itself once enough of its pages are read')
  })
})
