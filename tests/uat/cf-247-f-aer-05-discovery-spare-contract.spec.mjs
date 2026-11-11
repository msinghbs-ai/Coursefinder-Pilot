// Guards: F-AER.04 discovery campaign spare capacity (Platform Admin decision D2, 11 Nov 2026): up to 1,000 credits a day of verified unused capacity, inside the daily total and above the vendor floor
// The campaign may take a central spend past the central share only from spare room: the day total less automatic credits billed, less every other group's projected need and the
// unused central share, at most aer.discovery_spare_daily_max (never above 1,000) and above the vendor floor. The ceiling and every other rule still apply. Behaviour is proven on
// isolated PostgreSQL by tests/fixtures/aer-discovery-spare/run.sh.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261112103900_cf247_aer_discovery_spare.sql'
const m = fs.readFileSync(MIG, 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('the daily spare maximum is a setting that never passes 1,000; 0 switches it off', () => {
  expect(code).toContain("'number', to_jsonb(1000), 0, 1000, 'credits', 1507")
  expect(code).toContain("v_max := least(security.pipeline_num_v1('aer.discovery_spare_daily_max', 0), 1000);")
  expect(code).toContain("if v_max <= 0 then return jsonb_build_object('room', 0")
})

test('spare room is verified: day total, other groups kept, central unused, vendor floor; none without a fresh balance', () => {
  expect(code).toContain('v_room := greatest(0, floor(least(v_max - v_taken, v_total - v_auto - v_reserved - v_central_left, v_vendor)));')
  expect(code).toContain("return jsonb_build_object('room', 0, 'why', 'no vendor balance read in the last 2 hours'")
  expect(code).toContain('v_need := least(greatest(0, g.share - v_used), ceil(greatest(v_recent / v_win * v_left_h, v_prev) * (1 + v_margin / 100)));')
})

test('the spend rule: only for an open campaign request the share would refuse; the ceiling and later rules still apply; each spare spend recorded', () => {
  expect(code).toContain("v_spare := v_grp = 'central' and p_provider_id is not null and security.fc_budget_left_v1(p_purpose) < p_units")
  expect(code).toContain('if security.fc_budget_left_v1(p_purpose) < p_units and not v_spare then')
  expect(code).toContain('insert into pipeline.aer_discovery_spare_spends(campaign_id, provider_id, purpose, units, room)')
  expect(code).toContain("raise exception 'post-check: the campaign ceiling was lost'")
})

test('the credit count is the same total without the full scan; metrics on the discovery read; md5-guarded; one file per version', () => {
  expect(code).toContain('with f as (select q.provider_id, min(q.requested_at) t from pipeline.aer_source_discover_requests q where q.campaign_id = p_campaign group by 1)')
  expect(code).toContain("'metrics', security.aer_discovery_metrics_v1(),")
  for (const k of ['providers_attempted', 'new_sources', 'usable_sources', 'not_found', 'cost_per_usable_source', 'spare_credits_today']) expect(code).toContain(`'${k}'`)
  expect(m).toContain('--   public.svc_fc_spend(numeric,text,uuid,text) c9d616fa35a278103121416ce73e0295 -> 07972f712be389e84d49f33a0852f534')
  expect(m).toMatch(/^-- Replaces: security\.aer_discovery_campaign_used_v1/m)
  expect(fs.readdirSync('supabase/migrations').filter((f) => f.startsWith('20261112103900_'))).toEqual(['20261112103900_cf247_aer_discovery_spare.sql'])
})
