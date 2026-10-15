// CF-247 Decision 260: collects what the database cannot see for the component register — the edge functions and screens in the
// repository, and edge function calls from the logs — as one JSON payload for security.component_register_ingest_v1.
// Usage: node scripts/component-register-collect.mjs <edge-calls.json from the logs API> > payload.json
import fs from 'node:fs'
import { PAGES } from '../src/nav-map.js'

const FN_DIR = 'supabase/functions'
const firstComment = (file) => {
  if (!fs.existsSync(file)) return ''
  for (const line of fs.readFileSync(file, 'utf8').split('\n').slice(0, 40)) {
    const m = line.match(/^\s*\/\/\s*(.+)$/)
    if (m && !/^(deno-lint|@ts-|eslint)/.test(m[1])) return m[1].trim().slice(0, 300)
  }
  return ''
}

export function collect(edgeCallsRaw) {
  const edge_functions = fs.readdirSync(FN_DIR, { withFileTypes: true })
    .filter((d) => d.isDirectory() && !d.name.startsWith('_'))
    .map((d) => ({ name: d.name, purpose: firstComment(`${FN_DIR}/${d.name}/index.ts`) }))
  const screens = []
  for (const [key, p] of Object.entries(PAGES)) {
    if (!p || !p.label) continue
    screens.push({ name: p.label, page: p.label, purpose: p.subtitle || '' })
    for (const t of p.tabs || []) if (t && t.label) screens.push({ name: `${p.label} › ${t.label}`, page: p.label, purpose: '' })
  }
  const rows = Array.isArray(edgeCallsRaw?.result) ? edgeCallsRaw.result : []
  const edge_calls = rows.filter((r) => r && r.fn).map((r) => ({ name: r.fn, calls: Number(r.n) || 0, last: String(r.last).replace(' ', 'T').replace(/(\.\d+)?$/, 'Z') }))
  return { edge_functions, screens, edge_calls }
}

if (process.argv[1] && process.argv[1].endsWith('component-register-collect.mjs')) {
  const raw = process.argv[2] && fs.existsSync(process.argv[2]) ? JSON.parse(fs.readFileSync(process.argv[2], 'utf8') || '{}') : {}
  process.stdout.write(JSON.stringify(collect(raw)))
}
