// Guards: Models & services › AI loads within the admin statement limit (Platform Admin 16 Nov 2026 07:41): the AI read evaluates each service's route state once (a planner fence on the lateral route subquery, md5-guarded edit of the live definition), the last call per service and the page's last changes are read through indexes, and the read carries the prompt registry's parity report
// CF-247 S554. Migration 20261116060000_cf247_ai_tab_timeout. Measured 16 Nov 2026: 5.6 to 20.7 s before, 0.7 to 1.1 s after (rolled-back live run).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations-archive/20261116060000_cf247_ai_tab_timeout.sql', 'utf8')
const code = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('the route state is evaluated once per service; the edit is md5-guarded and exact', () => {
  expect(code).toContain("pg_temp.cf_g2_edit('public.admin_ai_overview_v1()', 'c757ac6eed57a7e7a9945ed8fd7205fe', 'j offset 0) rt'")
  expect(code).toContain("'old', 'cross join lateral (select security.ai_route_v1(r.service_code) j) rt', 'new', 'cross join lateral (select security.ai_route_v1(r.service_code) j offset 0) rt', 'n', 1)")
  expect(code).toContain("raise exception 'post-check: public.admin_ai_overview_v1 was not edited';")
})

test('indexes for the last call per service and the last changes; the prompt registry report on the AI tab', () => {
  expect(code).toContain('create index if not exists ai_invocations_service_at_idx on pipeline.ai_invocations (service_code, at desc, id desc);')
  expect(code).toContain('create index if not exists admin_control_events_area_created_idx on pipeline.admin_control_events (area, created_at desc);')
  expect(M).toContain("''prompt_registry'', security.prompt_registry_parity_v1(),")
  expect(code).not.toMatch(/website_v2_|zoho_edge_|svc_website_settings_v1/)
})
