// Guards: StudySearch Portal lane (Platform Admin 25 Nov 2026, S1-API-Frontend-Delivery): portal read functions are additive, role-checked, published-only and carry no operational number
// CF-247 S1143. The central rules stay with their own specs (G2 s32, G3 s57, housekeeping s42); this file checks what only this migration promises.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { migrationNames, migrationPath } from './support/migration-files.mjs'

const name = migrationNames().find((f) => f.includes('s1143_portal_read_functions'))
const sql = fs.readFileSync(migrationPath(name), 'utf8')
const body = (fn) => { const i = sql.indexOf(`create or replace function ${fn}`); return sql.slice(i, sql.indexOf('$function$;', sql.indexOf('as $function$', i)) + 11) }

test('the migration is additive: new objects only, guarded against the frozen consumer API, nothing dropped', () => {
  expect(name).toMatch(/^20261126230000_/)
  expect(sql).toMatch(/consumer_api_check_v1\(\)/)
  expect(sql).toContain("(v->>'functions')::int <> 75")
  expect(sql).toContain("(v_api->>'relations')::int <> 48")
  expect(sql).not.toMatch(/^\s*(drop|truncate)\b/im)
  for (const f of sql.match(/create or replace function [a-z_.]+/g)) expect(f, 'new portal functions only').toMatch(/(public|security)\.portal_/)
  expect(sql).not.toMatch(/website_v2_|website_edge_|zoho_edge_|api\./)
  expect(sql).toContain("comment on table portal.saved_courses is '")
})

test('every portal function checks the role rank itself: Viewer 1 reads, Counsellor 2 saves', () => {
  for (const fn of ['public.portal_settings_v1', 'public.portal_lookups_v1', 'public.portal_providers_v1', 'public.portal_scholarships_v1']) expect(body(fn), fn).toContain('security.portal_rank_v1(1)')
  for (const fn of ['public.portal_saved_list_v1', 'public.portal_saved_set_v1']) expect(body(fn), fn).toContain('security.portal_rank_v1(2)')
  expect(body('security.portal_rank_v1')).toMatch(/auth\.uid\(\) is null/)
  expect(body('security.portal_rank_v1')).toContain('security.current_role_rank()')
  const heads = sql.split('create or replace function ').slice(1).map((h) => h.slice(0, h.indexOf('as $function$')))
  expect(heads.length).toBe(9)
  for (const h of heads) expect(h, h.slice(0, 50)).toMatch(/set search_path = ''/)
  expect(sql).toMatch(/revoke all on function public\.portal_settings_v1\(\)[\s\S]*from public, anon;/)
  expect(sql).toMatch(/grant execute on function public\.portal_settings_v1\(\)[\s\S]*to authenticated;/)
})

test('providers and scholarships are published-only, as the website API reads them, and blocked records stay out', () => {
  for (const fn of ['public.portal_providers_v1', 'public.portal_scholarships_v1']) {
    const b = body(fn)
    expect(b, fn).toContain("lifecycle_status = 'active'")
    expect(b, fn).toContain("publication_status = 'published'")
    expect(b, fn).toContain('security.layer4_search_blocked_providers')
  }
  expect(body('public.portal_scholarships_v1')).toContain('security.layer4_search_blocked_scholarships')
  expect(body('public.portal_providers_v1')).toContain('pipeline.provider_representation')
  expect(body('public.portal_providers_v1')).toContain("'not_recorded'")
})

test('no operational number is written into a function: sizes and limits are settings under toolset portal (G2)', () => {
  // each setting row: ('portal', key, label, help, 'number', value, min, max, unit, sort, 'Portal', used_by, reason); help text may hold '' and quotes
  const block = sql.slice(sql.indexOf('insert into pipeline.platform_toolset_settings'), sql.indexOf('on conflict do nothing;', sql.indexOf('insert into pipeline.platform_toolset_settings')))
  const rows = block.split(/\n \('portal', /).slice(1)
  const settings = rows.map((r) => ({
    key: r.match(/^'([a-z_]+)'/)[1], label: r.match(/^'[a-z_]+',\s+'((?:[^']|'')+)'/)[1],
    ...Object.fromEntries(['value', 'min', 'max'].map((k, i) => [k, Number(r.match(/'number', '(\d+)'::jsonb, (\d+), (\d+), '([a-z]+)', (\d+), 'Portal', '((?:[^']|'')+)'/)[i + 1])])),
    unit: r.match(/'number', '\d+'::jsonb, \d+, \d+, '([a-z]+)'/)[1], usedBy: r.match(/'Portal', '((?:[^']|'')+)'/)[1], help: r.match(/^'[a-z_]+',\s+'(?:[^']|'')+',\s+'((?:[^']|'')+)'/)[1],
  }))
  expect(settings.map((m) => m.key).sort()).toEqual(['compare_courses_max', 'providers_page_size', 'recent_searches_shown', 'saved_courses_max', 'scholarships_page_size'])
  for (const m of settings) {
    expect(m.min, m.key).toBeLessThanOrEqual(m.value); expect(m.value, m.key).toBeLessThanOrEqual(m.max)
    expect(m.label.length, m.key).toBeGreaterThan(5); expect(m.help.length, m.key).toBeGreaterThan(10); expect(m.unit, m.key).toBeTruthy(); expect(m.usedBy, m.key).toBeTruthy()
  }
  for (const fn of ['public.portal_providers_v1', 'public.portal_scholarships_v1', 'public.portal_saved_set_v1', 'public.portal_saved_list_v1']) {
    expect(body(fn).replace(/-- .*$/gm, ''), fn).not.toMatch(/\blimit\s+([2-9]|\d{2,})\b/i) // "limit 1" picks the latest row; it is not a size
  }
  expect(body('public.portal_providers_v1')).toContain("security.portal_setting_v1('providers_page_size')")
  expect(body('public.portal_scholarships_v1')).toContain("security.portal_setting_v1('scholarships_page_size')")
  expect(body('public.portal_saved_set_v1')).toContain("security.portal_setting_v1('saved_courses_max')")
})

test('a person only ever sees their own shortlist, and the table is closed to direct reads', () => {
  expect(body('public.portal_saved_list_v1')).toContain('sc.user_id = auth.uid()')
  expect(body('public.portal_saved_set_v1')).toMatch(/user_id = auth\.uid\(\)/)
  expect(sql).toContain('alter table portal.saved_courses enable row level security;')
  expect(sql).toContain('revoke all on portal.saved_courses from public, anon, authenticated;')
  expect(body('public.portal_saved_set_v1')).toContain('SAVED_LIMIT')
})
