// Guards: Canonical migration squash (Platform Admin 17 Nov 2026 18:02, 18:25 and 23:07; admin docs/platform/MIGRATION-SQUASH-RUNBOOK.md): guards that check every migration from a version on read the migrations through one helper, so the squash moving applied files to supabase/migrations-archive drops no guard; the squash tool moves only applied files from the post-#452 range, repoints their literal paths, can refuse files missing from the production history, and its dry run changes nothing
// CF-247 S594. tests/uat/support/migration-files.mjs and scripts/migration-squash.mjs.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { execFileSync } from 'node:child_process'
import { migrationNames, migrationPath, LIVE_DIR, ARCHIVE_DIR, SQUASH_FROM } from './support/migration-files.mjs'

const TOOL = fs.readFileSync('scripts/migration-squash.mjs', 'utf8')

test('the helper lists the live folder plus files archived from the post-#452 baseline on, and finds a file in either folder', () => {
  const live = fs.readdirSync(LIVE_DIR)
  const archivedSince = fs.readdirSync(ARCHIVE_DIR).filter((n) => n.endsWith('.sql') && n.slice(0, 14) >= SQUASH_FROM && !live.includes(n))
  expect(migrationNames()).toEqual([...live, ...archivedSince].sort())
  expect(SQUASH_FROM).toBe('20261010006400')
  const anyLive = live.find((n) => n.endsWith('.sql'))
  expect(migrationPath(anyLive)).toBe(`${LIVE_DIR}/${anyLive}`)
  const anyOld = fs.readdirSync(ARCHIVE_DIR).find((n) => n.endsWith('.sql'))
  expect(migrationPath(anyOld)).toBe(`${ARCHIVE_DIR}/${anyOld}`)
})

test('the folder-listing guards use the helper, not the live folder alone', () => {
  for (const f of ['cf-247-s42-housekeeping-contract.spec.mjs', 'cf-247-s32-controls-in-settings-contract.spec.mjs', 'cf-247-s57-consumer-api-frozen.spec.mjs']) {
    const s = fs.readFileSync(`tests/uat/${f}`, 'utf8')
    expect(s, f).toContain("from './support/migration-files.mjs'")
    expect(s, f).not.toMatch(/readdirSync\(\s*(MIG_DIR|'supabase\/migrations')\s*\)/)
  }
})

test('the squash tool moves only the post-#452 range up to the cut-off, can check the production history, and its dry run changes nothing', () => {
  expect(TOOL).toContain("const SQUASH_FROM = '20261010006400'")
  expect(TOOL).toContain("version(n) >= SQUASH_FROM && version(n) <= cut")
  expect(TOOL).toContain("refused: ${missing.length} file(s) are not in the production history")
  expect(TOOL).toContain("execFileSync('git', ['mv', path.join(LIVE, n), path.join(ARCHIVE, n)])")
  expect(TOOL).not.toMatch(/live-capture|supabase\.co|database\/query|psql/) // never the baseline files or the database
  const first = fs.readdirSync(LIVE_DIR).filter((n) => /^\d{14}_/.test(n)).sort()[0].slice(0, 14)
  const before = execFileSync('git', ['status', '--porcelain']).toString()
  const out = execFileSync('node', ['scripts/migration-squash.mjs', first, '--dry-run']).toString()
  expect(out).toMatch(new RegExp(`^cut-off ${first}: 1 migration files to move`))
  expect(execFileSync('git', ['status', '--porcelain']).toString()).toBe(before)
})
