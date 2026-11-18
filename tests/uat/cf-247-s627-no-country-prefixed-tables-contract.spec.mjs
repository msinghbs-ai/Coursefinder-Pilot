// Guards: Platform Admin 18 Nov 2026 11:28 (S1-RM-Design, 29-destination architecture lock): one normalised schema serves every country; no migration may create or rename a table or view whose name starts with a country code (ca_, uk_, nz_, ie_, us_, pl_, it_, gr_, cy_, th_, my_, kr_, jp_ and every other destination). A country is a value in a country_code or country_id column, never a table. The six country-prefixed objects that existed before the lock are listed and may not grow.
// The mapping of every destination dataset to the existing tables is in the admin repository: docs/platform/DESTINATION-EDITIONS-AND-WAVE2-DRAFTS-RUNBOOK.md (Multi-country schema lock) and docs/CURRENT-STATE.md.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import path from 'node:path'

// the 28 Study Square destinations and the other country codes in use (ISO 3166-1 alpha-2, with uk beside gb)
const CODES = ['au', 'ca', 'gb', 'uk', 'nz', 'ie', 'us', 'de', 'se', 'fi', 'dk', 'es', 'mt', 'nl', 'fr', 'at', 'ch', 'pl', 'hu', 'it', 'gr', 'lv', 'cy', 'ae', 'th', 'sg', 'my', 'kr', 'jp', 'in', 'cn', 'np', 'lk', 'bd', 'pk', 'vn', 'ph', 'id']
// present before the lock (18 Nov 2026); read live then. Kept, never extended; a replacement goes into the shared tables.
export const LEGACY = ['pipeline.nz_cop_reads', 'pipeline.nz_cop_status', 'pipeline.ca_course_scope_keys', 'pipeline.au_nz_enrichment_backlog_v1', 'pipeline.au_nz_enrichment_backlog_summary_v1', 'ref.au_regional_postcode_ranges']
const NAME = `(?:"?[a-z_]+"?\\.)?"?((?:${CODES.join('|')})_[a-z0-9_]*)"?`
const CREATE = new RegExp(`\\bcreate\\s+(?:or\\s+replace\\s+)?(unlogged\\s+|temporary\\s+|temp\\s+)?(?:table|view|materialized\\s+view)\\s+(?:if\\s+not\\s+exists\\s+)?(${NAME})`, 'gi')
const RENAME = new RegExp(`\\balter\\s+(?:table|view|materialized\\s+view)\\s+(?:if\\s+exists\\s+)?[^;]*?\\brename\\s+to\\s+"?((?:${CODES.join('|')})_[a-z0-9_]*)"?`, 'gi')
const dir = 'supabase/migrations'
const code = (f) => fs.readFileSync(path.join(dir, f), 'utf8').split('\n').map((l) => l.replace(/--.*$/, '')).join('\n')

export function countryTables(sql) {
  const out = []
  // a temporary table is scratch work inside one migration, not schema
  for (const m of sql.matchAll(CREATE)) if (!/^temp/i.test(m[1] || '')) out.push(m[2].replace(/"/g, '').toLowerCase())
  for (const m of sql.matchAll(RENAME)) out.push(m[1].toLowerCase())
  return out
}

test('no migration creates or renames to a country-prefixed table or view, beyond the six held before the lock', () => {
  const found = []
  for (const f of fs.readdirSync(dir).filter((x) => x.endsWith('.sql'))) for (const t of countryTables(code(f))) {
    const full = t.includes('.') ? t : `?.${t}`
    if (!LEGACY.some((l) => l === full || l.endsWith(`.${t.split('.').pop()}`))) found.push(`${f}: ${t}`)
  }
  expect(found).toEqual([])
})

test('the check finds what it must and leaves temporary work and ordinary names alone', () => {
  expect(countryTables('create table if not exists catalogue.uk_providers (id uuid);')).toEqual(['catalogue.uk_providers'])
  expect(countryTables('CREATE OR REPLACE VIEW pipeline.jp_courses_v AS select 1;')).toEqual(['pipeline.jp_courses_v'])
  expect(countryTables('alter table destination.localities rename to ca_localities;')).toEqual(['ca_localities'])
  expect(countryTables('create table catalogue.provider_accreditations (id uuid); create table destination.locality_metrics (id uuid);')).toEqual([])
  expect(countryTables('create table pipeline.campus_regional_class (id uuid);')).toEqual([]) // "ca" inside a word is not a prefix
  expect(countryTables('create temp table nz_names(id uuid) on commit drop;')).toEqual([])
})
