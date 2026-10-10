// CF-247 production readiness phase 4 (10 Oct 2026): the live schema baseline is held in git and the
// rebuild test can never target the Pilot.
import { test, expect } from '@playwright/test'
import { readFileSync } from 'node:fs'
import { createHash } from 'node:crypto'

const dir = 'supabase/live-capture/baseline'
const md5 = (b) => createHash('md5').update(b).digest('hex')

test('baseline files match their recorded md5', () => {
  const sums = readFileSync(`${dir}/MD5SUMS`, 'utf8').trim().split('\n').map((l) => l.split(/\s+/))
  expect(sums.map((s) => s[1]).sort()).toEqual(['roles.sql', 'schema.sql'])
  for (const [hash, file] of sums) expect(md5(readFileSync(`${dir}/${file}`))).toBe(hash)
  const schema = readFileSync(`${dir}/schema.sql`, 'utf8')
  expect((schema.match(/^CREATE (OR REPLACE )?FUNCTION/gm) || []).length).toBe(1257)
  expect((schema.match(/^CREATE TABLE/gm) || []).length).toBe(400)
})

test('roles-apply.sql is the captured roles.sql minus only the Supabase-managed parameter grant', () => {
  const grant = 'GRANT SET ON PARAMETER "log_min_messages" TO "supabase_realtime_admin";'
  const raw = readFileSync(`${dir}/roles.sql`, 'utf8').split('\n')
  const apply = readFileSync(`${dir}/roles-apply.sql`, 'utf8').split('\n')
  expect(raw.filter((l) => l !== grant)).toEqual(apply)
  expect(raw.length - apply.length).toBe(1)
  expect(readFileSync('.github/workflows/db-baseline-rebuild-test.yml', 'utf8')).toContain('baseline/roles-apply.sql')
})

test('rebuild applies the default-privileges preamble before the schema', () => {
  const pre = readFileSync(`${dir}/apply-preamble.sql`, 'utf8')
  for (const kind of ['FUNCTIONS', 'TABLES', 'SEQUENCES'])
    expect(pre).toContain(`ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON ${kind} FROM "anon", "authenticated", "service_role";`)
  const wf = readFileSync('.github/workflows/db-baseline-rebuild-test.yml', 'utf8')
  expect(wf).toContain('cat supabase/live-capture/baseline/apply-preamble.sql supabase/live-capture/baseline/schema.sql')
  // the closing defaults in schema.sql restore the Pilot's defaults
  const schema = readFileSync(`${dir}/schema.sql`, 'utf8')
  expect(schema).toContain('ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";')
})

test('rebuild test refuses the Pilot and any project not named coursefinder-baseline-test', () => {
  const wf = readFileSync('.github/workflows/db-baseline-rebuild-test.yml', 'utf8')
  expect(wf).toContain("Refused: that is the Pilot project")
  expect(wf).toContain('if [ "$name" != "coursefinder-baseline-test" ]')
  expect(wf).toContain('Refused: the test project is not empty')
})
