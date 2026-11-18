// Guards: Layer 1 Register first for every country (Platform Admin 19 Nov 2026 06:45 and 06:50): the next-wave destination sources (NZ, CA, GB, IE, US; population, climate, visa rules, careers) are registered by country with authority, authority domains, format, check and load cadence and licence before any ingestion; sources with no reader or uncleared terms are paused with their reason.
// CF-247 S715. supabase/migrations/20261119083300_cf247_wave2_destination_sources_layer1_register.sql.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261119083300_cf247_wave2_destination_sources_layer1_register.sql', 'utf8')
const code = M.split('\n').filter(l => !l.trimStart().startsWith('--')).join('\n')

test('four sources per country, in the existing registry, by country', () => {
  for (const cc of ['NZ', 'CA', 'GB', 'IE', 'US']) expect((code.match(new RegExp(`^  \\('${cc}', '`, 'gm')) || []).length).toBe(4)
  expect(code).toContain('insert into pipeline.sources(source_type, country_id, url, label, trust_rank, status, metadata)')
  expect(code).toContain('insert into pipeline.layer1_source_operations(source_id, authority_name, authority_domains, expected_format, expected_count_kind')
  expect(code).toContain("raise exception 'post-check: expected 20 next-wave sources in the Layer 1 Register, found %'")
  expect(code).toContain("raise exception 'post-check: a next-wave source lacks authority, domains, format, cadence or licence'")
})

test('only sources with a reader and open terms run; the rest are paused with their reason', () => {
  expect(code).toContain("true, not v.active_now, 30, v.load_days, 20, 60, v.active_now, null")
  expect(code).toContain("'Registered 19 Nov 2026 (20261119083300, s715), paused: ' || v.pause_reason")
  expect(code).toContain("'Awaiting cleared reuse terms (canada.ca Crown copyright) before facts are written'")
})

test('no new table or function; nothing dropped; consumer API checked', () => {
  expect(code).not.toMatch(/create table|create or replace function/i)
  expect(code).not.toMatch(/^\s*(delete from|drop |truncate )/im)
  expect(code).toContain('v_drift := security.consumer_api_check_v1();')
  expect(M).toMatch(/^-- Replaces: /m)
  expect(M).toMatch(/^-- Retires: /m)
})
