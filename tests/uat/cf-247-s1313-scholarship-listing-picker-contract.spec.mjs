// Guards: SS-Programme-Control 27 Nov 2026 16:07 AEDT (P0 Scholarship Production Picker Recovery, decision D12; SCH-FU-10, coursefinder-admin #1305): held providers keep their free direct listing reads; eligibility, visibility and every paid-scrape control stay enforced
// CF-247 s1313. supabase/migrations/20261130180000_cf247_s1313_scholarship_listing_picker_free_first.sql
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261130180000_cf247_s1313_scholarship_listing_picker_free_first.sql', 'utf8')
const worker = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')

test('the picker uses the eligibility-only hold in place of fc_sch_held_v1; visibility stays', () => {
  expect(sql).toContain("a text := 'and not security.fc_sch_held_v1(d.provider_id, true)),';")
  expect(sql).toContain("'and not security.fc_sch_listing_held_v1(d.provider_id)),")
  expect(sql).toContain("dc3b688512a12d5bbf3ed16eecdbd796")
  expect(sql).not.toMatch(/provider_hidden_v1[^\n]*replace/)
})

test('the listing hold is rule (b) of fc_sch_held_v1 word for word: budget switch, eligibility, Canadian opening', () => {
  expect(sql).toContain("s.toolset_key = 'firecrawl' and s.key = 'daily_budget_on'")
  expect(sql).toContain('return not security.fc_sch_eligible_v1(p_provider_id)')
  expect(sql).toContain("s.key = 'scholarship.listing_open_ca'")
  expect(sql).toContain("if md5(pg_get_functiondef('security.fc_sch_held_v1(uuid,boolean)'::regprocedure)) <> '7c74b911a6b30e148e28bebc1ea29765'")
  expect(sql).toContain('held by the listing hold but not by fc_sch_held_v1')
})

test('paid scrapes stay gated: the worker reads direct first and asks svc_fc_spend, which enforces the per-university cap', () => {
  expect(sql).toContain("position('scholarship_cap_per_uni' in where n.nspname = 'public' and p.proname = 'svc_fc_spend')) = 0")
  expect(worker).toContain('if (!(await useFc("sch_scrape", providerId, url, true))) return none("waiting_scraper");')
  expect(worker).toContain('if (!(await rpc("svc_fc_spend", { p_units: units, p_purpose: purpose, p_provider_id: providerId, p_url: url }))) return { ok: false, why: "credits_refused" };')
})

test('nothing else changes: no cap, setting, job or lock; consumer API checked; nothing dropped', () => {
  expect(sql).not.toMatch(/insert into pipeline\.platform_toolset_settings|update pipeline\.platform_toolset_settings|cron\.(schedule|alter_job)/)
  expect(sql).not.toMatch(/\bdrop\s+(table|function|view)\b|\bdelete\s+from\b/i)
  expect(sql).toContain("(v->>'functions')::int <> 75 or (v->>'relations')::int <> 48")
  expect(sql).toMatch(/-- Replaces: public\.svc_scholarship_listing_next/)
  expect(sql).toMatch(/-- Retires: nothing\./)
})
