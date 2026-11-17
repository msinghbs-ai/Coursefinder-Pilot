// CF-247 canonical migration squash (Platform Admin 17 Nov 2026; admin docs/platform/MIGRATION-SQUASH-RUNBOOK.md).
// Guards that check "every migration from version X on" list the migrations through this helper, so they keep checking the same files after
// the squash moves applied files from supabase/migrations to supabase/migrations-archive. Before the squash it returns exactly what
// fs.readdirSync('supabase/migrations') returned: the live folder, plus archived files from SQUASH_FROM on (none before the squash).
// The first squash (Pilot #452, 10 Oct 2026) archived everything before SQUASH_FROM; those files stay outside these guards, as before.
import fs from 'node:fs'
import path from 'node:path'

export const LIVE_DIR = 'supabase/migrations'
export const ARCHIVE_DIR = 'supabase/migrations-archive'
export const SQUASH_FROM = '20261010006400' // first migration after the Pilot #452 baseline

const version = (name) => (name.match(/^(\d{14})_/) || [])[1] || ''

// names as fs.readdirSync('supabase/migrations') gave them before the squash (live folder entries plus archived files from SQUASH_FROM on)
export function migrationNames() {
  const live = fs.readdirSync(LIVE_DIR)
  const archived = fs.existsSync(ARCHIVE_DIR)
    ? fs.readdirSync(ARCHIVE_DIR).filter((n) => n.endsWith('.sql') && version(n) >= SQUASH_FROM && !live.includes(n))
    : []
  return [...live, ...archived].sort()
}

// the path of one migration file, wherever it is now
export function migrationPath(name) {
  const base = path.basename(name)
  const live = path.join(LIVE_DIR, base)
  if (fs.existsSync(live)) return live
  const archived = path.join(ARCHIVE_DIR, base)
  if (fs.existsSync(archived)) return archived
  return live // missing everywhere: let the caller's read fail with the live path, as before
}

export function readMigration(name) {
  return fs.readFileSync(migrationPath(name), 'utf8')
}
