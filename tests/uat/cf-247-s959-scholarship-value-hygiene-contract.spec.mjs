// Guards: CF-247 s959 (Platform Admin 22 Nov 2026 01:20 AEDT, Lane 1 item 3: REQ-64, REQ-71, REQ-72; REQ-100 follow-up): a range note "X% to Y%" holds Y marked up to; "Up to" notes hold their stated figure; the last text-only values are read from their notes ($0); no passed closing date reads open; locked values untouched; the study levels come in one page from the browser too
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261122080000_cf247_s959_scholarship_value_hygiene.sql', 'utf8')

test('the rule: upper figure, marked up to; text-only from the note; locks respected; every change logged', () => {
  expect(MIG).toContain("regexp_match(s.award_value_text, '^(\\d+(?:\\.\\d+)?)%\\s+to\\s+(\\d+(?:\\.\\d+)?)%\\s+of\\s') rng")
  expect(MIG).toContain('case when rng is not null then rng[2]::numeric')
  expect(MIG).toContain('award_value_is_maximum = true,')
  expect(MIG).toContain("k.field in ('award_value', 'award_value_type', 'award_amount', 'award_percentage')")
  expect(MIG).toContain('insert into pipeline.scholarship_sweep_changes (scholarship_id, field, before_value, after_value, evidence_id)')
  expect(MIG).toContain("'post-check: % range or up-to values still disagree with their note'")
  expect(MIG).toContain("'post-check (REQ-72): % published scholarships with a passed closing date are not closed'")
  expect(MIG).toContain("'post-check: the manual locks changed'")
})

test('values only: nothing published, unpublished, deleted, fetched or scheduled', () => {
  const body = MIG.split('\n').filter(l => !l.trimStart().startsWith('--')).join('\n')
  expect(body).not.toMatch(/publication_status\s*=\s*'(published|unpublished|hidden)'\s*,/i)
  expect(body).not.toMatch(/\bdrop\s+(table|function|view)\b|\bdelete\s+from\b|cron\.schedule\(|on_demand_open_v1|net\.http_post/i)
  expect(MIG).toMatch(/^-- Retires: nothing\./m)
})

test('REQ-100 follow-up: the browser asks for up to 100 study levels in one page', () => {
  expect(fs.readFileSync('src/lib/supabase.js', 'utf8')).toContain("limit: Math.min(Math.max(Number(limit)||10,1),kind==='level'?100:10),")
})
