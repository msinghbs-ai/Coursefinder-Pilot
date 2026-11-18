#!/usr/bin/env node
// Writes the role guides from src/guide/roleGuides.js (the same words the app shows under Guides › Role guides) to docs/role-guides/<id>.md.
//   node scripts/export-role-guides.mjs                     write docs/role-guides/
//   node scripts/export-role-guides.mjs --check             exit 1 when docs/role-guides/ differs from the source
//   node scripts/export-role-guides.mjs --write-mirror <d>  write the same files into <d> (the admin repository's docs/platform/role-guides)
// One generator only: this script. The pages each role can open come from the menu (src/nav-map.js).
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { ROLE_GUIDES, roleGuideMarkdown } from '../src/guide/roleGuides.js'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
export const files = () => Object.fromEntries(ROLE_GUIDES.map((g) => [`${g.id}.md`, roleGuideMarkdown(g)]))
export const index = () => ['# StudySearch – Role guides', '', 'One guide per role, generated from the Pilot `src/guide/roleGuides.js`; never edited by hand.', '',
  '| Role | Rank | Guide | Version |', '|---|---|---|---|', ...ROLE_GUIDES.map((g) => `| ${g.role} | ${g.rank} | [${g.id}.md](${g.id}.md) | ${g.version} |`), ''].join('\n')

function write(dir) {
  fs.mkdirSync(dir, { recursive: true })
  for (const [f, text] of Object.entries({ ...files(), 'README.md': index() })) fs.writeFileSync(path.join(dir, f), text)
}

const [, , flag, arg] = process.argv
if (import.meta.url === `file://${process.argv[1]}`) {
  const own = path.join(root, 'docs/role-guides')
  if (flag === '--check') {
    const want = { ...files(), 'README.md': index() }
    const bad = Object.entries(want).filter(([f, t]) => !fs.existsSync(path.join(own, f)) || fs.readFileSync(path.join(own, f), 'utf8') !== t).map(([f]) => f)
    if (bad.length) { console.error(`docs/role-guides differs from src/guide/roleGuides.js: ${bad.join(', ')}. Run node scripts/export-role-guides.mjs`); process.exit(1) }
    console.log(`ok: ${Object.keys(want).length} role guide files match`)
  } else if (flag === '--write-mirror') {
    if (!arg) { console.error('--write-mirror needs a folder'); process.exit(1) }
    write(path.resolve(arg)); console.log(`wrote ${ROLE_GUIDES.length + 1} files to ${arg}`)
  } else { write(own); console.log(`wrote ${ROLE_GUIDES.length + 1} files to docs/role-guides`) }
}
