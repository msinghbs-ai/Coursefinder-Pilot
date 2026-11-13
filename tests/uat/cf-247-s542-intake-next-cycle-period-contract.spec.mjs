// Guards: F-INT next-year period matching (Platform Admin decision 13 Nov 2026 14:58, Intake Process Record §14): for the listed providers only, an intake takes the next start of the named period that starts in its month even when another named period starts sooner; a page tied to other years is held; other providers are unchanged.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const mig = fs.readFileSync('supabase/migrations/20261113331500_cf247_intake_next_cycle_period.sql', 'utf8')

test('scoped by a setting naming only Canterbury and Massey; empty means off', () => {
  expect(mig).toContain("'intake_dates.next_cycle_period_providers'")
  expect(mig).toContain('\'["db910e88-67d1-4d2b-a65c-cea290aa0692","229dc07d-c573-44a3-b5dc-cc423cc2c300"]\'::jsonb')
  expect(mig).toContain("where s.toolset_key = 'pipeline' and s.key = 'intake_dates.next_cycle_period_providers' and jsonb_typeof(s.value) = 'array'), '{}');")
  expect(mig).toContain('on conflict (toolset_key, key) do nothing;')
})

test('the "starts sooner" check counts only named periods that start in the intake month, for listed providers only', () => {
  expect(mig).toContain('and (not (r.provider_id = any (v_next))')
  expect(mig).toContain('where s2.kind = \'start\' and s2.period = s.period and s2.month = v_m and s2.year_ok));')
  // the original holding branch stays for everything else
  expect(mig).toContain('    if v_start is not null then$n$]')
})

test('an offering tied to other years is never rolled into the next year; the listed providers are looked at again by fingerprint only', () => {
  expect(mig).toContain("and coalesce(v_raw, '') ~ '\\m20\\d\\d\\M' and coalesce(v_raw, '') !~ ('\\m' || v_year || '\\M') then")
  expect(mig).toContain("reason := 'the course page names only other years for its intakes: the ' || v_year || ' start in this month is not taken (month only)';")
  expect(mig).toContain("case when c.provider_id = any (v_next) then ';nextcycle=1' else '' end")
  expect(mig).toContain("case when r.provider_id = any (v_next) then ';nextcycle=1' else '' end")
})

test('md5-guarded counted edit, post-checked, nothing dropped, housekeeping lines present', () => {
  expect(mig).toContain("pg_temp.edit_counted('security.intake_dates_plan_v3(uuid[],integer)', '98ab7972726d0b3ccef7e816be77fd8d', '020a047e45a9c8e82ad45be74a668b2b',")
  expect(mig).toContain('array[1, 2, 1, 1]);')
  expect(mig).toContain("if v_c <> p_counts[i] then raise exception")
  expect(mig).toMatch(/<> '020a047e45a9c8e82ad45be74a668b2b' then\s+raise exception 'post-check/)
  expect(mig).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(mig).toMatch(/^-- Replaces: security\.intake_dates_plan_v3/m)
  expect(mig).toMatch(/^-- Retires: nothing\./m)
})
