// Guards: Platform Admin 12 Nov 2026 21:07 (operating model 3.3.2): "toolset limit should be waved when doing on demand, only scheduled tasks should obey toolset limits ... it should display estimated toolset value and then after finish display actual used or credit left on toolset"
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261113153100_cf247_on_demand_waives_toolset_limits.sql', 'utf8')

test('an open on-demand request waives the Firecrawl toolset limits for its providers only; the directory rule and the monthly plan still apply', () => {
  expect(M).toContain("'41fb1ac8c71c74df25b913b85dcf3baa'")
  expect(M).toContain('v_req uuid := case when p_provider_id is null then null else security.on_demand_request_for_v1(p_provider_id) end;')
  // the waiver branch comes after the directory-site rule and the monthly plan limit, which are not edited
  const spend = M.slice(M.indexOf("pg_temp.edit_n('public.svc_fc_spend"), M.indexOf("pg_temp.edit_n('security.fc_budget_left_v1"))
  expect(spend).toMatch(/elsif v_req is not null then\n\s+v_why := null;[^\n]*\n\s+elsif v_od is not null then/)
  expect(spend).not.toMatch(/month_limit|directory_site/)
  expect(M).toMatch(/r\.state = 'open' and r\.expires_at > now\(\) and p_provider = any \(r\.provider_ids\)/)
  // the allowance no longer holds a Run now plan; spends of a request are outside the scheduled shares
  expect(spend).toContain("null;  -- 12 Nov 2026 (Platform Admin 21:07): on demand is not held by toolset limits")
  expect(M).toContain('and x.on_demand_run is null and x.on_demand_request is null;')
  expect(M).toContain('v_od, v_req from')
})

test('a request records its estimate and the credit left before, and reports the actual use and the credit left after', () => {
  expect(M).toContain('create table if not exists pipeline.on_demand_requests')
  expect(M).toContain('comment on table pipeline.on_demand_requests')
  expect(M).toMatch(/return jsonb_build_object\('id', v_id, 'estimate', [^\n]*'credit_left_before', v_before/)
  expect(M).toMatch(/'firecrawl_units', \(select coalesce\(sum\(u\.units\), 0\) from pipeline\.coverage_vendor_usage u where u\.on_demand_request = r\.id\)/)
  expect(M).toContain("'credit_left_now', security.on_demand_credit_left_v1()")
  expect(M).toMatch(/'firecrawl_left_on_plan', security\.fc_vendor_estimate_v1\(\)/)
  expect(M).toMatch(/'ondemand\.window_hours'[\s\S]*?'number', to_jsonb\(6\), 1, 48, 'hours'/)
  // Run now is checked against the account, not the allowance
  expect(M).toContain("'dab650c5adefd9b0b9c006b0c5db4d5d'")
  expect(M).toContain('more than the Firecrawl credit left on the plan')
  expect(M).not.toMatch(/^\s*(delete|drop|truncate)\b/im)
  // the Claude-session procedure is a working rule
  expect(fs.readFileSync('CLAUDE.md', 'utf8')).toMatch(/security\.on_demand_open_v1[\s\S]*security\.on_demand_close_v1/)
})
