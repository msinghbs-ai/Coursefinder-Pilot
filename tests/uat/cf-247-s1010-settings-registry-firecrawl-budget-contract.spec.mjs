// Guards: Platform Admin 23 Nov 2026 19:59 AEDT (S1-Build: settings registry for the v1.2 Settings screen and the Firecrawl Tier 1 micro-budget, Standing Authority Charter section 10; G2 settings changed with a reason; G3 frozen).
// s1010: firecrawl.daily_budget_total goes from 0 to 5 (credits a day, inside the US$5.00 a day platform cap) only if it still holds 0, with the
// Platform Admin's reason; every setting has plain-English help for the Settings screen; nothing else changes.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261123210000_cf247_s1010_settings_registry_firecrawl_budget.sql', 'utf8')

test('s1010: the Firecrawl daily budget moves from 0 to 5 credits with the Platform Admin reason, never over a later change', () => {
  expect(MIG).toContain("set value = to_jsonb(5)")
  expect(MIG).toContain("where s.toolset_key = 'firecrawl' and s.key = 'daily_budget_total' and (s.value #>> '{}')::numeric = 0;")
  expect(MIG).toContain('Standing Authority Charter Section 10 — Tier 1 micro-budget cap US$5.00/day')
  expect(MIG).toContain('post-check: the Firecrawl daily budget is outside 0 to 5 credits')
  expect(MIG).toContain('post-check: the Firecrawl daily-budget guard is off')
})

test('s1010: every setting gets plain-English help, filled only where it was empty or short', () => {
  const rows = MIG.match(/^ {2}\('(firecrawl|pipeline)', '[^']+', '/gm) || []
  expect(rows.length).toBe(33)
  expect(MIG).toContain("and length(coalesce(btrim(s.help), '')) < 25;")
  expect(MIG).toContain('post-check: a setting still has no label or plain-English help')
  expect(MIG).not.toMatch(/set\s+(label|min_value|max_value|unit|kind)\s*=/i)
})

test('s1010: G3 guarded before and after, locks and cron unchanged, no job, nothing dropped or deleted', () => {
  expect(MIG).toMatch(/^-- Replaces: /m)
  expect(MIG).toMatch(/^-- Retires: /m)
  expect((MIG.match(/\(v->>'functions'\)::int <> 75|\(v_api->>'functions'\)::int <> 75/g) || []).length).toBe(2)
  expect(MIG).toContain('post-check: manual locks changed')
  expect(MIG).toContain('post-check: the number of active cron jobs changed')
  expect(MIG).not.toMatch(/cron\.(schedule|unschedule|alter_job)|\bdrop (table|function|index|schema|view|trigger)|delete from |truncate /i)
})
