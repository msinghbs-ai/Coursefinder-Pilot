// Guards: Atlas brief to S1-API-Frontend-Delivery, 26 Nov 2026 12:02 AEDT: the Entry Requirements Study level filter reads the live level table, Viewer and above, anon refused (portal access, s1143)
// CF-247 s1215: public.portal_study_levels_v1 gives the Entry Requirements screen its Study level filter from the live level table (s930).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const dir = 'supabase/migrations'
const file = fs.readdirSync(dir).find(f => f.startsWith('20261129090000_cf247_s1215_'))
const sql = file ? fs.readFileSync(`${dir}/${file}`, 'utf8') : ''

test('the migration exists, is above S2-Build’s s1214 version, and carries the housekeeping lines', () => {
  expect(file).toBeTruthy()
  expect(sql).toMatch(/^-- Replaces: nothing/m); expect(sql).toMatch(/^-- Retires: nothing/m)
  expect(sql).toContain("register (kind, name, layer, area, purpose, status, replaces, introduced_in)")
})

test('read only, Viewer and above, anon refused, authenticated granted', () => {
  expect(sql).toContain('perform security.portal_rank_v1(1)')
  expect(sql).toMatch(/revoke all on function public\.portal_study_levels_v1\(\) from public, anon/)
  expect(sql).toMatch(/grant execute on function public\.portal_study_levels_v1\(\) to authenticated/)
  expect(sql).not.toMatch(/\b(insert into|update|delete from|drop|truncate)\b(?![^;]*component_register)[^;]*\bref\./i)
  expect(sql).not.toMatch(/\bdrop\s+(table|function|schema)/i)
})

test('levels are read from the live table, not listed in the function', () => {
  expect(sql).toMatch(/from ref\.study_levels s/)
  expect(sql).toMatch(/search\.course_documents/)
  expect(sql).not.toMatch(/'(bachelor|masters|diploma|doctorate)'/)
})

test('the consumer API is guarded before and after, and no frozen name is touched', () => {
  expect(sql).toMatch(/pre-check: consumer API baseline/); expect(sql).toMatch(/post-check: consumer API baseline changed/)
  expect(sql).toContain('75'); expect(sql).toContain('48')
  expect(sql).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1/)
  expect(sql).toMatch(/s1215_guard/); expect(sql).toMatch(/cron before|cron_before/); expect(sql).toMatch(/locks_before/)
})
