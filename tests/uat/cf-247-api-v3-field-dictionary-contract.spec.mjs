// Guards: REQ-76 API v3 field dictionary (Platform Admin 15 Nov 2026, combined build item 1): every Website API v3 and Zoho API v3 read action is described field by field in docs/api/v3/field-dictionary.json, and the newest sync migration (20261118135707, after 20261116110000) loads exactly that list
// Behaviour of the sync and drift functions is proven on isolated PostgreSQL by tests/fixtures/api-field-dictionary/run.sh (workflow api-field-dictionary-test).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { load, validate, compact, embedded } from '../../scripts/api-v3-field-dictionary.mjs'
import { migrationNames, migrationPath } from './support/migration-files.mjs'

// the sync and drift functions live in 20261116110000; each later reviewed list is loaded by its own sync migration, the newest of which must embed the file
const MIG = 'supabase/migrations/20261116110000_cf247_api_field_dictionary_sync.sql'
const LIST = 'supabase/migrations/20261118135707_cf247_api_field_dictionary_v3_gaps.sql'
const sql = fs.readFileSync(MIG, 'utf8')
const listSql = fs.readFileSync(LIST, 'utf8')
const code = sql.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const doc = load()
const actions = (file) => JSON.parse(fs.readFileSync(file, 'utf8').match(/const ACTIONS = (\[[^\]]+\])/)[1].replace(/\s+/g, ' '))

test('the reviewed list is complete and valid: one entry per field, a description and a type for each, parents listed', () => {
  expect(validate(doc)).toEqual([])
  for (const f of doc.fields) expect(f.description.trim().length, `${f.api_surface} ${f.endpoint} ${f.field_path}`).toBeGreaterThan(8)
})

test('the newest sync migration loads exactly the reviewed list', () => {
  expect(embedded(listSql)).toBe(compact(doc))
  expect(listSql).toContain("security.api_field_dictionary_sync_v1('v3', 'v3.0', (")
  const newest = migrationNames().filter((f) => /api_field_dictionary/.test(f) && embedded(fs.readFileSync(migrationPath(f), 'utf8'))).sort().at(-1)
  expect(migrationPath(newest)).toBe(LIST)
})

test('every read action of both v3 APIs is in the dictionary', () => {
  const writes = new Set(['report'])   // a counsellor report is a write, described in the guide's request table
  const web = actions('supabase/functions/website-api-v3/index.ts')
  const zoho = actions('supabase/functions/zoho-api-v3/index.ts').filter((a) => !writes.has(a))
  // 17 Nov 2026 (roadmap schema pack, RM0E): an action added since the last reviewed issue is described under pending_fields (with a pending_reason) until the next issue loads it
  const held = (s) => new Set([...doc.fields, ...(doc.pending_fields || [])].filter((f) => f.api_surface === s).map((f) => f.endpoint.split(':')[0]))
  for (const a of web) expect(held('website').has(a), `website ${a}`).toBe(true)
  for (const a of zoho) expect(held('zoho').has(a), `zoho ${a}`).toBe(true)
})

test('the sync writes only what changed and never deletes; only the service role can run it', () => {
  expect(code).toContain('on conflict (api_surface, version, endpoint, field_path) do update')
  expect(code).toContain('is distinct from')
  expect(code).toContain('set deprecated_in = p_release')
  expect(code).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  for (const f of ['api_field_dictionary_sync_v1(text, text, jsonb)', 'api_field_dictionary_drift_v1(text, text, jsonb, text)']) {
    expect(code).toContain(`revoke all on function security.${f} from public, anon, authenticated;`)
    expect(code).toContain(`grant execute on function security.${f} to service_role;`)
  }
})
