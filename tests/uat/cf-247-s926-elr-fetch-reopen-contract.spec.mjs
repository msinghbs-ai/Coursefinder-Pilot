// Guards: CF-247 s926 (session S1-ELR-Unblock-IQ00624, Platform Admin 21 Nov 2026 11:05 AEDT, "Reopen and fetch"): the queued central English pages move to one new on-demand request (claude_session, Firecrawl only, scope central) only when their own request is closed or expired; at most 100 pages; no function, job, table or setting changes
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261121173000_cf247_s926_elr_fetch_reopen.sql', 'utf8')

test('one new request, Firecrawl only, scoped to central, for queued pages whose request is not open', () => {
  expect(MIG).toContain("perform security.on_demand_open_v1('claude_session', v_reason, v_ids, v_est, null, array['firecrawl']);")
  expect(MIG).toContain("perform security.on_demand_scope_v1(v_id, array['central']);")
  expect((MIG.match(/f\.status = 'queued' and \(f\.on_demand_id is null or not exists \(select 1 from pipeline\.on_demand_requests r where r\.id = f\.on_demand_id and r\.state = 'open' and r\.expires_at > now\(\)\)\)/g) || []).length).toBe(2)
  expect(MIG).toContain("raise exception 'post-check: more than 100 pages queued'")
})

test('housekeeping and safety', () => {
  expect(MIG).toMatch(/^-- Replaces: .+\.$/m)
  expect(MIG).toMatch(/^-- Retires: nothing\./m)
  expect(MIG).not.toMatch(/^(drop|delete|truncate)\b/im)
  expect(MIG).not.toMatch(/create or replace function|cron\.schedule\(|create table|platform_toolset_settings|openrouter/i)
  expect((MIG.match(/security\.consumer_api_check_v1\(\)/g) || []).length).toBe(2)
})
