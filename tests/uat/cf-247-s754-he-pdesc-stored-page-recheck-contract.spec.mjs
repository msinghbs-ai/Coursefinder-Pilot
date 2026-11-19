// Guards: University and higher-education provider description triage and re-check (Platform Admin 19 Nov 2026 16:00, s754): one read is queued only for published, active providers of those types with no description, no manual lock, a stored official page and no open read, whose latest read was held by a content rule (never identity, host, sub-unit or a refused source word) and was not made by GPT-4.1 mini in the last day; the reader, the identity proof and the unchanged machine admission decide; Firecrawl stays off and the route cap stays at most US$0.50
// CF-247 S754. Migration 20261119170500_cf247_s754_he_pdesc_stored_page_recheck. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261119170500_cf247_s754_he_pdesc_stored_page_recheck.sql', 'utf8')

test('only higher-education providers with no description, no lock, a stored page and no open read are queued', () => {
  expect(M).toContain("in ('university', 'university_college', 'higher_education_institute', 'wananga')")
  expect(M).toContain("and p.lifecycle_status = 'active' and p.publication_status = 'published' and nullif(btrim(p.description), '') is null")
  expect(M).toContain("l.field in ('description', 'p_description', 'all')")
  expect(M).toContain("r.state in ('queued', 'reading', 'proposed')")
  expect(M).toContain('security.provider_description_stored_v1(lr.provider_id) is not null')
})

test('identity, host, sub-unit and refused-source holds are never re-read; a same-day GPT-4.1 mini read is not repeated', () => {
  expect(M).toContain("lr.rule not in ('provider_name_conflict', 'provider_name_not_proved', 'provider_host_conflict', 'provider_subunit_source', 'refused_word', 'refused_host')")
  expect(M).toContain("lr.rule not like 'machine_declined_identity%'")
  expect(M).toContain("not (coalesce(lr.model, '') ilike '%gpt-4.1-mini%' and lr.created_at > now() - interval '1 day')")
})

test('no Firecrawl, capped route, no overwrite, nothing created', () => {
  expect(M).toContain("security.pipeline_num_v1('pdesc.acquire_firecrawl', 1) <> 0")
  expect(M).toContain("(security.ai_route_v1('provider_description')->'cap'->>'usd')::numeric > 0.5")
  expect(M).toContain("raise exception 'post-check: a provider with a description was queued'")
  expect(M).toContain("raise exception 'post-check: a provider has two open reads'")
  expect(M).not.toMatch(/create (table|or replace function|function|schema)|alter table|cron\.schedule|update catalogue\.|delete from/i)
  expect(M).toMatch(/^-- Replaces: nothing$/m)
  expect(M).toMatch(/^-- Retires: nothing$/m)
})
