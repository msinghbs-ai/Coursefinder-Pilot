// UI map generator (Platform Admin 16 Nov 2026 09:04: "prevent UI instructions and SOPs from drifting behind live screen changes").
// Reads the admin menu (src/nav-map.js: PAGES, SECTIONS, LEGACY), the shell's page switch (pageBody in src/mature-main.jsx) and each
// screen's component source, and writes docs/UI-MAP.md: every live admin route, its top-level tabs, and under each tab the sub-tabs
// (tab lists and view bars), folds (cards and fold-outs) and drawers or dialogs, each with the file it is written in.
// It reads source text only (no build, no browser, no packages), like scripts/test-register.mjs.
//
//   node scripts/ui-map.mjs                      write docs/UI-MAP.md
//   node scripts/ui-map.mjs --check              exit 1 when docs/UI-MAP.md is not what the source gives now (the release line aside)
//   node scripts/ui-map.mjs --stdout             print it, write nothing
//   node scripts/ui-map.mjs --mirror <admin dir> also write <coursefinder-admin>/docs/UI-MAP.md
//
// Rule (CLAUDE.md, "UI map and screen help"): a PR that moves, renames or folds UI controls updates the inline screen help text and
// regenerates this document in the same release; every release bump regenerates it with the test register sync.
// tests/uat/cf-247-s557-ui-map-contract.spec.mjs fails the build when the committed document and the source disagree.
// The generator fails (exit 1) rather than guess: a menu tab with no screen component, or a page case it cannot read, stops it.
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { PAGES, SECTIONS, LEGACY, ROLE_NAMES, hrefFor } from '../src/nav-map.js'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const SRC = path.join(ROOT, 'src')
const OUT = 'docs/UI-MAP.md'
const SHELL = 'mature-main.jsx'
// shared building blocks: not screens, so the walk does not go into them (Card and Overlay are read where they are used)
const KIT = new Set(['ui-kit', 'Card', 'Overlay', 'ExpandList', 'DataTable', 'JobButton', 'SnapshotStamp', 'ProviderLogo'])
const MAX_DEPTH = 6

