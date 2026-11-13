// Guards: Platform Admin 12 Nov 2026 21:07 (operating model 3.3.2: only on-demand work is waived; scheduled work keeps every limit): a request waives limits only for the purpose groups it covers
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261113321500_cf247_on_demand_purpose_scope.sql', 'utf8')

test('the spend uses the request for its provider and purpose group; null groups keep the old behaviour', () => {
  expect(M).toContain("'521d7e98ef897e92eda1bb6fd8e46af8'")
  expect(M).toContain('security.on_demand_request_for_v2(p_provider_id, p_purpose)')
  expect(M).toContain('and (r.purpose_groups is null or security.fc_purpose_group_v1(p_purpose) = any (r.purpose_groups))')
  expect(M).toContain('alter table pipeline.on_demand_requests add column if not exists purpose_groups text[]')
  expect(M).not.toMatch(/^\s*(delete|drop|truncate)\b/im)
})
