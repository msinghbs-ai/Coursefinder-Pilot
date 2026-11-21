// Guards: CF-247 s930 (Platform Admin 21 Nov 2026 11:55, S1-Dynamic-Lookups; standing rule "Dynamic Database-Driven Lookups" in CLAUDE.md and AGENTS.md): admin dropdowns, filter options and intake years read the live database; the Entry requirements Provider list holds every active provider and is never cut; no screen writes its own country list
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { countryName, countryPairs, intakeYears, targetCountries } from '../../src/lib/lookups.js'

const MIG = fs.readFileSync('supabase/migrations/20261121190000_cf247_s930_dynamic_lookups.sql', 'utf8')
const src = (f) => fs.readFileSync(`src/${f}`, 'utf8')

test('the Provider list of Entry requirements is every active provider, in name order, never cut (md5-guarded)', () => {
  expect(MIG).toContain("'0f4af8394ea36e6ef96df2e9130e0cc9'")
  expect(MIG).toContain("'8aba9ae6ad9b8f21fd1996ae9d93aa82'")
  expect(MIG).toContain("where p.lifecycle_status = 'active' or mc9.provider_id is not null")
  expect(MIG).toContain("'active_rows', z.a, 'waiting_rows', z.w")
  const v_new = MIG.slice(MIG.indexOf('v_new constant text'), MIG.indexOf('$n$;'))
  expect(v_new).not.toMatch(/\blimit\b/i)
  expect(MIG).toContain("'post-check: Charles Sturt University is not in the Provider list'")
})

test('public.admin_lookups_v1: countries, study levels and the rolling intake years, read only, any assigned role', () => {
  expect(MIG).toContain('create or replace function public.admin_lookups_v1(p_args jsonb default \'{}\'::jsonb) returns jsonb')
  expect(MIG).toMatch(/language plpgsql stable security definer set search_path to ''/)
  expect(MIG).toContain("if auth.uid() is null or v_rank < 1 then raise exception 'assigned StudySearch role required'")
  expect(MIG).toContain("security.pipeline_num_v1('lookups.intake_years_ahead', 2)")
  expect(MIG).toContain("generate_series(v_y, v_y + v_ahead)")
  expect(MIG).toContain("from ref.study_levels l")
  expect(MIG).toContain("'pipeline', 'lookups.intake_years_ahead', 'Lookups: intake years ahead'")
  expect(MIG).toContain('revoke all on function public.admin_lookups_v1(jsonb) from public, anon;')
})

test('screens read countries from the lookups, not from lists written in the code', () => {
  for (const f of ['ProviderOnboarding.jsx', 'EnrichPlan.jsx', 'HumanEditsAudit.jsx', 'Layer4Grid.jsx', 'FieldCoverage.jsx', 'data-quality-entry.jsx', 'lib/ops-pulse.js']) {
    const s = src(f)
    expect(s, f).not.toMatch(/\[\s*'AU'\s*,\s*'NZ'\s*,\s*'CA'\s*\]/)
    expect(s, f).not.toMatch(/\['AU',\s*'Australia/)
    expect(s, f).not.toMatch(/\{AU:'Australia'/)
  }
  expect(src('lib/lookups.js')).toContain("supabase.rpc('admin_lookups_v1'")
  const aer = src('AerWorkspace.jsx')
  expect(aer.match(/options=\{provOpts\(o\)\}/g)).toHaveLength(3)
  expect(aer).toContain('intakeYears(lk,o.intake_years||[])')
  expect(src('PlatformGuide.jsx')).toContain('data-guide-coverage')
})

test('the lookups helpers: target countries first, extra codes kept, intake years joined and ordered', () => {
  const lk = { countries: [{ code: 'AU', name: 'Australia', target: true }, { code: 'NZ', name: 'New Zealand', target: true }, { code: 'GB', name: 'United Kingdom', target: false }], intake_years: [2026, 2027, 2028] }
  expect(targetCountries(lk).map((c) => c.code)).toEqual(['AU', 'NZ'])
  expect(countryPairs(lk)).toEqual([['AU', 'Australia'], ['NZ', 'New Zealand']])
  expect(countryPairs(lk, { only: 'all' }).map(([c]) => c)).toEqual(['AU', 'NZ', 'GB'])
  expect(countryPairs(lk, { extra: ['CA'] }).map(([c]) => c)).toEqual(['AU', 'NZ', 'CA'])
  expect(intakeYears(lk, [2025, '2027'])).toEqual([2025, 2026, 2027, 2028])
  expect(countryName(lk, 'AU')).toBe('Australia')
  expect(countryPairs({})).toEqual([])
})

test('the standing rule is in CLAUDE.md and AGENTS.md', () => {
  for (const f of ['CLAUDE.md', 'AGENTS.md']) {
    const s = fs.readFileSync(f, 'utf8')
    expect(s, f).toContain('### Standing Rule: Dynamic Database-Driven Lookups (No Static Lists or Cut Subsets)')
    expect(s, f).toContain('`lookups.intake_years_ahead`')
  }
})
