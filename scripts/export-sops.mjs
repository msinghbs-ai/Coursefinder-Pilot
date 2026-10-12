// Writes the versioned SOP documents from src/guide/sops.js (the same words the app shows under Guides).
// Run after changing an SOP: node scripts/export-sops.mjs — then copy docs/sops/*.md to the admin repo (coursefinder-admin docs/sops/).
import fs from 'node:fs'
import { PAGES } from '../src/nav-map.js'
import { SOPS, sopMarkdown } from '../src/guide/sops.js'

const label = (page, tab) => { const p = PAGES[page]; const t = (p?.tabs || []).find((x) => x.key === tab); return [p?.label || page, t?.label].filter(Boolean).join(' › ') }
fs.mkdirSync('docs/sops', { recursive: true })
for (const s of SOPS) { fs.writeFileSync(`docs/sops/${s.id}.md`, sopMarkdown(s, label)); console.log(`docs/sops/${s.id}.md v${s.version}`) }
