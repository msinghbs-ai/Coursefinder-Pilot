// Guards: AER v3 benchmark round 3 closed (Platform Admin 16 Nov 2026 16:52 step 3): the three run switches go back to 0 with a reason and a control event, the on-demand window is closed, and the change refuses while any round-3 run is still answering; nothing is qualified or switched on
// CF-247 S571. Migration 20261117030000_cf247_aer_v3_bench_r3_close.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const code = fs.readFileSync('supabase/migrations/20261117030000_cf247_aer_v3_bench_r3_close.sql', 'utf8').split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('refuses while a round-3 run answers; switches back to 0 with reason and event; window closed', () => {
  expect(code.indexOf("raise exception 'refused: a round-3 run is still answering; nothing was changed';")).toBeLessThan(code.indexOf('update pipeline.platform_toolset_settings'))
  expect(code).toContain("set value = '0'::jsonb, updated_at = now(),")
  expect(code).toContain("where toolset_key = 'pipeline' and key in ('reading.aer_v2_long_page_sections_on', 'ai_eval.offline_runs_on', 'ai_eval.aer_v3_runs_on')")
  expect(code).toMatch(/insert into pipeline\.admin_control_events\(area, action, target, detail, actor\)\s+select 'settings', 'migration', u\.key/)
  expect(code).toContain("select security.on_demand_close_v1(id) from pipeline.on_demand_requests")
})

test('nothing qualified or switched on', () => {
  expect(code).not.toMatch(/update pipeline\.ai_route_qualifications|update pipeline\.ai_service_routes/)
  expect(code).not.toMatch(/'aer\.v2_shadow_on'[^)]*'1'/)
  expect(code).toContain("raise exception 'post-check: the entry reading routes stay off';")
})
