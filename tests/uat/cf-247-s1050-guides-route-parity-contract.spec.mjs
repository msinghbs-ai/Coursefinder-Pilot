// Guards: UI/UX Unification & Live Guide Parity Plan v1.2, Slice 4 (Platform Admin brief 24 Nov 2026 15:11): the Role Guides are driven by the live route map (docs/UI-MAP.md): every `Page › Tab` a guide, the Platform guide's role table or an SOP names is a page and tab that exist there, the pages a role is told about are those it can open, no guide carries a typed release banner, and the Counsellor guide matches the Counsellor build.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { ROLE_GUIDES, ROLE_GUIDES_REVIEWED_FOR, pagesFor } from '../../src/guide/roleGuides.js'
import { UI_VERSION } from '../../src/release-manifest.js'

const MAP = fs.readFileSync('docs/UI-MAP.md', 'utf8')
const PAGES = new Map()
let cur = null
for (const l of MAP.split('\n')) {
  let m = l.match(/^### (.+?) — `/); if (m) { cur = m[1]; PAGES.set(cur, []); continue }
  m = l.match(/^#### (.+?) › (.+?) — `/); if (m && PAGES.has(m[1])) PAGES.get(m[1]).push(m[2])
}
const strings = o => typeof o === 'string' ? [o] : Array.isArray(o) ? o.flatMap(strings) : o && typeof o === 'object' ? Object.values(o).flatMap(strings) : []
// every "<Page label> › <Tab>" in the text: the page must be in the map and, when the page has tabs, the words after the arrow must open with one of its tab labels
function unknownRoutes(texts) {
  const labels = [...PAGES.keys()].sort((a, b) => b.length - a.length), bad = new Set()
  for (const s of texts) for (const p of labels) {
    let i = -1
    while ((i = s.indexOf(`${p} › `, i + 1)) >= 0) { const rest = s.slice(i + p.length + 3), tabs = PAGES.get(p); if (tabs.length && !tabs.some(t => rest.startsWith(t))) bad.add(`${p} › ${rest.slice(0, 40)}`) }
  }
  return [...bad]
}

test('the route map is read and the Role Guides name only pages and tabs that exist in it', () => {
  expect(PAGES.size).toBeGreaterThanOrEqual(20); expect(PAGES.get('Layer 4 Review')).toEqual(['Inbox'])
  expect(unknownRoutes(strings(ROLE_GUIDES))).toEqual([])
})

test('every guide link (#address) and page key in every guide source is a live route or a redirected old address in docs/UI-MAP.md', () => {
  const slugs = new Set([...MAP.matchAll(/`#([a-z0-9-]+)/g)].map(m => m[1])), keys = new Set([...MAP.matchAll(/Page key `([a-z0-9]+)`/g)].map(m => m[1]))
  const old = new Set([...MAP.split('## Old addresses')[1].matchAll(/`#?([a-z0-9-]+)/g)].map(m => m[1]))
  expect(keys.size).toBeGreaterThanOrEqual(20)
  for (const f of fs.readdirSync('src/guide').filter(x => x.endsWith('.js'))) {
    const src = fs.readFileSync(`src/guide/${f}`, 'utf8')
    const links = [...src.matchAll(/['"(\s]#([a-z][a-z0-9-]+)/g)].map(m => m[1]).filter(x => !slugs.has(x) && !old.has(x))
    const pageKeys = [...src.matchAll(/\bpage:\s*'([a-z0-9]+)'/g)].map(m => m[1]).filter(x => !keys.has(x))
    expect({ f, links, pageKeys }).toEqual({ f, links: [], pageKeys: [] })
  }
})

test('negative: a made-up tab or page is caught by the same check', () => {
  expect(unknownRoutes(['Open Layer 4 Review › Review by rule: choose the queue'])).toEqual(['Layer 4 Review › Review by rule: choose the queue'])
  expect(unknownRoutes(['Open Layer 4 Review › Inbox, then decide'])).toEqual([])
})

test('every page a role guide lists is one that role can open and is in the map', () => {
  for (const g of ROLE_GUIDES) for (const p of pagesFor(g.rank)) expect(PAGES.has(p.label), `${g.role}: ${p.label}`).toBe(true)
})

test('no typed release banner: the guides are reviewed for the live UI version and no source names v2.16.61', () => {
  expect(ROLE_GUIDES_REVIEWED_FOR).toBe(UI_VERSION)
  for (const f of ['src/guide/roleGuides.js', 'src/guide/platformGuide.js', 'src/guide/sops.js', 'src/RoleGuides.jsx', 'src/ui-v1/GuideView.jsx']) expect(fs.readFileSync(f, 'utf8').split('\n').filter(l => !l.trim().startsWith('//') && !l.includes('release:')).join('\n'), f).not.toMatch(/v?2\.16\.61\b/) // a version table's own release column is history, not a banner
})

test('the Counsellor guide matches the Counsellor build: Report a data issue and My reports', () => {
  const c = ROLE_GUIDES.find(g => g.id === 'counsellor'), cb = fs.readFileSync('src/ui-v1/CounsellorApp.jsx', 'utf8')
  expect(cb).toMatch(/\['reports',\s*'My reports'\]/)
  expect(strings(c).join(' ')).toContain('My reports'); expect(strings(c).join(' ')).toContain('Report a data issue')
})
