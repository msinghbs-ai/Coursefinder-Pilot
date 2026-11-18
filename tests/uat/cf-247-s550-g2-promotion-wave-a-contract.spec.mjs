// Guards: Phase 2 wave A of the UI/UX and settings simplification (Platform Admin 16 Nov 2026 05:23, values written into code become settings): operational values written into eleven live functions become settings with today's values (label, range, unit, section, used_by), technical values in the same functions are marked "-- fixed: <why>", every edit is md5-guarded against the live definition and must match an exact number of times, and the consumer API, AER v1 and onboarding stage timers are not touched
// CF-247 S550. Migration 20261116020000_cf247_g2_promotion_wave_a. G2 in general is guarded by s32, G3 by s57 and housekeeping by s42.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations-archive/20261116020000_cf247_g2_promotion_wave_a.sql', 'utf8')
const code = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const SETTINGS = [['layer1.reverify_after_days', 30, 'days'], ['scholarship.scheduler_retry_minutes', 60, 'minutes'], ['coverage.link_search_retry_days', 7, 'days'],
  ['data_quality.stale_after_days', 180, 'days'], ['retention.progress_snapshots_days', 90, 'days'], ['retention.evidence_min_age_days', 7, 'days'],
  ['zero_yield.redetect_hours', 23, 'hours'], ['english_policy.replan_minutes', 30, 'minutes'], ['retention.audit_columns_per_tick', 3, 'columns']]

test('nine new settings carry today’s value with a label, range, unit, section and used_by; none is overwritten', () => {
  for (const [k, v, unit] of SETTINGS) expect(code).toMatch(new RegExp(`\\('pipeline', '${k.replace('.', '\\.')}', '[^']+',[\\s\\S]*?'number', to_jsonb\\(${v}\\), \\d+, \\d+, '${unit}', \\d+, '[^']+', '[^']+', 'security\\.`))
  expect(code).toContain('on conflict (toolset_key, key) do nothing;')
  expect(code).toContain("raise exception 'post-check: the 9 settings are not all present';")
})

test('each function is edited only from its known live definition, each edit an exact number of times, and nothing else changes', () => {
  const fn = code.slice(code.indexOf('create or replace function pg_temp.cf_g2_edit'), code.indexOf('end $edit$;'))
  expect(fn).toContain("if md5(v_def) <> p_md5 then raise exception")
  expect(fn).toContain("if v_n <> (e->>'n')::int then raise exception")
  expect(fn).toContain("if position(p_done in v_def) > 0 then return 'already'; end if;")
  for (const md5 of ['92818b53fa475a437dbf84cae67ec766', '0741db9c35ef91eba6caa55b04fde869', '6af37c60bfa0f2a41d4ea14e7cdc9d0c', 'cc69c46ac00b76f93be4846c721ca4df',
    '85b6c4d92bb1575e095f604e89860c30', '5587c9b82d6adde716d229843d66f7a4', 'd2b01fca6972a405e72603ff12ed1b9e', '2f877c1898de889e44b1983f582f5599',
    'd7424522e9c0dcc97a62ad0d4a662268', '130169b8cef0c8683b29eef86d0a8bb8', '4f583aa618658a66c70acd56cbbd014c']) expect(code).toContain(`'${md5}'`)
  // every promoted value is read with today's value as its default
  for (const [k, v] of SETTINGS) expect(code).toContain(`security.pipeline_num_v1(''${k}'', ${v})::int`)
  expect(code).toContain("security.pipeline_num_v1(''reread.scholarship_page_days'', 90)::int")
  expect(code).toContain("raise exception 'post-check: a value is still written into %', v_bad;")
})

test('technical values stay in code, each line marked fixed with its reason', () => {
  expect(code).toContain("'\\& -- fixed: ' || (e->>'new')")
  for (const why of ['rows seen by this run (its own hour), not an operating window', 'page size of the area list (display)',
    'the hour that zero_yield.providers_per_run counts', 'hand-over lease: work not confirmed within 10 minutes is taken back']) expect(code).toContain(`'${why}'`)
})

test('not touched: consumer API, AER v1 functions and the onboarding stage timers', () => {
  expect(code).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|zoho_reference_bundle/)
  expect(code).not.toMatch(/security\.aer_[a-z_]+v1\(/)
  expect(code).not.toContain('provider_onboarding_step_v1(')
})
