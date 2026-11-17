// Guards: Two repositories, one source of truth (Platform Admin 16 Nov 2026 09:20; paste split approved 16 Nov 2026 10:10, done 18 Nov 2026): Pilot has no docs/paste/ folder; a paste file lives in admin docs/paste/, and only the byte-for-byte copies that specs, database fixtures, workflow triggers or the evidence classifier read are kept, as test fixtures, in tests/fixtures/paste/
// CF-247 S616. tests/fixtures/paste/; CLAUDE.md "Existing files"; scripts/test-evidence-classes.json; .github/workflows/intake-run-validate-test.yml.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import path from 'node:path'

const SKIP = new Set(['node_modules', '.git', 'dist', 'test-results', 'playwright-report', 'tests/fixtures/paste'])
function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name)
    if (SKIP.has(e.name) || SKIP.has(p)) continue
    if (e.isDirectory()) walk(p, out)
    else out.push(p)
  }
  return out
}

test('there is no docs/paste/ folder and no PASTE-*.sql file outside tests/fixtures/paste/', () => {
  expect(fs.existsSync('docs/paste'), 'docs/paste/ must not exist: paste files live in the admin repository').toBe(false)
  const stray = walk('.').filter((p) => /(^|\/)PASTE-[^/]*\.sql$/.test(p))
  expect(stray, 'a PASTE-*.sql file outside tests/fixtures/paste/').toEqual([])
})

test('every fixture paste file is read by a spec, a database fixture, a workflow or the evidence classifier', () => {
  const names = fs.readdirSync('tests/fixtures/paste')
  expect(names.length).toBeGreaterThan(0)
  const readers = [...walk('tests'), ...walk('.github/workflows'), 'scripts/test-evidence-classes.json']
    .filter((p) => /\.(mjs|js|sh|py|ya?ml|json)$/.test(p) && fs.existsSync(p))
    .map((p) => fs.readFileSync(p, 'utf8')).join('\n')
  // a spec that reads a family by prefix (s257: PASTE-20261104-fee-units-holds + suffix) counts for every member of the family
  const unread = names.filter((n) => !readers.includes(n) && !readers.includes(n.replace(/-(containment|correction|interim-stop)(-rollback)?\.sql$/, '')))
  expect(unread, 'a fixture paste file nothing reads belongs in admin docs/paste/ only').toEqual([])
})

test('the readers point at tests/fixtures/paste/, and the rule is written down', () => {
  const cfg = JSON.parse(fs.readFileSync('scripts/test-evidence-classes.json', 'utf8'))
  expect(cfg.executionOverrides).toContain('tests/fixtures/paste/**')
  expect(cfg.executionOverrides).not.toContain('docs/paste/**')
  expect(fs.readFileSync('.github/workflows/intake-run-validate-test.yml', 'utf8')).toContain("'tests/fixtures/paste/PASTE-20261108-iq00313-deakin-intake-withdrawal.sql'")
  const rule = fs.readFileSync('CLAUDE.md', 'utf8')
  expect(rule).toContain('There is no `docs/paste/` folder here, and no new `PASTE-*.sql` is added outside `tests/fixtures/paste/`')
  expect(rule).toContain('cf-247-s616-paste-files-one-source-contract.spec.mjs')
})
