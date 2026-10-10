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

test('rebuild test refuses the Pilot and any project not named coursefinder-baseline-test', () => {
  const wf = readFileSync('.github/workflows/db-baseline-rebuild-test.yml', 'utf8')
  expect(wf).toContain("Refused: that is the Pilot project")
  expect(wf).toContain('if [ "$name" != "coursefinder-baseline-test" ]')
  expect(wf).toContain('Refused: the test project is not empty')
})
