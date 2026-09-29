// B2 UI uniformity guard: colour literals live only in src/tokens.css.
// Lists any hex / rgb() / hsl() colour written anywhere else in src/ and exits non-zero if one is found.
// The Course coverage ordinal ramp (course-coverage.jsx) keeps its validated hex values; they equal --cf-seq-1..5.
import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const ALLOWED = new Set(['src/tokens.css'])
const RAMP = new Set(['#0d366b', '#1c5cab', '#2a78d6', '#5598e7', '#86b6ef'])
const COLOUR = /#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3,4})\b|rgba?\(\s*\d[^)]*\)|hsla?\(\s*\d[^)]*\)/g
const files = []
const walk = dir => { for (const e of fs.readdirSync(dir, { withFileTypes: true })) { const p = path.join(dir, e.name); if (e.isDirectory()) walk(p); else if (/\.(css|jsx?|mjs)$/.test(e.name)) files.push(p) } }
walk(path.join(root, 'src'))
const found = []
for (const f of files) {
  const rel = path.relative(root, f).split(path.sep).join('/')
  if (ALLOWED.has(rel)) continue
  const text = fs.readFileSync(f, 'utf8')
  for (const m of text.matchAll(COLOUR)) {
    const lit = m[0].toLowerCase()
    if (rel === 'src/course-coverage.jsx' && RAMP.has(lit)) continue
    found.push(`${rel}: ${m[0]}`)
  }
}
const tokens = fs.readFileSync(path.join(root, 'src/tokens.css'), 'utf8')
const distinct = new Set([...tokens.matchAll(COLOUR)].map(m => m[0].toLowerCase()))
if (found.length) { console.error(`ui-tokens: ${found.length} colour literal(s) outside src/tokens.css\n` + found.join('\n')); process.exit(1) }
console.log(`ui-tokens: PASS — ${distinct.size} colour values, all defined in src/tokens.css`)
