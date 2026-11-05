// Guards: decision 19:14 §8 (Platform Admin 5 Nov 2026): release validation uses production-representative constraints, grants, RLS, triggers and function signatures; the parity tool reads production only
// CF-247 agent E. Source contract for scripts/prod-parity-capture.mjs. The database round trip (capture -> fixture -> check, the simplified
// fixture caught, the intake releases' rejections reproduced) is tests/fixtures/prod-parity/run.sh, run by .github/workflows/prod-parity.yml.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import {
  captureSql, checkSql, digestSql, factsDigest, fixtureSql, verifyManifest, normaliseScope, subsetManifest, diffFacts, parseCaptured, PERSONAL,
} from '../../scripts/prod-parity-capture.mjs'

const MANIFEST = 'tests/fixtures/prod-parity/manifests/intake-lessons-admin-jobs-manual-locks.json'
const prod = () => JSON.parse(fs.readFileSync(MANIFEST, 'utf8'))

// Remove comments and every quoted literal, leaving the statement's own words.
function words(sql) {
  return sql.replace(/--[^\n]*/g, '').replace(/\$([a-z]*)\$[\s\S]*?\$\1\$/g, ' ').replace(/'(?:[^']|'')*'/g, ' ')
}
const WRITES = /\b(insert|update|delete|merge|create|alter|drop|grant|revoke|truncate|copy|vacuum|analyze|cluster|reindex|lock|listen|notify|call|do|set|reset|refresh|security|dblink|pg_read_file|pg_ls_dir|lo_import|set_config|nextval|setval|pg_terminate_backend|pg_cancel_backend)\b/i

