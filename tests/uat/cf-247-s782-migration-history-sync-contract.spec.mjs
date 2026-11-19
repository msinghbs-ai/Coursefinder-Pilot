// Guards: Platform Admin 19 Nov 2026 23:10 AEDT (chat S1-Build, s782): "Sync migration from supabase to repo so they are same". Every version in production's migration history has its applied text in the repository (an existing file with the same text, or supabase/migration-history/applied/), listed in MANIFEST.tsv with its md5; nothing in that folder is ever applied; the sync workflow reads production with read-only queries and refuses texts that look like keys.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import crypto from 'node:crypto'

const DIR = 'supabase/migration-history'
const norm = (t) => t.replace(/\r/g, '').replace(/\n+$/, '')
const md5 = (p) => crypto.createHash('md5').update(norm(fs.readFileSync(p, 'utf8'))).digest('hex')
const rows = fs.readFileSync(`${DIR}/MANIFEST.tsv`, 'utf8').trim().split('\n')
const head = rows.shift()
const M = rows.map((l) => { const [version, path, md, status] = l.split('\t'); return { version, path, md, status } })
const history = M.filter((r) => r.status !== 'file-without-history-version')

test('the manifest lists every history version once, up to at least the head at the first sync', () => {
  expect(head).toBe('version\tpath\ttext_md5\tstatus')
  const v = history.map((r) => r.version)
  expect(new Set(v).size).toBe(v.length)
  expect(v.length).toBeGreaterThanOrEqual(2194)
  expect(v.slice().sort().at(-1) >= '20261119182000').toBe(true)
  for (const r of M) expect(r.status, r.version).toMatch(/^(same-version-same-text|no-file-of-this-version|applied-text-differs-from |file-without-history-version)/)
})

test('each history version points at a file whose text has the recorded md5', () => {
  for (const r of history) {
    const p = r.path.split(' ').find((x) => fs.existsSync(x) && md5(x) === r.md)
    expect(p, `${r.version}: no file with the applied text`).toBeTruthy()
    if (r.status !== 'same-version-same-text') expect(r.path, r.version).toMatch(/^supabase\/migration-history\/applied\/\d{14}_[a-z0-9_]+\.sql$/)
  }
})

test('every file in applied/ is in the manifest', () => {
  const listed = new Set(history.map((r) => r.path))
  for (const f of fs.readdirSync(`${DIR}/applied`)) expect(listed.has(`${DIR}/applied/${f}`), f).toBe(true)
})

test('nothing applies the history folder; the sync workflow is read only and refuses key-like texts', () => {
  const deploy = fs.readFileSync('.github/workflows/deploy-on-merge.yml', 'utf8')
  expect(deploy).toContain("- 'supabase/migrations/*.sql'")
  expect(deploy).not.toContain('migration-history')
  expect(fs.readFileSync('scripts/ci/apply-migration.sh', 'utf8')).toContain('f="supabase/migrations/$FILE"')
  const wf = fs.readFileSync('.github/workflows/db-migration-history-sync.yml', 'utf8')
  expect(wf).toContain('workflow_dispatch:')
  expect(wf).not.toMatch(/^\s+(schedule|push|pull_request):/m)
  expect(wf).toContain("'{query:$q, read_only:true}'")
  expect(wf).not.toMatch(/\b(insert|update|delete|drop|truncate|alter)\b[^\n]*schema_migrations/i)
  expect(wf).toContain('--scan --write')
  const script = fs.readFileSync('scripts/migration-history-sync.mjs', 'utf8')
  expect(script).toContain("process.exit(3)")
  expect(script).toContain("supabase/migration-history/applied/")
  expect(script).not.toMatch(/writeFileSync\(`supabase\/(migrations|migrations-archive|held)\//)
})
