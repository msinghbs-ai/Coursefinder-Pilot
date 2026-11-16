// Guards: Admin destination data design v1.6 (roadmap schema pack, Platform Admin 17 Nov 2026 07:39; RM0C, RM0D, RM0E, RM0F): the pack extends the destination tables of 20261115190000 in place, returns only approved or published rows on the API v3 destination action, and keeps approval with the Platform Admin
// Behaviour is proven on isolated PostgreSQL by tests/fixtures/destination-schema-pack/run.sh (workflow destination-schema-pack-test); these checks keep the rules in the migration and the edge functions.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261117040000_cf247_rm_destination_schema_pack.sql', 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const web = fs.readFileSync('supabase/functions/website-api-v3/index.ts', 'utf8')
const zoho = fs.readFileSync('supabase/functions/zoho-api-v3/index.ts', 'utf8')

test('extend in place: the 20261115190000 tables are altered, never created again or dropped; the new tables are new', () => {
  for (const t of ['editions', 'study_rules', 'city_profiles', 'career_outcomes']) expect(code).not.toMatch(new RegExp(`create table (if not exists )?destination\\.${t}\\b`))
  for (const t of ['destination.localities', 'destination.locality_postcodes', 'destination.locality_metrics', 'destination.rule_applicability', 'ref.registration_schemes']) {
    expect(code).toContain(`create table if not exists ${t} (`)
    expect(code).toContain(`alter table ${t} enable row level security;`)
  }
  expect(code).toContain('alter table destination.study_rules\n  add column if not exists state_code text,')
  expect(code).toContain('alter table destination.career_outcomes\n  add column if not exists locality_id uuid references destination.localities(id) on delete restrict,')
  expect(code).not.toMatch(/drop (table|column|function|schema|trigger|index)/i)
  // the deploy step (scripts/ci/apply-migration.sh) refuses these at the start of a line; 20261117030000 was refused for one, so the same test runs here before merge
  expect(m).not.toMatch(/^(drop|delete|truncate)\b|^alter table .* drop /im)
  expect(code).not.toMatch(/destination_(import|row_guard|edition_guard|edition_publish|edition_set_terms)_v1\s*\(/) // the importer and guards of 20261115230000 are not replaced
})

test('only approved or published rows are returned; a rule or career row also needs its edition published and a rule its effective dates', () => {
  expect(code).toContain("where l.status in ('approved', 'published')")
  expect(code).toContain("m.status in ('approved', 'published')")
  expect((code.match(/join destination\.editions e on e\.id = [ro]\.edition_id and e\.status = 'published'/g) || []).length).toBe(2)
  expect(code).toContain("where r.approval_status = 'approved'")
  expect(code).toContain('(r.effective_from is null or r.effective_from <= current_date) and (r.effective_to is null or r.effective_to >= current_date)')
  expect(code).toContain("where o.status in ('approved', 'published')")
  expect(code).toContain("return jsonb_build_object('localities', v_loc, 'study_rules', v_rules, 'career_outcomes', v_careers,")
  for (const f of ['website_v3_destination', 'zoho_v3_destination']) {
    expect(code).toContain(`revoke all on function public.${f}(jsonb, int, int) from public, anon, authenticated;`)
    expect(code).toContain(`grant execute on function public.${f}(jsonb, int, int) to service_role;`)
  }
})

test('v2 stays untouched and both v3 edge functions offer the destination action through their own wrapper', () => {
  expect(code).not.toMatch(/create or replace function (public\.(website|zoho)_v2_|public\.website_edge_|public\.zoho_edge_|api\.)/i)
  expect(code).not.toMatch(/create or replace function public\.(website|zoho)_v3_(?!destination\()/)
  expect(web).toMatch(/const ACTIONS = \[[^\]]*"destination"\]/); expect(zoho).toMatch(/const ACTIONS = \[[^\]]*"destination"\]/)
  expect(web).toContain('case "destination": fn = "website_v3_destination";')
  expect(zoho).toContain('case "destination": fn = "zoho_v3_destination";')
  for (const v2 of ['website-api-v2', 'zoho-api-v2']) expect(fs.readFileSync(`supabase/functions/${v2}/index.ts`, 'utf8')).not.toContain('destination')
})

test('approval is the Platform Admin’s, with a reason; reading is Curator and above; the access history takes password_reset_sent as a superset', () => {
  expect(code).toContain("if coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin (rank 6) is needed to approve or withdraw destination data'")
  expect(code).toContain("if v_reason is null then raise exception 'a reason is required'")
  expect((code.match(/current_role_rank\(\), 0\) < 3 then raise exception 'Curator role or above required'/g) || []).length).toBe(2)
  expect(code).toContain("check (action = any (array['user_created', 'user_invited', 'roles_replaced', 'user_disabled', 'user_enabled', 'password_reset_sent']));")
})

test('schemes are registered once per kind and country in the keys the catalogue stores, each with the schemes it is never mixed with', () => {
  expect(code).toContain('primary key (scheme, kind, country_code)')
  for (const s of ['cricos', 'nzqa', 'mtcu', 'ircc_dli', 'pgwp', 'uk_qaa', 'uk_ofs', 'ie_qqi', 'us_opeid', 'us_ipeds', 'asced', 'nzsced', 'cip', 'hecos']) expect(code).toContain(`('${s}', '`)
  expect(code).toMatch(/\('ircc_dli', 'provider_registration', 'CA'[^\n]*'\{pgwp,cricos,nzqa\}'/)
  expect(code).toMatch(/\('asced', 'field_of_study', 'AU'[^\n]*'\{nzsced,cip,hecos\}'/)
  expect(code).not.toMatch(/update catalogue\.|alter table catalogue\./) // what the catalogue stores is not changed
})
