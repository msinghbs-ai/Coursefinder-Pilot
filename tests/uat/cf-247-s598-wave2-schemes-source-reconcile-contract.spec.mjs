// Guards: Wave 2 admission groundwork (Platform Admin 18 Nov 2026 07:34): the four missing registration schemes (uk_ukvi, uk_hesa, ie_ilep, us_ipeds_completions) are registered and set on the drafts that had none; the four unused duplicate seed sources are retired, never deleted, and only while nothing references them; a duplicate source is the same address and the same name; nothing is activated
// CF-247 S598. Migration 20261118080000_cf247_wave2_schemes_and_source_reconcile.sql.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261118080000_cf247_wave2_schemes_and_source_reconcile.sql', 'utf8')

test('the four schemes are registered as planned and set only on drafts whose scheme is still empty', () => {
  for (const s of ["('uk_ukvi', 'provider_registration', 'GB'", "('uk_hesa', 'course_registration', 'GB'", "('ie_ilep', 'course_registration', 'IE'", "('us_ipeds_completions', 'course_registration', 'US'"]) expect(M).toContain(s)
  expect(M).toContain('on conflict (scheme, kind, country_code) do nothing;')
  expect(M).toContain("where i.id = x.id and i.status = 'draft' and coalesce(i.payload->>'scheme', '') = '' and coalesce(i.payload->>'scheme_kind', '') = '';")
  expect(M).toContain("raise exception 'post-check: a Wave 2 draft still has step 1 unfinished'")
})

test('duplicate seed sources are retired only while unreferenced, with the replacing draft named and logged', () => {
  expect(M).toContain("raise exception 'a seed source row is now referenced by %.% (% rows): not retired, nothing changed'")
  expect(M).toContain("update pipeline.sources s set status = 'retired', updated_at = now(),")
  expect(M).toContain("'superseded_by_induction', x.induction")
  expect(M).toContain("'source_retired_duplicate'")
  expect(M).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

test('a duplicate source is the same address and the same name (md5-guarded edit); nothing is activated', () => {
  expect(M).toContain("'af4ddf6016526eb12c06a27c94b54970'")
  expect(M).toContain('lower(s.url) = lower(v_url) and lower(btrim(s.label)) = lower(btrim(v_label))')
  expect(M).toContain("if v_c <> 1 then raise exception 'admin_layer1_add_source: the edit must apply exactly once")
  expect(M).not.toMatch(/admin_layer1_induction_activate\s*\(/)
  expect(M).toMatch(/-- Replaces: .+\n-- Retires: .+/)
})