test('the capture and check queries are one read-only SELECT each: no write, no setting change, no file or remote access', () => {
  // the screen is not vacuous: a write hidden after the WITH, or a setting change, is seen
  expect(words("with x as (select 1) insert into t select 1 from x")).toMatch(WRITES)
  expect(words("with x as (select set_config('search_path', '', false)) select 1")).toMatch(WRITES)
  expect(words("with x as (select 'insert' v) select v from x")).not.toMatch(WRITES)
  const scope = { tables: ['pipeline.admin_jobs', 'pipeline.manual_locks'], functions: ['security.ops_guard_refuse_v1()', 'security.aer_schedule_held_v1'], lookups: ['pipeline.ops_outcome_codes'] }
  for (const [name, sql] of [['capture', captureSql(scope)], ['check', checkSql(prod())], ['digest', digestSql(prod())], ['compact', checkSql(prod(), { compact: true })]]) {
    const w = words(sql)
    expect(/^(with|select) /.test(w.trim().toLowerCase()), `${name} is a query`).toBe(true)
    expect(w, `${name} has one statement`).not.toContain(';')
    // 'security' and 'set' are only names here (the schema, the column names); everything else is a write or side effect
    const found = (w.replace(/\bsecurity\./g, ' ').replace(/'?\bset_(at|by)\b/g, ' ').match(new RegExp(WRITES, 'gi')) || []).filter((x) => !/^security$/i.test(x))
    expect(found, `${name} contains ${found.join(', ')}`).toEqual([])
  }
})

test('scope names are checked; auth, storage, vault and realtime tables are never copied as lookups', () => {
  expect(() => normaliseScope({ tables: ['pipeline.admin_jobs; drop table x'] })).toThrow(/not a schema.table/)
  expect(() => normaliseScope({ functions: ["security.f'"] })).toThrow(/not a schema.function/)
  for (const t of ['auth.users', 'storage.objects', 'vault.secrets', 'realtime.messages']) expect(() => normaliseScope({ lookups: [t] })).toThrow(/refused/)
  expect(() => normaliseScope({ lookups: ['pipeline.ops_outcome_codes'], maxLookupRows: 100000 })).toThrow(/max-lookup-rows/)
  const re = new RegExp(PERSONAL, 'i')
  for (const c of ['email', 'set_by', 'requested_by', 'user_id', 'phone', 'actor', 'contact_name', 'ip']) expect(re.test(c), c).toBe(true)
  for (const c of ['code', 'title', 'counts_as_movement', 'kind', 'label', 'added_in']) expect(re.test(c), c).toBe(false)
})

test('the committed production manifest verifies: definitions equal their md5s, no personal data, the intake lessons are present', () => {
  const m = prod()
  expect(m.source).toMatch(/fxcwkweaxjtknorudmwp.*read-only/)
  expect(verifyManifest(m)).toEqual([])
  const f = m.facts
  expect(f['constraint|pipeline.admin_jobs|admin_jobs_outcome_fkey']).toBe('f|FOREIGN KEY (outcome) REFERENCES pipeline.ops_outcome_codes(code)')
  expect(f['constraint|pipeline.manual_locks|manual_locks_pkey']).toBe('p|PRIMARY KEY (entity, entity_id, field)')
  expect(f['constraint|pipeline.manual_locks|manual_locks_mode_check']).toContain("'value'::text, 'removed'::text")
  expect(f['lookup_rows|pipeline.ops_outcome_codes']).toMatch(/^8\|[0-9a-f]{32}$/)
  for (const t of m.tables) for (const r of t.rows || []) for (const k of Object.keys(r)) expect(new RegExp(PERSONAL, 'i').test(k), `${t.fq}.${k}`).toBe(false)
  // a transcription error in a definition is refused
  const bad = prod(); bad.functions[0].def += ' '
  expect(verifyManifest(bad).join('\n')).toMatch(/differs from captured/)
  // the digest the one-row production check compares with
  expect(digestSql(m)).toContain(`= '${factsDigest(m.facts).md5}' as matches_manifest`)
  // the saved tool output can be the MCP text, rows or the manifest
  expect(parseCaptured(JSON.stringify([{ manifest: m }])).facts).toEqual(m.facts)
  expect(parseCaptured(`<untrusted-data-x>\n${JSON.stringify([{ manifest: m }])}\n</untrusted-data-x>`).facts).toEqual(m.facts)
})

test('the fixture reproduces keys, foreign keys with seeded code values, checks, triggers with their functions, RLS and exact grants, on a local database only', () => {
  const sql = fixtureSql(prod())
  expect(sql).toContain("refusing a Supabase project database")
  expect(sql).toContain("prod-parity fixtures are for a local database only")
  expect(sql).toMatch(/add constraint admin_jobs_outcome_fkey FOREIGN KEY \(outcome\) REFERENCES pipeline\.ops_outcome_codes\(code\)/)
  expect(sql).toMatch(/add constraint manual_locks_pkey PRIMARY KEY \(entity, entity_id, field\)/)
  expect(sql).toMatch(/insert into pipeline\.ops_outcome_codes \(code, title, counts_as_movement\) select/)
  expect(sql).toContain('succeeded_with_result')
  expect(sql).toContain('CREATE OR REPLACE FUNCTION security.ops_remedy_guard_active_v1()')
  expect(sql).toMatch(/CREATE TRIGGER ops_guard_locks BEFORE INSERT OR DELETE OR UPDATE ON pipeline\.manual_locks FOR EACH ROW WHEN \(security\.ops_remedy_guard_active_v1\(\)\)/)
  expect(sql).toContain('alter table pipeline.manual_locks enable row level security;')
  expect(sql).toMatch(/revoke all on table pipeline\.admin_jobs from public, anon, authenticated, authenticator, service_role;/)
  expect(sql).toMatch(/set search_path to "\\\$user", public, extensions;/)
  // keys come before the code rows, the rows before the foreign keys, the functions before the defaults and triggers that need them
  const at = (s) => sql.indexOf(s)
  expect(at('add constraint ops_outcome_codes_pkey')).toBeLessThan(at('insert into pipeline.ops_outcome_codes'))
  expect(at('insert into pipeline.ops_outcome_codes')).toBeLessThan(at('add constraint admin_jobs_outcome_fkey'))
  expect(at('CREATE OR REPLACE FUNCTION security.ops_remedy_guard_active_v1')).toBeLessThan(at('CREATE TRIGGER ops_guard_locks'))
})

test('a part of a manifest keeps exactly the facts of the smaller scope; facts compare both ways', () => {
  const m = prod()
  const part = subsetManifest(m, ['pipeline.progress_transitions'])
  expect(part.scope.tables).toEqual(['pipeline.progress_transitions'])
  expect(part.tables.map((t) => t.fq).sort()).toEqual(['pipeline.integration_issues', 'pipeline.progress_transitions'])
  expect(Object.keys(part.facts).some((k) => k.includes('admin_jobs') || k.includes('manual_locks'))).toBe(false)
  expect(part.facts['constraint|pipeline.progress_transitions|progress_transitions_next_key_fkey']).toBeTruthy()
  expect(() => subsetManifest(m, ['pipeline.nothing'])).toThrow(/not target tables/)
  const b = prod(); delete b.facts['constraint|pipeline.manual_locks|manual_locks_pkey']; b.facts['column|pipeline.manual_locks|mode'] = 'pipeline.lock_mode|notnull=true'
  expect(diffFacts(m, b).map((d) => `${d.diff} ${d.fact}`)).toEqual(['different column|pipeline.manual_locks|mode', 'missing constraint|pipeline.manual_locks|manual_locks_pkey'])
})

test('the database round trip runs in its own workflow on PostgreSQL 17 (production is 17.6) and never names a Supabase project', () => {
  const wf = fs.readFileSync('.github/workflows/prod-parity.yml', 'utf8')
  expect(wf).toContain('image: postgres:17.6-alpine')
  expect(wf).toContain('bash tests/fixtures/prod-parity/run.sh')
  const run = fs.readFileSync('tests/fixtures/prod-parity/run.sh', 'utf8')
  expect(run.startsWith('#!/usr/bin/env bash\n# Guards: ')).toBe(true)
  expect(run).toContain("Refusing a remote database")
  for (const f of [wf, run, fs.readFileSync('scripts/prod-parity-capture.mjs', 'utf8')]) {
    expect(f).not.toMatch(/supabase\s+db\s+push|apply_migration|SUPABASE_ACCESS_TOKEN|supabase\.co/)
  }
})
