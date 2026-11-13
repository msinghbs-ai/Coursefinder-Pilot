// Guards: F-SCH provider coverage and applicant nationality in the existing Admin views (Platform Admin S2-Scholarship directive 13 Nov 2026 16:01 §5, §6; Developer Requirements v2.26 F-SCH.11, F-SCH.13): every provider in the scholarship population is filterable by country, university, state and published, with its next action; a student-nationality filter uses proven rules only and never counts "not stated" as eligible
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261113351500_cf247_sch_provider_coverage_and_nationality_country.sql'
const m = fs.readFileSync(MIG, 'utf8')
const cov = fs.readFileSync('src/ScholarshipCoverage.jsx', 'utf8')
const ui = fs.readFileSync('src/mature-main.jsx', 'utf8')
const exp = fs.readFileSync('scripts/export/sch-provider-coverage-evidence.sql', 'utf8')

test('the snapshot holds the same population, disposition and next action as the dated evidence export', () => {
  expect(m).toContain('create table if not exists pipeline.scholarship_provider_coverage (')
  expect(m).toContain('comment on table pipeline.scholarship_provider_coverage is')
  expect(m).toContain('with univ as materialized (select p.id from catalogue.providers p where security.scholarship_university(p.id)),')
  for (const t of ['pipeline.scholarship_discovery_providers', 'pipeline.scholarship_page_candidates', 'pipeline.scholarship_listing_pages', 'scholarship.scholarships'])
    expect(m).toContain(`union select provider_id from ${t}`)
  // every disposition of the export, word for word
  const disp = [...exp.matchAll(/then '([a-z_]+)'\n/g)].map((x) => x[1]).filter((d) => exp.includes(`'${d}'`))
  expect(disp.length).toBeGreaterThanOrEqual(8)
  for (const d of disp) expect(m).toContain(`'${d}'`)
  expect(m).toContain("else 'not_yet_attempted_or_vendor_failure' end disposition")
  expect(m).toContain('least(d.next_discover_at, k.next_read, cv.next_recovery) next_retry')
})

test('rebuilt after each full hourly classification; a failure keeps the last snapshot and never stops classification', () => {
  expect(m).toContain("select pg_temp.edit_n('security.scholarship_coverage_classify_v1(uuid[])', 'e305eb1354ba06dc5922d0d7b7f3ed19'")
  expect(m).toContain('if p_providers is null then')
  expect(m).toContain("exception when others then raise warning 'scholarship_provider_coverage_refresh_v1: %', sqlerrm; end;")
})

test('Coverage › All providers reads the snapshot with the country, university, state and published filters and the funnel', () => {
  expect(m).toContain('create or replace function public.admin_scholarship_provider_coverage(p_args jsonb')
  expect(m).toContain("if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required'")
  for (const k of ["p_args->>'country'", "p_args->>'universities'", "p_args->>'disposition'", "p_args->>'has_published'"]) expect(m).toContain(k)
  for (const k of ["'searched'", "'official_source'", "'pages_read'", "'scholarships_published'", "'providers_published'"]) expect(m).toContain(k)
  expect(cov).toContain("supabase.rpc('admin_scholarship_provider_coverage',{p_args:args})")
  expect(cov).toContain('data-cov-tab-providers>All providers</button>')
  expect(cov).toContain("if(scope==='providers')return;")
})

test('student nationality: a proven rule naming the country or proven open to all, never one that excludes it; not stated only when asked', () => {
  expect(m).toContain("select pg_temp.edit_n('security.admin_scholarships_page(jsonb)', '4ab6f36b1da99f3a19b55552332c5bc6'")
  expect(m).toContain("and (upper(p_args->>'nationality_country') = any (coalesce(nr.codes, '{}'::text[])) or coalesce(nr.phrases ? 'ANY', false))")
  expect(m).toContain("coalesce(cx.value_json->'excluded', '[]'::jsonb) ? upper(p_args->>'nationality_country')")
  expect(m).toContain("or (coalesce((p_args->>'nationality_unknown_too')::boolean, false) and l4.entity_id is null")
  expect(m).toContain("'nationality_countries',(select")
  expect(ui).toContain("['nationalityCountry','nationality_country'],['nationalityUnknownToo','nationality_unknown_too']]")
  expect(ui).toContain('<FilterSelect label="Student nationality" value={filters.nationalityCountry||\'\'}')
})

test('admin read paths only: no consumer object is touched (G3)', () => {
  expect(m).not.toMatch(/create or replace function (api\.|public\.website_|public\.zoho_)/i)
  expect(m).toContain('-- Replaces: security.admin_scholarships_page(jsonb), security.scholarship_coverage_classify_v1(uuid[])')
  expect(m).toContain('-- Retires: nothing.')
})
