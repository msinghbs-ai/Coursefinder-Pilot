// CF-247 v2.15.260 (S25): Platform Admin, 12 Oct 2026 20:00: "Increase the limit to read course pages if found. Keep moving to the next
// wave if a course page is not found. ... the same mechanism ... using Firecrawl in finding course pages and not burned by direct HTTP."
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const sql = fs.readFileSync('supabase/migrations/20261012011700_cf247_course_pages_firecrawl_reads.sql', 'utf8')
const worker = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const outside = s => s.slice(0, s.indexOf('CREATE OR REPLACE FUNCTION')) + s.slice(s.lastIndexOf('$function$;'))

test('worker v0.21.2: a page the search found is read through Firecrawl first (rendered), direct only when Firecrawl cannot be used', () => {
  expect(worker).toContain('const WORKER = "coverage-sweep-worker-v0.21.2"')
  expect(worker).toContain('const searchFound = ["title_search", "cricos_search", "firecrawl_search", "serper_search"].includes(it.basis || "");')
  const i = worker.indexOf('else if (searchFound && await useFc("scrape", it.provider_id, it.url)) {')
  expect(i).toBeGreaterThan(0)
  // the Firecrawl branch comes before the direct request
  expect(i).toBeLessThan(worker.indexOf('const r = await fetch(u, { headers: { "user-agent": UA, accept: "text/html,application/xhtml+xml" }, redirect: "follow", signal: AbortSignal.timeout(20000) });\n              http = r.status; finalUrl = r.url || it.url;'))
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
    await page.goto('/#layer-2-discovery?tab=onboarding')
    await expect(page.locator('[data-provider-onboarding]')).toBeVisible()
    const src = fs.readFileSync('src/ProviderOnboarding.jsx', 'utf8')
    expect(src).toContain("ai_allowance:['AI allowance used'")
    expect(src).toContain('carries on by itself once enough of its pages are read')
  })
})
