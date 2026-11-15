// Guards: Phase 2 wave B of the UI/UX and settings simplification (Platform Admin 16 Nov 2026 05:23, values written into code become settings): the stage timers of provider onboarding become nine settings with today's values (section Onboarding), every interval of the function is accounted for, the edit is md5-guarded against the live definition and must match an exact number of times, and the one technical value left is marked fixed
// CF-247 S551. Migration 20261116030000_cf247_g2_promotion_wave_b. G2 in general is guarded by s32, G3 by s57 and housekeeping by s42.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261116030000_cf247_g2_promotion_wave_b.sql', 'utf8')
const code = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const SETTINGS = [['onboarding.job_done_wait_minutes', 90], ['onboarding.read_quiet_minutes', 60], ['onboarding.proposal_wait_minutes', 30],
  ['onboarding.apply_max_minutes', 90], ['onboarding.apply_quiet_minutes', 10], ['onboarding.apply_activity_minutes', 5], ['onboarding.enrich_wait_minutes', 20],
  ['onboarding.enrich_quiet_minutes', 10], ['onboarding.scholarship_settle_minutes', 15]]

test('nine settings with today’s values, in minutes, section Onboarding, read by the onboarding step; none overwritten', () => {
  for (const [k, v] of SETTINGS) {
    expect(code).toMatch(new RegExp(`\\('pipeline', '${k.replace('.', '\\.')}', '[^']+',\\s+'[^']+',\\s+'number', to_jsonb\\(${v}\\), \\d+, \\d+, 'minutes', \\d+, '[^']+', 'Onboarding', 'security\\.provider_onboarding_step_v1 \\(job provider-onboarding\\)', 'automatic'\\)`))
    expect(code).toContain(`security.pipeline_num_v1(''${k}'', ${v})::int`)
  }
  expect(code).toContain('on conflict (toolset_key, key) do nothing;')
})

test('one md5-guarded edit of the live definition; every interval accounted for; the clock tolerance marked fixed', () => {
  expect(code).toContain("pg_temp.cf_g2_edit('security.provider_onboarding_step_v1(uuid)', '8597740642ce2470f793be575793e680', 'onboarding.apply_max_minutes'")
  expect(code).toContain("if md5(v_def) <> p_md5 then raise exception")
  expect(code).toContain("if v_n <> (e->>'n')::int then raise exception")
  expect(code).toContain("'old', 'v_age > interval ''30 minutes''', 'new'")
  expect(code).toContain("'n', 3)")
  expect(code).toContain("'kind', 'mark', 'old', '- interval ''1 minute''', 'new', 'clock tolerance: scholarships created just before the step started', 'n', 1)")
  expect(code).toContain("raise exception 'post-check: an interval other than the marked clock tolerance is still written into security.provider_onboarding_step_v1';")
  expect(code).not.toMatch(/website_v2_|website_edge_|zoho_edge_|svc_website_settings_v1/)
})
