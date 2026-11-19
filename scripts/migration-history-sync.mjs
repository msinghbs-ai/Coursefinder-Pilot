#!/usr/bin/env node
// CF-247 S1-Build (Platform Admin 19 Nov 2026 23:10, "Sync migration from supabase to repo so they are same"): makes the repository hold one
// file for every version in production's supabase_migrations.schema_migrations, with the exact text that was applied.
// Input: a JSON-lines export of the history (version, name, statements), read only through the Management API by the export workflow.
// For each history version:
//   - a file of that version already in supabase/migrations, supabase/migrations-archive or supabase/held: kept as it is; its content is
//     compared (carriage returns and trailing newlines ignored) and the result is written to the manifest;
//   - no file of that version: the applied text is written to supabase/migrations-archive/<version>_<name>.sql (statements joined by a newline,
//     exactly as stored; the archive is never applied, Deploy on merge reads supabase/migrations only).
// Files that have no history version are left where they are and listed in the manifest (with the history version holding the same text, if any).
// Nothing in the database is changed. --scan refuses to write when an applied text looks like it holds a key or password (the repository is public).
// Usage: node scripts/migration-history-sync.mjs <history.jsonl> [--write] [--scan]
import fs from 'node:fs'
import path from 'node:path'
import crypto from 'node:crypto'

const [src, ...flags] = process.argv.slice(2)
if (!src) { console.error('usage: migration-history-sync.mjs <history.jsonl> [--write] [--scan]'); process.exit(2) }
const write = flags.includes('--write'), scan = flags.includes('--scan')
const DIRS = ['supabase/migrations', 'supabase/migrations-archive', 'supabase/held']
const norm = (t) => t.replace(/\r/g, '').replace(/\n+$/, '')
const md5 = (t) => crypto.createHash('md5').update(norm(t)).digest('hex')
const SECRETS = [/eyJ[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{15,}\./, /\bsk-(or-|proj-)?[A-Za-z0-9_-]{20,}/, /\bsk_live_[A-Za-z0-9]{10,}/, /\bfc-[a-f0-9]{24,}/,
  /\bre_[A-Za-z0-9]{8}_[A-Za-z0-9]{16,}/, /\bAKIA[0-9A-Z]{16}\b/, /\bxox[bpa]-[A-Za-z0-9-]{10,}/, /\bghp_[A-Za-z0-9]{30,}/, /\bsbp_[a-f0-9]{30,}/,
  /password\s*(=|:=|:)\s*'[^']{6,}'/i, /Bearer\s+[A-Za-z0-9._-]{30,}/]

const rows = fs.readFileSync(src, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l))
const files = new Map() // version -> [{path, md5}]
const byMd5 = new Map() // md5 -> [path]
for (const d of DIRS) {
  if (!fs.existsSync(d)) continue
  for (const f of fs.readdirSync(d)) {
    const m = /^(\d{14})_.*\.sql$/.exec(f); if (!m) continue
    const p = `${d}/${f}`, h = md5(fs.readFileSync(p, 'utf8'))
    files.set(m[1], [...(files.get(m[1]) || []), { path: p, md5: h }])
    byMd5.set(h, [...(byMd5.get(h) || []), p])
  }
}
const seen = new Set(), out = [], hits = [], add = []
for (const r of rows) {
  const v = String(r.version), text = (r.statements || []).join('\n'), h = md5(text)
  seen.add(v)
  const have = files.get(v)
  if (have) { out.push([v, have.map((x) => x.path).join(' '), h, have.some((x) => x.md5 === h) ? 'same-version-same-text' : 'same-version-text-differs']); continue }
  if (scan) for (const re of SECRETS) if (re.test(text)) hits.push(`${v} ${re.source.slice(0, 24)}`)
  const safe = String(r.name || 'applied').toLowerCase().replace(/[^a-z0-9_]+/g, '_').replace(/^_+|_+$/g, '').slice(0, 90) || 'applied'
  const p = `supabase/migrations-archive/${v}_${safe}.sql`
  add.push([p, text.endsWith('\n') ? text : text + '\n'])
  out.push([v, p, h, (byMd5.get(h) ? `added-from-history (same text as ${byMd5.get(h).join(' ')})` : 'added-from-history')])
}
const orphans = []
for (const [v, list] of files) if (!seen.has(v)) for (const x of list) orphans.push([v, x.path, x.md5, 'file-without-history-version'])
const tally = (k) => out.filter((x) => x[3].startsWith(k)).length
console.log(`history rows ${rows.length}; already in the repository with the same text ${tally('same-version-same-text')}; same version, different text ${tally('same-version-text-differs')}; written from history ${add.length}; repository files with no history version ${orphans.length}`)
if (hits.length) { console.log(`REFUSED: ${hits.length} applied texts look like they hold a key or password:\n${hits.join('\n')}`); process.exit(3) }
if (write) {
  for (const [p, t] of add) fs.writeFileSync(p, t)
  const head = 'version\tpath\ttext_md5\tstatus\n'
  fs.mkdirSync('supabase/migration-history', { recursive: true })
  fs.writeFileSync('supabase/migration-history/MANIFEST.tsv', head + [...out, ...orphans].sort((a, b) => a[0].localeCompare(b[0]) || a[1].localeCompare(b[1])).map((x) => x.join('\t')).join('\n') + '\n')
  console.log(`wrote ${add.length} files and supabase/migration-history/MANIFEST.tsv`)
}
