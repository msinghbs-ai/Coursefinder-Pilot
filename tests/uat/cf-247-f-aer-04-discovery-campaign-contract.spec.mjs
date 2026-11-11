// Guards: F-AER.04 AER source discovery campaign: a recorded outcome for every eligible provider, 10,000-credit ceiling inside every other budget (Platform Admin 11 Nov 2026 16:24)
// Production 11 Nov 2026: 1,413 of 1,476 eligible providers had no entry source; discovery asked only the 372 "nothing stored" providers, settled every request 'refused'
// from evidence recorded on 22 Oct, and the entry search spent 0 credits. Migration 20261112040000 runs a campaign over every provider without a source; behaviour is proven
// on isolated PostgreSQL by tests/fixtures/aer-discovery-campaign/run.sh (workflow aer-discovery-campaign-test).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261112040000_cf247_aer_discovery_campaign.sql'
const m = fs.readFileSync(MIG, 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('the two live functions are edited only from their live md5 and the result is checked', () => {
  expect(m).toContain('--   public.svc_fc_spend(numeric,text,uuid,text) 39075b66a1d8ff15246b8c82ffa0c590 -> c9d616fa35a278103121416ce73e0295')
  expect(m).toContain('--   security.aer_source_discover_v1(boolean) f818e6bb2500c5cc63c361970c73d1e3 -> 16e04c3ffe38a38f3b6f23df7bd0e0a1')
  expect(code).toContain("raise exception 'live % differs from the definition this change edits (body md5 %)'")
  expect(code).toContain("raise exception '% after the edit has body md5 %, expected %'")
  expect(m).toMatch(/^-- Replaces: public\.svc_fc_spend, security\.aer_source_discover_v1/m)
  expect(m).toMatch(/^-- Retires: nothing\./m)
})

test('the ceiling is a setting and is checked after every existing budget rule; nothing raises or bypasses a budget', () => {
  expect(code).toMatch(/'aer\.discovery_campaign_credit_cap', 'Entry requirements: discovery campaign credit ceiling',/)
  expect(code).toContain("'number', to_jsonb(10000), 0, 50000, 'credits'")
  const edit = code.slice(code.indexOf("('public.svc_fc_spend(numeric,text,uuid,text)', '39075b66"), code.indexOf("('security.aer_source_discover_v1(boolean)', 'f818e6bb"))
  expect(edit).toContain("elsif p_provider_id is not null and v_grp = 'central' and security.aer_discovery_campaign_over_v1(p_provider_id, p_units) then\n      v_why := 'campaign_cap';")
  expect(code).not.toMatch(/daily_share_central|daily_budget_total|monthly_vendor_units_limit|ondemand_credits_per_day/)
  expect(code).toContain("position('fc_month_refusal_v1' in")
})

test('a request is never settled from evidence recorded before it (the 22 Oct defect)', () => {
  expect(code).toContain("when r.s_req is null and r.evidence ? 'refusal' and r.s_upd >= r.requested_at then 'refused'")
  expect(code).toContain("when (r.state = 'failed' or (r.evidence ? 'error' and r.s_req is null)) and r.s_upd >= r.requested_at then 'failed'")
})

test('every eligible provider without a source is asked until it has an outcome; an outcome row exists for every eligible provider', () => {
  expect(code).toContain('where not exists (select 1 from pipeline.entry_matrix_sources s where s.provider_id = e.provider_id)')
  expect(code).toContain("and p.website ~* '^https?://' and not security.third_party_host_v1(p.website)")
  expect(code).toContain('v_left := v_cand + v_open;')
  expect(code).toContain("update pipeline.aer_discovery_campaigns set state = 'complete'")
  expect(code).toContain("with e as (select e.provider_id, e.country from security.aer_eligible_v1() e)")
  expect(code).toMatch(/comment on table pipeline\.aer_discovery_campaigns is/)
  expect(code).not.toMatch(/cron\.(schedule|alter_job)|^\s*(drop|delete|truncate)\b/im)
})

test('the version is used by no other migration', () => {
  expect(fs.readdirSync('supabase/migrations').filter((f) => f.startsWith('20261112040000_'))).toEqual(['20261112040000_cf247_aer_discovery_campaign.sql'])
})