// ---------- source files, split into top-level declarations ----------
const files = new Map()
function load(file) {
  if (files.has(file)) return files.get(file)
  const full = path.join(SRC, file)
  if (!fs.existsSync(full)) { files.set(file, null); return null }
  const text = fs.readFileSync(full, 'utf8'), lines = text.split('\n')
  const chunks = new Map(), imports = new Map(), consts = new Map()
  const starts = []
  lines.forEach((l, i) => { if (/^(export\s+)?(default\s+)?(async\s+)?(function|const|let|class)\s/.test(l) || /^import[\s{'"]/.test(l)) starts.push(i) })
  let def = null
  starts.forEach((s, n) => {
    const body = lines.slice(s, starts[n + 1] ?? lines.length).join('\n')
    const m = lines[s].match(/^(export\s+)?(default\s+)?(?:async\s+)?(?:function|const|let|class)\s+([A-Za-z_$][\w$]*)/)
    if (!m) return
    if (/^[A-Z]/.test(m[3]) && /^(export\s+)?(default\s+)?(async\s+)?function|=\s*(\(|[\w$]+\s*=>|React\.|memo\(|forwardRef\()/.test(lines[s])) chunks.set(m[3], body)
    if (m[2]) def = m[3]
    // several components written on one line (}function Name(…): each is its own chunk
    const more = [...body.matchAll(/\}function\s+([A-Z]\w*)\s*\(/g)]
    more.forEach((x, k) => { chunks.set(x[1], body.slice(x.index + 1, more[k + 1] ? more[k + 1].index + 1 : body.length)) })
    if (more.length && chunks.has(m[3])) chunks.set(m[3], body.slice(0, more[0].index + 1))
    const c = lines[s].match(/^(?:export\s+)?const\s+([A-Z][A-Z0-9_]*)\s*=\s*(\[.*)$/)
    if (c) consts.set(c[1], body)
  })
  const dm = text.match(/^export\s+default\s+([A-Za-z_$][\w$]*)\s*;?\s*$/m); if (dm && chunks.has(dm[1])) def = dm[1]
  for (const m of text.matchAll(/^import\s*([^'"]*?)\s*from\s*['"](\.\/[^'"]+)['"]/gm)) {
    const target = resolve(m[2]); if (!target) continue
    const d = m[1].match(/^([A-Za-z_$][\w$]*)/); if (d) imports.set(d[1], { file: target, name: 'default' })
    const named = m[1].match(/\{([^}]*)\}/)
    if (named) for (const part of named[1].split(',')) { const [a, b] = part.trim().split(/\s+as\s+/); if (a) imports.set((b || a).trim(), { file: target, name: a.trim() }) }
  }
  for (const m of text.matchAll(/^const\s+([A-Z]\w*)\s*=\s*lazyPage\(\(\)\s*=>\s*import\(['"](\.\/[^'"]+)['"]\)\s*(?:,\s*['"](\w+)['"])?\)/gm)) {
    const target = resolve(m[2]); if (target) imports.set(m[1], { file: target, name: m[3] || 'default' })
  }
  const f = { file, text, chunks, imports, consts, def }
  files.set(file, f)
  return f
}
function resolve(spec) {
  const base = spec.replace(/^\.\//, '')
  for (const ext of ['', '.jsx', '.js']) if (fs.existsSync(path.join(SRC, base + ext)) && fs.statSync(path.join(SRC, base + ext)).isFile()) return base + ext
  return null
}
const isKit = (file) => KIT.has(file.replace(/\.(jsx|js)$/, ''))

// ---------- small text helpers ----------
/** Index just past the bracket that closes the one at `i` ({, ( or [), reading quotes; -1 when it never closes. */
function closeOf(s, i) {
  const open = s[i], close = { '{': '}', '(': ')', '[': ']' }[open]
  let d = 0
  for (let j = i; j < s.length; j++) {
    const c = s[j]
    if (c === '"' || c === '`' || (c === "'" && !/\w/.test(s[j - 1] || ''))) { const e = s.indexOf(c, j + 1); if (e < 0 || (c !== '`' && s.slice(j, e).includes('\n'))) continue; j = e; continue }
    if (c === open) d++
    else if (c === close && --d === 0) return j + 1
  }
  return -1
}
/** Words a person reads from a piece of JSX: expressions become …, tags go. */
function words(jsx) {
  let out = ''
  for (let i = 0; i < jsx.length; i++) {
    if (jsx[i] === '{') { const e = closeOf(jsx, i); if (e < 0) break; const inner = jsx.slice(i + 1, e - 1).trim(); const lit = inner.match(/^(['"])([^'"]*)\1$/); out += lit ? lit[2] : /^\/\*/.test(inner) ? '' : '…'; i = e - 1 } else out += jsx[i]
  }
  return out.replace(/<[^>]*>/g, ' ').replace(/&amp;/g, '&').replace(/\s+/g, ' ').replace(/\s*\([^()]*…[^()]*\)/g, '').replace(/(\s*…)+/g, ' …').replace(/^[\s·:,]+|[\s·:,]+$/g, '').trim()
}
/** The value of attribute `name` in an opening tag's text: a literal as written, an expression as `{…}` code. */
function attr(tag, name) {
  const m = new RegExp(`(?:^|\\s)${name}=`).exec(tag); if (!m) return ''
  const i = m.index + m[0].length
  if (tag[i] === '"') return tag.slice(i + 1, tag.indexOf('"', i + 1))
  if (tag[i] === '{') {
    const e = closeOf(tag, i); if (e < 0) return ''
    const inner = tag.slice(i + 1, e - 1).trim(), lit = inner.match(/^(['"])([^'"]*)\1$/)
    if (lit) return lit[2]
    if (/^</.test(inner)) { const strong = inner.match(/<strong[^>]*>([\s\S]*?)<\/strong>/); return words(strong ? strong[1] : inner) }
    return '`' + (inner.length > 70 ? inner.slice(0, 67) + '…' : inner).replace(/`/g, "'").replace(/\s+/g, ' ') + '`'
  }
  return ''
}
/** The opening tag that starts at `i` (`<Name …>`), reading braces so a `>` inside an expression does not end it. */
function openTag(s, i) {
  for (let j = i + 1; j < s.length; j++) {
    if (s[j] === '{') { const e = closeOf(s, j); if (e < 0) return s.slice(i, i + 400); j = e - 1 } else if (s[j] === '"') { const e = s.indexOf('"', j + 1); if (e < 0) break; j = e } else if (s[j] === '>') return s.slice(i, j + 1)
  }
  return s.slice(i, i + 400)
}
const cell = (s) => String(s).replace(/\|/g, '\\|')

// ---------- what a component's source shows: sub-tabs, folds, drawers ----------
function pairsOf(src) { return [...src.matchAll(/\[\s*(['"])[^'"]*\1\s*,\s*(['"])([^'"]+)\2/g)].map((m) => m[3]) }
function structure(f, body) {
  const out = { subtabs: [], folds: [], drawers: [] }
  // sub-tabs: tab lists, and the view bars (pg-views) that switch what a tab shows
  for (const m of body.matchAll(/<(div|nav)\s[^>]*?(?:role="tablist"|className="pg-views")/g)) {
    const tag = openTag(body, m.index), name = attr(tag, 'aria-label') || 'Views'
    const end = body.indexOf(`</${m[1]}>`, m.index), inner = body.slice(m.index + tag.length, end < 0 ? m.index + 1500 : Math.min(end, m.index + 2500))
    let labels = pairsOf(inner)
    if (!labels.length) { const c = inner.match(/\{\s*([A-Z][A-Z0-9_]*)\s*\.(?:filter\([^)]*\)\s*\.)?map\(/); if (c && f.consts.has(c[1])) labels = pairsOf(f.consts.get(c[1])) }
    if (!labels.length) {
      for (const b of inner.matchAll(/<(button|a)\b/g)) {
        const bt = openTag(inner, b.index), stop = inner.indexOf(`</${b[1]}>`, b.index)
        const text = words(inner.slice(b.index + bt.length, stop < 0 ? undefined : stop)).replace(/\s*…$/, '')
        if (text && text !== '…') labels.push(text)
      }
    }
    const dynamic = /\.map\(/.test(inner) && !pairsOf(inner).length && !/\{\s*[A-Z][A-Z0-9_]*\s*\./.test(inner)
    out.subtabs.push({ name, labels: [...new Set(labels)], dynamic })
  }
  // folds: cards (closed until opened), fold-outs (LazyFold) and details
  for (const m of body.matchAll(/<Card\s/g)) { const tag = openTag(body, m.index); out.folds.push({ kind: 'card', name: attr(tag, 'title') || '(untitled)', id: attr(tag, 'id') }) }
  for (const m of body.matchAll(/<LazyFold\s/g)) { const tag = openTag(body, m.index); out.folds.push({ kind: 'fold', name: attr(tag, 'summary') || '(untitled)', id: attr(tag, 'data') }) }
  for (const m of body.matchAll(/<details\b/g)) {
    const s = body.indexOf('<summary', m.index); if (s < 0 || s - m.index > 600) continue
    const st = openTag(body, s), e = body.indexOf('</summary>', s); if (e < 0) continue
    const raw = body.slice(s + st.length, e), strong = raw.match(/<strong[^>]*>([\s\S]*?)<\/strong>/)
    let name = words(strong ? strong[1] : raw.replace(/<(small|span)\b[^>]*>[\s\S]*?<\/\1>/g, ' ')); if (name.length > 90) name = name.slice(0, 87).trimEnd() + '…'
    if (name && name !== '…') out.folds.push({ kind: 'details', name, id: '' })
  }
  // drawers and dialogs
  for (const m of body.matchAll(/<Overlay\s/g)) { const tag = openTag(body, m.index); out.drawers.push({ kind: attr(tag, 'variant') === 'panel' ? 'panel' : 'drawer', name: [attr(tag, 'eyebrow'), attr(tag, 'title')].filter(Boolean).join(': ') || '(untitled)' }) }
  for (const m of body.matchAll(/<(aside|section|div)\s/g)) {
    const tag = openTag(body, m.index), dialog = /\srole="dialog"/.test(tag)
    const cls = (tag.match(/\sclassName=(?:"([^"]*)"|\{([^}]*)\})/) || []).slice(1).find(Boolean) || ''
    const drawer = /(?:^|[\s"'`])(?:\w+-)?drawer(?=[\s"'`]|$)/.test(cls)
    if (!dialog && !drawer) continue
    const label = attr(tag, 'aria-label')
    out.drawers.push({ kind: drawer ? 'drawer' : 'dialog', name: label || '`' + cls.replace(/`/g, "'") + '`' })
  }
  return out
}

// ---------- the walk from a tab's screen components down through what they draw ----------
function componentsIn(f, body) {
  const seen = new Set(), out = []
  for (const m of body.matchAll(/<([A-Z][\w]*)[\s/>]/g)) {
    const n = m[1]; if (seen.has(n)) continue; seen.add(n)
    if (f.chunks.has(n)) out.push({ name: n, file: f.file, local: n })
    else if (f.imports.has(n)) { const t = f.imports.get(n); if (!isKit(t.file)) out.push({ name: n, file: t.file, local: t.name }) }
  }
  return out
}
function walk(f, body, acc, visited, depth) {
  const st = structure(f, body)
  for (const k of ['subtabs', 'folds', 'drawers']) for (const x of st[k]) acc[k].push({ ...x, file: f.file })
  if (depth >= MAX_DEPTH) return
  for (const c of componentsIn(f, body)) {
    const key = `${c.file}#${c.local}`; if (visited.has(key)) continue; visited.add(key)
    const tf = load(c.file); if (!tf) continue
    const name = c.local === 'default' ? tf.def : c.local
    const tb = name && tf.chunks.get(name); if (!tb) continue
    if (name === 'LazyFold') continue
    walk(tf, tb, acc, visited, depth + 1)
  }
}

// ---------- the shell's page switch: which components each page and tab draws ----------
/** Reads one `case` of pageBody: the top-level JSX elements, each with the tab keys it is drawn for ([] = every tab no condition names). */
function readCase(src) {
  const roots = [], named = new Set()
  const stack = [] // open brackets outside JSX: {ch, tabs?} (tabs: an if(tab===…){ block })
  let ctx = null, pending = null, lastSig = '', lastWord = '', i = 0
  const sig = (t) => { lastSig = t; lastWord = /^\w+$/.test(t) ? t : '' }
  while (i < src.length) {
    const c = src[i], two = src.slice(i, i + 2)
    if (two === '//') { const e = src.indexOf('\n', i); i = e < 0 ? src.length : e; continue }
    if (two === '/*') { const e = src.indexOf('*/', i); i = e < 0 ? src.length : e + 2; continue }
    if (c === '\n') { if (!stack.some((s) => s.ch === '(')) { ctx = null; pending = null } i++; continue }
    if (/\s/.test(c)) { i++; continue }
    if (c === '"' || c === "'" || c === '`') { const e = src.indexOf(c, i + 1); i = e < 0 ? src.length : e + 1; sig('str'); continue }
    const cond = src.slice(i).match(/^tab\s*===\s*(['"])([\w-]+)\1/)
    if (cond) { named.add(cond[2]); pending = lastSig === '||' && pending ? [...pending, cond[2]] : [cond[2]]; i += cond[0].length; sig('cond'); continue }
    if (two === '||' || two === '&&' || two === '=>') { i += 2; sig(two); continue }
    if (c === '<' && /[A-Za-z>]/.test(src[i + 1] || '') && (!/[\w)\]]/.test(lastSig.slice(-1)) || lastWord === 'return' || lastSig === 'cond?')) {
      const e = elementEnd(src, i); if (e < 0) throw new Error('unreadable JSX element')
      const block = [...stack].reverse().find((s) => s.tabs)
      roots.push({ jsx: src.slice(i, e), tabs: ctx || (block && block.tabs) || [] })
      i = e; sig(')'); continue
    }
    if (c === '?') { if (lastSig === 'cond' && pending) { ctx = pending; sig('cond?') } else sig('?'); pending = lastSig === 'cond?' ? null : pending; i++; continue }
    if (c === ':') { if (!stack.some((s) => s.ch !== '{' || !s.block)) ctx = null; i++; sig(':'); continue }
    if (c === ';') { if (!stack.some((s) => s.ch === '(')) { ctx = null; pending = null } i++; sig(';'); continue }
    if (c === '(' || c === '[' || c === '{') {
      const blockTabs = c === '{' && lastSig === ')' && stack.ifTabs ? stack.ifTabs : null
      stack.push({ ch: c, tabs: blockTabs, block: c === '{' && (lastSig === ')' || lastSig === '=>') }); if (blockTabs) { stack.ifTabs = null; ctx = null }
      i++; sig(c); continue
    }
    if (c === ')' || c === ']' || c === '}') {
      const top = stack.pop()
      if (c === ')' && pending && !stack.some((s) => s.ch === '(')) { // the end of if(tab===…): the statement or block that follows is for these tabs
        const rest = src.slice(i + 1).match(/^\s*(\{|return\b)/)
        if (rest && rest[1] === '{') stack.ifTabs = pending; else if (rest) ctx = pending
        pending = null
      }
      if (top && top.tabs) ctx = null
      i++; sig(c); continue
    }
    const w = src.slice(i).match(/^[A-Za-z_$][\w$]*/)
    if (w) { i += w[0].length; sig(w[0]); continue }
    i++; sig(c)
  }
  return { roots, named }
}
/** Index just past the JSX element that starts at `i`. */
function elementEnd(s, i) {
  let depth = 0, j = i
  while (j < s.length) {
    if (s[j] === '{') { const e = closeOf(s, j); if (e < 0) return -1; j = e; continue }
    if (s[j] !== '<') { j++; continue }
    const closing = s[j + 1] === '/'
    const tag = openTag(s, j); j += tag.length
    if (closing) { if (--depth === 0) return j } else if (!/\/>$/.test(tag)) depth++; else if (depth === 0) return j
  }
  return -1
}
function pageCases() {
  const shell = load(SHELL), body = shell.chunks.get('Page')
  const at = body.indexOf('function pageBody()'); if (at < 0) throw new Error('pageBody() not found in ' + SHELL)
  const sw = body.slice(at), marks = [...sw.matchAll(/^\s*case\s*'([\w-]+)'\s*:/gm)]
  if (!marks.length) throw new Error('no page cases found in pageBody()')
  const out = new Map()
  marks.forEach((m, n) => {
    let text = sw.slice(m.index + m[0].length, marks[n + 1]?.index ?? sw.length)
    if (n === marks.length - 1) { const d = text.search(/^\s*default\s*:/m); if (d >= 0) text = text.slice(0, d) }
    out.set(m[1], text)
  })
  return out
}

// ---------- the document ----------
export function build() {
  const shell = load(SHELL), cases = pageCases(), problems = []
  const version = (fs.readFileSync(path.join(SRC, 'release-manifest.js'), 'utf8').match(/UI_VERSION\s*=\s*'([^']+)'/) || [])[1] || 'unknown'
  const L = [], count = { pages: 0, tabs: 0, subtabs: 0, folds: 0, drawers: 0 }
  const role = (n) => ROLE_NAMES[n] || `rank ${n}`
  const shape = (pageKey, tabKey, roots) => {
    const acc = { subtabs: [], folds: [], drawers: [] }, visited = new Set(), top = []
    for (const r of roots) {
      for (const c of componentsIn(shell, r.jsx)) if (c.name !== 'LazyFold' && !top.some((t) => t.name === c.name)) top.push(c)
      walk(shell, r.jsx, acc, visited, 0)
    }
    if (!top.length) problems.push(`${pageKey}${tabKey ? ' › ' + tabKey : ''}: no screen component found in pageBody()`)
    const lines = [`- **Screen:** ${top.map((c) => `\`${c.name}\` (${c.file})`).join(', ') || 'none found'}`]
    const uniq = (list, key) => { const s = new Set(); return list.filter((x) => { const k = key(x); if (s.has(k)) return false; s.add(k); return true }) }
    const subs = uniq(acc.subtabs, (x) => `${x.name}|${x.file}`), folds = uniq(acc.folds, (x) => `${x.kind}|${x.name}|${x.file}`), drawers = uniq(acc.drawers, (x) => `${x.kind}|${x.name}|${x.file}`)
    count.subtabs += subs.length; count.folds += folds.length; count.drawers += drawers.length
    if (subs.length) { lines.push('- **Sub-tabs and view bars:**'); for (const s of subs) lines.push(`  - ${s.name}: ${s.labels.length ? s.labels.join(' · ') : s.dynamic ? '(drawn from data)' : '(labels not in source)'}${s.dynamic && s.labels.length ? ' · (more drawn from data)' : ''} — ${s.file}`) }
    if (folds.length) { lines.push('- **Folds:**'); for (const x of folds) lines.push(`  - ${x.name} (${x.kind}${x.id ? `, \`${String(x.id).replace(/`/g, '')}\`` : ''}) — ${x.file}`) }
    if (drawers.length) { lines.push('- **Drawers and dialogs:**'); for (const x of drawers) lines.push(`  - ${x.name} (${x.kind}) — ${x.file}`) }
    return lines
  }
  for (const section of SECTIONS) {
    L.push(`## ${section.label || 'Overview'}`, '')
    for (const key of section.pages) {
      const p = PAGES[key]; count.pages++
      const text = cases.get(key)
      L.push(`### ${p.label} — \`#${p.slug}\``, '', `Page key \`${key}\` · opens for ${role(p.min)} and above${p.tabs ? ` · ${p.tabs.length} tab${p.tabs.length === 1 ? '' : 's'}` : ' · no tabs'}`, '')
      if (text == null) { problems.push(`${key}: no case in pageBody()`); continue }
      let read; try { read = readCase(text) } catch (e) { problems.push(`${key}: ${e.message}`); continue }
      if (!p.tabs) { count.tabs++; L.push(...shape(key, '', read.roots), ''); continue }
      for (const t of p.tabs) {
        count.tabs++
        const roots = read.roots.filter((r) => r.tabs.includes(t.key) || (!r.tabs.length && !read.named.has(t.key)))
        L.push(`#### ${p.label} › ${t.label} — \`${hrefFor(key, t.key)}\``, '', `Tab key \`${t.key}\` · ${role(t.min)} and above${t.hidden ? ' · hidden from the tab row' : ''}`, '', ...shape(key, t.key, roots), '')
      }
      for (const k of read.named) if (!p.tabs.some((t) => t.key === k)) problems.push(`${key}: pageBody() names tab '${k}', which the menu does not have`)
    }
  }
  for (const key of Object.keys(PAGES)) if (!SECTIONS.some((s) => s.pages.includes(key))) problems.push(`${key}: a page in PAGES that no menu section lists`)
  const legacy = Object.entries(LEGACY).map(([slug, t]) => `| \`#${slug}\` | ${cell(PAGES[t.page]?.label || t.page)}${t.tab ? ' › ' + cell((PAGES[t.page]?.tabs || []).find((x) => x.key === t.tab)?.label || t.tab) : ''}${t.set ? ` (${Object.entries(t.set).map(([k, v]) => `${k}=${v}`).join(', ')})` : ''} |`)
  const head = [
    '# StudySearch Admin – UI map (generated)', '',
    `<!-- ui-map: release ${version} -->`,
    `**Generated by \`node scripts/ui-map.mjs\` from the Pilot source at release v${version}. Do not edit by hand.**`, '',
    'Every live admin route and top-level tab comes from the menu (`src/nav-map.js`); the screen under each tab comes from the page switch (`pageBody` in `src/mature-main.jsx`); sub-tabs, folds and drawers come from each screen\'s component source, followed through the components it draws. A name in `code` is worked out when the screen runs (for example one card per service); "…" stands for a count or value shown beside the name.', '',
    '**Rule (Platform Admin 16 Nov 2026):** a PR that moves, renames or folds UI controls updates the inline screen help text and regenerates this document in the same release. Every release bump regenerates it with the test register sync, and it is mirrored to `coursefinder-admin` `docs/UI-MAP.md`. Spec `cf-247-s557-ui-map-contract` fails the build when this document and the source disagree. What each screen shows and does, in words, is in the admin `docs/platform/UI-CATALOGUE.md` and the in-app Guides.', '',
    `**Counts:** ${count.pages} pages · ${count.tabs} tabs (a page without tabs counts as one) · ${count.subtabs} sub-tab or view bars · ${count.folds} folds · ${count.drawers} drawers and dialogs · ${legacy.length} old addresses.`, '',
    'Roles (rank): ' + Object.entries(ROLE_NAMES).map(([n, r]) => `${n} ${r}`).join(' · ') + '.', '', '---', '',
  ]
  const tail = ['---', '', '## Old addresses (still open, redirected by `resolveTarget`)', '', '| Old address | Opens |', '|---|---|', ...legacy, '', 'Old tab addresses inside a page (for example `#coverage?tab=progress`) are redirected in `resolveTarget` in `src/nav-map.js`.', '']
  return { text: [...head, ...L, ...tail].join('\n'), problems, count, version }
}
/** The document without its release lines, for comparing structure only. */
export const structureOnly = (md) => md.split('\n').filter((l) => !/^<!-- ui-map: release /.test(l) && !/^\*\*Generated by /.test(l)).join('\n')

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2), { text, problems, count, version } = build()
  if (problems.length) { console.error('ui-map: cannot map these, so nothing was written:\n  ' + problems.join('\n  ')); process.exit(1) }
  const target = path.join(ROOT, OUT)
  if (args.includes('--stdout')) process.stdout.write(text)
  else if (args.includes('--check')) {
    const have = fs.existsSync(target) ? fs.readFileSync(target, 'utf8') : ''
    if (structureOnly(have) !== structureOnly(text)) { console.error(`ui-map: ${OUT} is behind the source. Run: node scripts/ui-map.mjs`); process.exit(1) }
    console.log(`ui-map: ${OUT} matches the source (${count.pages} pages, ${count.tabs} tabs).`)
  } else {
    fs.writeFileSync(target, text)
    console.log(`ui-map: wrote ${OUT} at v${version}: ${count.pages} pages, ${count.tabs} tabs, ${count.subtabs} sub-tab bars, ${count.folds} folds, ${count.drawers} drawers and dialogs.`)
    const m = args.indexOf('--mirror')
    if (m >= 0) {
      const dir = args[m + 1]; if (!dir || !fs.existsSync(path.join(dir, 'docs'))) { console.error('ui-map: --mirror needs the coursefinder-admin folder (it must have docs/)'); process.exit(1) }
      fs.writeFileSync(path.join(dir, OUT), text); console.log(`ui-map: mirrored to ${path.join(dir, OUT)}`)
    }
  }
}
