// Writes the versioned SOP documents from src/guide/sops.js (the same words the app shows under Guides).
// Run after changing an SOP: node scripts/export-sops.mjs — then copy docs/sops/*.md to the admin repo (coursefinder-admin docs/sops/).
//
// SS-016 UR-03 (Platform Admin 1 Nov 2026 20:08): each document starts with one provenance line (an HTML comment, not shown when the
// Markdown is read): the SOP id and version, the reviewed release, the Pilot commit the export ran from and the sha256 of the content below it.
// Check a copy, for example the admin mirror, without writing anything:
//   node scripts/export-sops.mjs --check-mirror <path to coursefinder-admin/docs/sops>
// It regenerates the documents in memory and lists each mirror file as same, differs, missing or without provenance; it exits 1 on any drift.
// Write the documents into a mirror folder (SS-016 UR-03 ancestor guard, 1 Nov 2026), refusing a stale writer:
//   node scripts/export-sops.mjs --write-mirror <path to coursefinder-admin/docs/sops>
// Before writing anything, each existing mirror file's reviewed release must be this source's or older; for the same release its
// source-commit must be known here and be this HEAD or one of its ancestors (git merge-base --is-ancestor). Pilot merges by squash. An export from an older source over a newer mirror is refused (exit 1), even when the mirror's git push
// would fast-forward; a commit this clone does not know is refused with "fetch first". Nothing is written unless every file passes.
// One generator only: this script. No poller.
import fs from 'node:fs'
import path from 'node:path'
import crypto from 'node:crypto'
import { execFileSync } from 'node:child_process'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { PAGES } from '../src/nav-map.js'
import { SOPS, SOP_REVIEWED_FOR, sopMarkdown } from '../src/guide/sops.js'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const label = (page, tab) => { const p = PAGES[page]; const t = (p?.tabs || []).find((x) => x.key === tab); return [p?.label || page, t?.label].filter(Boolean).join(' › ') }
const sha256 = (s) => crypto.createHash('sha256').update(s, 'utf8').digest('hex')
const PROVENANCE = /^<!-- sop-export: (.*) -->\n/

