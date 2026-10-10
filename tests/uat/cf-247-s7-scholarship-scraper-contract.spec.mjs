// CF-247 v2.15.242 (S7): scholarship pages and listing pages are read through the scraper first (Platform Admin, 11 Oct 2026:
// "Always use scraper for Scholarships ... This can be controlled via ui"). Worker coverage-sweep v0.17.40; migration 20261011008200.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

test('worker reads scholarship and listing pages through the scraper first, direct as fallback', () => {
  const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(w).toContain('const WORKER = "coverage-sweep-worker-v0.17.41"')
  expect(w).toContain('const schScraper = !!schBudget && Number(schBudget.scraper ?? 1) >= 1;')
  expect(w).toContain('await useFc("sch_scrape", providerId, url, true)') // any provider, within the scholarship cap
  expect(w).toContain('formats: ["rawHtml"], onlyMainContent: false, waitFor: 1500')
  expect(w).toContain('const pg = await readDirect(url);') // fallback
  expect(w).toContain('const pg = await readSch(r.url, r.provider_id);') // listing pages
  expect(w).toContain('const pg = await readSch(it.url, it.provider_id);') // scholarship pages
  expect(w).toContain('if (!robotsAllows(await robotsFor(u), u.pathname + u.search)) return { status: "robots_disallowed"')
})

test('setting, budget and immediate re-read; md5-guarded; nothing dropped', () => {
  const sql = fs.readFileSync('supabase/migrations/20261011008200_cf247_scholarship_scraper_first.sql', 'utf8')
  expect(sql).toContain("values ('read_via_scraper', 2, 'Read scholarship pages through the scraper',")
  expect(sql).toContain("'scraper', coalesce((select s.value from pipeline.scholarship_layer_settings s where s.key = 'read_via_scraper'), 1)")
  expect(sql).toContain("update pipeline.scholarship_layer_settings set value = 12000")
  expect(sql).toContain('update pipeline.scholarship_pages p set next_read_at = now(), attempts = 0, leased_until = null')
  expect(sql).toContain('"public.svc_scholarship_fc_budget()": "2faa5eac7d0703f160d7931ca42eacf8"')
  expect(sql).toContain('"public.svc_scholarship_fc_budget()": "5a58bfd5a6f3001fdb9e1387ed046650"')
  expect(sql).not.toMatch(/^(drop|delete|truncate)\b/im)
})

test('on/off settings are a switch in the UI', () => {
  const ui = fs.readFileSync('src/ScholarshipLayer.jsx', 'utf8')
  expect(ui).toContain("s.unit==='on/off'")
  expect(ui).toContain('role="switch"')
  expect(ui).toContain("sch_scrape:'Reading scholarship and listing pages'")
  expect(fs.readFileSync('src/mature.css', 'utf8')).toContain('.sl-switch input:checked{background:var(--cf-indigo-600)}')
})
