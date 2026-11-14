// Guards: Platform Admin 12 Nov 2026 21:07 and 13 Nov 2026 15:31 (operating model 3.3.2; Firecrawl crawling for evidence first): course page searches of an open on-demand request are picked and spent without the scheduled share, daily cap, focus or target-list cut; scheduled searches keep them
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261113341500_cf247_on_demand_course_search.sql', 'utf8')
const W = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')

test('the picker takes on-demand providers first and keeps the scheduled limits for everyone else', () => {
  expect(M).toContain("'00f7add9839d659f7dfc7efe6bd82216'")
  expect(M).toContain("security.fc_purpose_group_v1('course_link_search') = any (r.purpose_groups)")
  expect(M).toContain('if v_room > 0 then v_sched := least(v_sched, v_room); end if;')
  expect(M).toContain('else not (s.provider_id = any (v_od)) and (v_room > 0 or (v_person and security.link_search_person_task_v1(s.provider_id, s.course_id))) end)')
  expect(M).toContain('and (v_pass = 1 or pv.focus or s.requested_at is not null)')
  expect(M).toContain('limit v_take')
  // the policies are not touched: stop gate, directory sites, skip list
  expect(M).not.toMatch(/search_stop_gate_v1|third_party_host_v1|search\.skip_providers'\]/)
  expect(M).not.toMatch(/^\s*(delete|drop|truncate)\b/im)
})

test('the worker asks the database before a target-list refusal', () => {
  expect(M).toContain('create or replace function public.svc_fc_on_demand_covers_v1(p_provider uuid, p_purpose text)')
  expect(W).toContain('!(await onDemandCovers(providerId, purpose))')
  expect(W).toContain('rpc("svc_fc_on_demand_covers_v1", { p_provider: providerId, p_purpose: purpose })')
  expect(W).toContain('// was v0.84.0 // v0.84.0 (13 Nov 2026, CF-247 operating model 3.3.2')  // v0.87.0 (Lean AI Input Phase 1) keeps this release's behaviour
})