// The Pilot commit the export ran from; "+local" when the guide sources differ from that commit.
function sourceCommit() {
  try {
    const head = execFileSync('git', ['rev-parse', '--short=12', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim()
    const dirty = execFileSync('git', ['status', '--porcelain', '--', 'src/guide', 'src/nav-map.js'], { cwd: root, encoding: 'utf8' }).trim()
    return dirty ? `${head}+local` : head
  } catch { return 'unknown' }
}

export function sopDocument(s, commit) {
  const body = sopMarkdown(s, label)
  return `<!-- sop-export: id=${s.id}; version=${s.version}; reviewed-release=${SOP_REVIEWED_FOR}; source-commit=${commit}; content-sha256=${sha256(body)} -->\n${body}`
}

// Splits a document into its provenance fields and the content below the provenance line.
export function parseSopDocument(text) {
  const m = PROVENANCE.exec(text)
  if (!m) return { meta: null, body: text }
  const meta = Object.fromEntries(m[1].split('; ').map((kv) => { const i = kv.indexOf('='); return [kv.slice(0, i), kv.slice(i + 1)] }))
  return { meta, body: text.slice(m[0].length) }
}

// Compares every SOP document in `dir` with what src/guide/sops.js generates now. Returns one result per SOP.
export function checkMirror(dir) {
  return SOPS.map((s) => {
    const file = path.join(dir, `${s.id}.md`)
    const want = sopMarkdown(s, label)
    if (!fs.existsSync(file)) return { id: s.id, file, state: 'missing' }
    const { meta, body } = parseSopDocument(fs.readFileSync(file, 'utf8'))
    if (!meta) return { id: s.id, file, state: 'no provenance', detail: 'no sop-export line: copy it again from docs/sops/' }
    const problems = []
    if (body !== want) {
      const a = body.split('\n'), b = want.split('\n'); let i = 0
      while (i < Math.max(a.length, b.length) && a[i] === b[i]) i++
      problems.push(`content differs from line ${i + 2}: mirror "${String(a[i] ?? '').slice(0, 80)}" / source "${String(b[i] ?? '').slice(0, 80)}"`)
    }
    if (meta['content-sha256'] !== sha256(body)) problems.push('content-sha256 does not match the content (edited by hand?)')
    if (meta['content-sha256'] !== sha256(want)) problems.push(`content-sha256 ${String(meta['content-sha256']).slice(0, 12)} is not the source digest ${sha256(want).slice(0, 12)}`)
    if (meta.version !== s.version) problems.push(`version ${meta.version}, source ${s.version}`)
    if (meta['reviewed-release'] !== SOP_REVIEWED_FOR) problems.push(`reviewed-release ${meta['reviewed-release']}, source ${SOP_REVIEWED_FOR}`)
    return { id: s.id, file, state: problems.length ? 'differs' : 'same', detail: problems.join('; '), sourceCommit: meta['source-commit'] }
  })
}

// Compares two release numbers such as 2.15.399; null when either cannot be read.
export function cmpRelease(a, b) {
  const p = (v) => (/^\d+(\.\d+)*$/.test(String(v || '')) ? String(v).split('.').map(Number) : null)
  const x = p(a), y = p(b)
  if (!x || !y) return null
  for (let i = 0; i < Math.max(x.length, y.length); i++) { const d = (x[i] || 0) - (y[i] || 0); if (d) return Math.sign(d) }
  return 0
}

// Checks every existing mirror file before a write. `repo` is the exporting repository, `head` the exporting commit.
// Returns one result per SOP: ok (no file, an unmarked older copy, or an ancestor/equal commit) or refused with the reason.
export function mirrorGuard(dir, { repo = root, head = 'HEAD' } = {}) {
  const git = (args) => { try { execFileSync('git', args, { cwd: repo, stdio: 'ignore' }); return true } catch { return false } }
  return SOPS.map((s) => {
    const file = path.join(dir, `${s.id}.md`)
    if (!fs.existsSync(file)) return { id: s.id, file, ok: true, detail: 'new file' }
    const { meta } = parseSopDocument(fs.readFileSync(file, 'utf8'))
    if (!meta) return { id: s.id, file, ok: true, detail: 'copy without provenance (made before UR-03): replaced' }
    // Pilot merges by squash, so the branch commit a mirror names is never an ancestor of main. The reviewed release decides first
    // (fixed after v2.15.399's first sync was refused); for the same release, the same content passes and
    // commit ancestry decides only between two different exports.
    const rel = cmpRelease(meta['reviewed-release'], SOP_REVIEWED_FOR)
    if (rel === null) return { id: s.id, file, ok: false, detail: `mirror reviewed-release "${meta['reviewed-release']}" cannot be compared; export from a clean checkout and compare by hand` }
    if (rel < 0) return { id: s.id, file, ok: true, detail: `mirror is for v${meta['reviewed-release']}, older than v${SOP_REVIEWED_FOR}` }
    if (rel > 0) return { id: s.id, file, ok: false, detail: `mirror is for v${meta['reviewed-release']}, newer than this source (v${SOP_REVIEWED_FOR}): pull and export from the newer source` }
    if (meta['content-sha256'] === sha256(sopMarkdown(s, label))) return { id: s.id, file, ok: true, detail: `mirror for v${SOP_REVIEWED_FOR} already holds this content` }
    const commit = String(meta['source-commit'] || '').replace(/\+local$/, '')
    if (!/^[0-9a-f]{7,40}$/i.test(commit)) return { id: s.id, file, ok: false, detail: `mirror source-commit "${meta['source-commit']}" cannot be checked; export from a clean checkout and compare by hand` }
    if (!git(['cat-file', '-e', `${commit}^{commit}`])) return { id: s.id, file, ok: false, detail: `mirror was exported from ${commit}, which this clone does not know: git fetch first, then export again` }
    if (!git(['merge-base', '--is-ancestor', commit, head])) return { id: s.id, file, ok: false, detail: `mirror was exported from ${commit}, which is not ${head} or one of its ancestors: this export is older or on another line; pull and export from the newer source` }
    return { id: s.id, file, ok: true, detail: `mirror from ${commit} is ${head} or an ancestor` }
  })
}

function main(argv) {
  const w = argv.indexOf('--write-mirror')
  if (w >= 0) {
    const dir = argv[w + 1]
    if (!dir) { console.error('usage: node scripts/export-sops.mjs --write-mirror <path to docs/sops>'); return 2 }
    if (!fs.existsSync(dir) || !fs.statSync(dir).isDirectory()) { console.error(`not a folder: ${dir}`); return 2 }
    const results = mirrorGuard(dir)
    for (const r of results) console.log(`${(r.ok ? 'ok' : 'refused').padEnd(8)} ${r.file}: ${r.detail}`)
    const refused = results.filter((r) => !r.ok).length
    if (refused) { console.log(`Refused: ${refused} of ${results.length} mirror documents come from a newer or unknown source; nothing was written`); return 1 }
    const commit = sourceCommit()
    for (const s of SOPS) fs.writeFileSync(path.join(dir, `${s.id}.md`), sopDocument(s, commit))
    console.log(`Wrote ${SOPS.length} SOP documents to ${dir} (from ${commit})`)
    return 0
  }
  const at = argv.indexOf('--check-mirror')
  if (at >= 0) {
    const dir = argv[at + 1]
    if (!dir) { console.error('usage: node scripts/export-sops.mjs --check-mirror <path to docs/sops>'); return 2 }
    if (!fs.existsSync(dir) || !fs.statSync(dir).isDirectory()) { console.error(`not a folder: ${dir}`); return 2 }
    const results = checkMirror(dir)
    for (const r of results) console.log(`${r.state.padEnd(13)} ${r.file}${r.sourceCommit ? ` (exported from ${r.sourceCommit})` : ''}${r.detail ? `\n              ${r.detail}` : ''}`)
    const drift = results.filter((r) => r.state !== 'same').length
    console.log(drift ? `${drift} of ${results.length} SOP documents differ from src/guide/sops.js: run node scripts/export-sops.mjs and copy docs/sops/ again` : `All ${results.length} SOP documents match src/guide/sops.js (reviewed for v${SOP_REVIEWED_FOR})`)
    return drift ? 1 : 0
  }
  const commit = sourceCommit()
  fs.mkdirSync(path.join(root, 'docs/sops'), { recursive: true })
  for (const s of SOPS) { fs.writeFileSync(path.join(root, `docs/sops/${s.id}.md`), sopDocument(s, commit)); console.log(`docs/sops/${s.id}.md v${s.version} (reviewed for v${SOP_REVIEWED_FOR}, from ${commit})`) }
  return 0
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) process.exitCode = main(process.argv.slice(2))
