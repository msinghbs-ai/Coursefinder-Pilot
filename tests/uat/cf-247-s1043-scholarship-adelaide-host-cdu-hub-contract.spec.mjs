// Guards: CF-247 s1043 (Platform Admin 24 Nov 2026 14:53, S1-Scholarship-Claude): Adelaide University's scholarship host adelaide.edu.au is allowed through the discovery provider's allowed_hosts (no function changed, G3 untouched),
// and Charles Darwin's international scholarship hubs are registered and read now so the s1037 splitter reads the awards. Data only; idempotent; no lock, cron or consumer API change.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261124173000_cf247_s1043_scholarship_adelaide_host_cdu_hub.sql', 'utf8')

test.describe('s1043 migration contract', () => {
  test('widens the Adelaide host through allowed_hosts only, idempotently', () => {
    expect(sql).toMatch(/update pipeline\.scholarship_discovery_providers set allowed_hosts/)
    expect(sql).toMatch(/not \('adelaide\.edu\.au' = any/)
    expect(sql).not.toMatch(/create or replace function/i)
    expect(sql).toMatch(/security\.url_on_provider_sites\('https:\/\/adelaide\.edu\.au\/study\/scholarships\/', v_ade\)/)
  })
  test('registers the Charles Darwin international hubs behind the host guard and reads them now', () => {
    expect(sql).toContain('https://www.cdu.edu.au/international/scholarships')
    expect(sql).toContain('https://www.cdu.edu.au/international/how-apply/scholarships')
    expect(sql).toMatch(/url_on_provider_sites\(v_url, v_cdu\)/)
    expect(sql).toMatch(/'manual', true, 'waiting', null/)
  })
  test('keeps the guardrails: housekeeping lines, G3, locks and cron checked, nothing dropped or deleted', () => {
    expect(sql).toMatch(/^-- Replaces: nothing$/m)
    expect(sql).toMatch(/^-- Retires: nothing$/m)
    expect(sql).toMatch(/functions'\)::int <> 75 or \(v->>'relations'\)::int <> 48/)
    expect(sql).toMatch(/manual locks changed/)
    expect(sql).toMatch(/active cron jobs changed/)
    expect(sql).not.toMatch(/\b(drop (table|function|index|column|schema)|delete from|truncate)\b/i)
  })
})
