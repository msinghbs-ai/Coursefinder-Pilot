// Guards: Lane 2 (S2-Data-Destination-Continuous), Platform Admin 22 Nov 2026 00:11 AEDT, IR-008 approved (RM1I, s965): Migration Tasmania's
// Tasmania-wide weekly living costs as draft figures at $0, attributed and labelled Tasmania-wide, for the Platform Admin's terms sign-off;
// localities chosen from the database (Tasmanian SUAs), never a list; nothing approved here.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261122100000_cf247_s965_rm1i_tasmania_living_costs.sql', 'utf8')
const code = MIG.split('\n').filter((l) => !l.trimStart().startsWith('--')).join('\n')
const figures = [...code.matchAll(/\('([a-z_]+_week(?:_low|_high)?)',\s+(\d+), '([^']+)'\)/g)].map((m) => ({ key: m[1], v: Number(m[2]), quote: m[3] }))

test('s965: fifteen weekly figures, each with its verbatim line, every range as low and high', () => {
  expect(figures).toHaveLength(15)
  for (const f of figures) expect(f.quote, f.key).toContain(`$${f.v}`)
  const lows = figures.filter((f) => f.key.endsWith('_low'))
  for (const l of lows) {
    const h = figures.find((f) => f.key === l.key.replace(/_low$/, '_high'))
    expect(h, l.key).toBeTruthy(); expect(h.v).toBeGreaterThan(l.v); expect(h.quote).toBe(l.quote)
  }
  expect(figures.find((f) => f.key === 'rent_whole_house_week').v).toBe(550)
})

test('s965: draft, AUD per week, Tasmania-wide attribution to Migration Tasmania; the approval stays with the Platform Admin', () => {
  expect(code).toContain("'living_cost', f.metric_key, f.v, 'AUD per week', 'AUD',")
  expect(code).toContain("'draft', 'Draft (s965, 22 Nov 2026): read verbatim from the page: \"' || f.quote || '\"'")
  expect(code).toContain('Living costs: Migration Tasmania, Live in Tasmania (migration.tas.gov.au), Tasmanian Government. Approximate weekly costs for Tasmania as a whole (Tasmania-wide)')
  expect(code).not.toMatch(/'approved'|figures_bulk_approve\(|'published'/)
})

test('s965: localities come from the database (Tasmanian SUAs), not a list of names', () => {
  expect(code).toContain("where l.country_code = 'AU' and l.geography_type = 'SUA' and l.geography_code like '6%'")
  expect(code).not.toMatch(/'(Hobart|Launceston|Devonport|Burnie)/)
  expect(code).toContain("if v_rows <> 15 * v_loc then raise exception")
})

test('s965: the source is in the Layer 1 Register, not auto-ingested; $0 (no Firecrawl, no model call)', () => {
  expect(code).toContain("'https://www.migration.tas.gov.au/live_and_work/live_in_tasmania', 'Migration Tasmania: Live in Tasmania (weekly living costs)'")
  expect(code).toContain('30, 30, 20, 60, false, null,')
  expect(code).not.toMatch(/firecrawl|openrouter|svc_pilot_submit_nonce|net\.http/i)
  expect(code).not.toMatch(/\b(drop|delete|truncate)\b/i)
})
