#!/usr/bin/env node
// CF-247 canonical migration squash tool (Platform Admin 17 Nov 2026; admin docs/platform/MIGRATION-SQUASH-RUNBOOK.md, based on Pilot #452).
//
//   node scripts/migration-squash.mjs <cut-off version> [--history <file>] [--dry-run]
//
// Moves every supabase/migrations/<v>_*.sql with SQUASH_FROM <= v <= cut-off to supabase/migrations-archive/ (git mv, so history follows),
// then rewrites every literal reference "supabase/migrations/<moved file>" under tests/, scripts/, src/, docs/ and .github/ to
// "supabase/migrations-archive/<moved file>". Guards that list the folder already read both folders through
// tests/uat/support/migration-files.mjs, so no assertion changes.
// --history: a file with one applied version per line (read only from production's supabase_migrations.schema_migrations); the tool refuses
// if a file to move is not in it (nothing unapplied is ever archived). --dry-run prints what would change and changes nothing.
// It never touches the database, the baseline files or a migration file's content.
import fs from 'node:fs'
import path from 'node:path'
import { execFileSync } from 'node:child_process'

const LIVE = 'supabase/migrations'
const ARCHIVE = 'supabase/migrations-archive'
const SQUASH_FROM = '20261010006400'
const ROOTS = ['tests', 'scripts', 'src', 'docs', '.github']
const TEXT = /\.(mjs|js|jsx|ts|tsx|json|md|sql|sh|yml|yaml|py|txt|csv)$/

const args = process.argv.slice(2)
const cut = args.find((a) => /^\d{14}$/.test(a))
const dry = args.includes('--dry-run')
const hIdx = args.indexOf('--history')
if (!cut) { console.error('usage: node scripts/migration-squash.mjs <cut-off version (14 digits)> [--history <file>] [--dry-run]'); process.exit(2) }

const version = (n) => (n.match(/^(\d{14})_/) || [])[1] || ''
const moving = fs.readdirSync(LIVE).filter((n) => n.endsWith('.sql') && version(n) >= SQUASH_FROM && version(n) <= cut).sort()
if (moving.length === 0) { console.error(`nothing to move at or below ${cut}`); process.exit(1) }

if (hIdx >= 0) {
  const applied = new Set(fs.readFileSync(args[hIdx + 1], 'utf8').split(/\r?\n/).map((s) => s.trim()).filter(Boolean))
  const missing = moving.filter((n) => !applied.has(version(n)))
  if (missing.length) { console.error(`refused: ${missing.length} file(s) are not in the production history:\n${missing.join('\n')}`); process.exit(1) }
}
const clash = moving.filter((n) => fs.existsSync(path.join(ARCHIVE, n)))
if (clash.length) { console.error(`refused: already in ${ARCHIVE}:\n${clash.join('\n')}`); process.exit(1) }

// every text file under the roots that names a moved file by its live path
const walk = (d, out = []) => {
  if (!fs.existsSync(d)) return out
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    if (e.name === 'node_modules' || e.name.startsWith('.git') && e.name !== '.github') continue
    const p = path.join(d, e.name)
    if (e.isDirectory()) walk(p, out); else if (TEXT.test(e.name)) out.push(p)
  }
  return out
}
const movingSet = new Set(moving)
const ref = /supabase\/migrations\/(\d{14}_[A-Za-z0-9_]+\.sql)/g
let filesChanged = 0, refsChanged = 0
const edits = []
for (const f of ROOTS.flatMap((r) => walk(r))) {
  const before = fs.readFileSync(f, 'utf8')
  let n = 0
  const after = before.replace(ref, (m, name) => (movingSet.has(name) ? (n++, `${ARCHIVE}/${name}`) : m))
  if (n) { filesChanged++; refsChanged += n; edits.push([f, after, n]) }
}

console.log(`cut-off ${cut}: ${moving.length} migration files to move (${moving[0]} .. ${moving[moving.length - 1]}); ` +
  `${refsChanged} references in ${filesChanged} files to repoint`)
if (dry) { for (const [f, , n] of edits) console.log(`  ${n}\t${f}`); process.exit(0) }

for (const n of moving) execFileSync('git', ['mv', path.join(LIVE, n), path.join(ARCHIVE, n)])
for (const [f, after] of edits) fs.writeFileSync(f, after)
const left = fs.readdirSync(LIVE).filter((n) => n.endsWith('.sql') && version(n) <= cut)
if (left.length) { console.error(`post-check: ${left.length} file(s) at or below ${cut} still in ${LIVE}`); process.exit(1) }
console.log('done')
