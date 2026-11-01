// Test register generator (CF-247 test governance, Platform Admin 26 Oct 2026). Reads every spec in tests/uat: its "// Guards:" line,
// its tests (source contract or browser), its tags, the PR that added it (git) and, when uat-artifacts/results.json exists, the status
// of its last local run. Writes the register as markdown to stdout. The register is published as admin docs/platform/TEST-REGISTER.md;
// a PR that adds or removes a test regenerates it in the same change (doc-as-code).
// Usage: node scripts/test-register.mjs > /tmp/TEST-REGISTER.md
import fs from 'node:fs'
import { execFileSync } from 'node:child_process'

const DIR = 'tests/uat'
// standing rules (CLAUDE.md and decisions that apply to every change); a spec whose Guards line starts with one of these is a rule guard
export const STANDING = ['G1', 'G2', 'G3', 'G4', 'Housekeeping', 'Website API v2', 'Release contract']
const TEST = /(?<![\w.])test(?:\.only|\.skip|\.fixme)?\(\s*(['"`])((?:\\.|(?!\1).)*)\1\s*,\s*(?:\{[^}]*\}\s*,\s*)?(?:async\s*)?(?:function\s*)?\(([^)]*)\)/gs

export function specInfo(file, src) {
  const guards = (src.match(/^\/\/ Guards: (.+)$/m) || [])[1] || ''
  const tests = [...src.matchAll(TEST)].map((m) => ({ title: m[2], browser: m[3].includes('page') }))
  const deployed = /@deployed\b/.test(src)
  const responsive = /@responsive\b/.test(src)
  const kind = STANDING.some((s) => guards.startsWith(s)) ? 'rule' : deployed ? 'deployed' : 'regression'
  return { file, id: file.replace(/\.spec\.mjs$/, ''), guards, tests, deployed, responsive, kind }
}

// SS-016 UR-16 (Platform Admin 1 Nov 2026 22:01): every count in the register comes from this one pass over the collected tests, so the
// category table and the narrative cannot disagree (the 1 Nov register said 89 deployed in the table and 92 in the text: three @deployed
// tests sit in rule or regression specs). It throws when the parts do not add up.
export function summarise(specs) {
  const isLive = (t) => /@live-acting\b/.test(t.title), isPhone = (t) => /@responsive\b/.test(t.title)
  const part = (list) => {
    const all = list.flatMap((s) => s.tests)
    return { specs: list.length, tests: all.length, local: all.filter((t) => !t.deployed).length, deployed: all.filter((t) => t.deployed).length }
  }
  const byKind = Object.fromEntries(['rule', 'regression', 'deployed'].map((k) => [k, part(specs.filter((s) => s.kind === k))]))
  const total = part(specs), all = specs.flatMap((s) => s.tests)
  const out = { byKind, total, live: all.filter(isLive).length, phone: all.filter(isPhone).length }
  out.safeDeployed = total.deployed - out.live
  const sum = (f) => Object.values(byKind).reduce((x, k) => x + k[f], 0)
  for (const f of ['specs', 'tests', 'local', 'deployed']) {
    if (sum(f) !== total[f]) throw new Error(`test register: ${f} by category (${sum(f)}) does not equal the total (${total[f]})`)
  }
  if (total.local + total.deployed !== total.tests) throw new Error(`test register: local (${total.local}) + deployed (${total.deployed}) is not ${total.tests}`)
  return out
}

export function summaryLines(sum) {
  const row = (label, k) => `| ${label} | ${k.specs} | ${k.tests} | ${k.local} | ${k.deployed} |`
  return [
    '| Category | Specs | Tests | Local suite | Deployed track |', '|---|---|---|---|---|',
    row('Rule guards (standing rules)', sum.byKind.rule),
    row('Regression guards (one decision or change each)', sum.byKind.regression),
    row('Deployed specs (run against the live site by deployed-uat)', sum.byKind.deployed),
    `| **Total** | **${sum.total.specs}** | **${sum.total.tests}** | **${sum.total.local}** | **${sum.total.deployed}** |`, '',
    `Local suite (\`--grep-invert @deployed\`): ${sum.total.local} tests, one run each (desktop; phone only for \`@responsive\`). Phone-width tests (\`@responsive\`, phone project only): ${sum.phone}. Deployed track: ${sum.total.deployed} tests (${sum.byKind.deployed.deployed} in deployed specs, ${sum.total.deployed - sum.byKind.deployed.deployed} tagged \`@deployed\` inside rule or regression specs), desktop plus the phone gate; ${sum.live} of them act on the live site (\`@live-acting\`) and run only when the live-acting switch is on (default off), so ${sum.safeDeployed} safe tests run each week.`,
  ]
}

function addedBy() {
  const out = {}
  const log = execFileSync('git', ['log', '--diff-filter=A', '--name-only', '--format=@@%h|%ad|%s', '--date=short', '--', DIR], { encoding: 'utf8' })
  let cur = null
  for (const l of log.split('\n')) {
    if (l.startsWith('@@')) cur = l.slice(2).split('|')
    else if (l.startsWith(DIR + '/') && cur) out[l.slice(DIR.length + 1)] = cur // newest first: the last one seen is the commit that added it
  }
  return out
}

// the tests Playwright actually collects (one project), by file and line; a test is a browser test when its callback takes `page`
function listed() {
  const out = {}, seen = new Set()
  const d = JSON.parse(execFileSync('npx', ['playwright', 'test', '--list', '--reporter=json'], { encoding: 'utf8', maxBuffer: 64 << 20 }))
  // tags in a describe title apply to every test inside it
  const walk = (s, chain = '') => {
    for (const sp of s.specs || []) {
      if (seen.has(`${sp.file}:${sp.line}:${sp.title}`)) continue  // the list repeats each test once per project
      seen.add(`${sp.file}:${sp.line}:${sp.title}`)
      const full = `${chain} ${sp.title}`
      ;(out[sp.file] ||= []).push({ title: full.trim(), line: sp.line, deployedTag: /@deployed\b/.test(full) })
    }
    for (const c of s.suites || []) walk(c, c.title && !c.title.endsWith('.mjs') ? `${chain} ${c.title}` : chain)
  }
  for (const s of d.suites || []) walk(s)
  return out
}

function lastRun() {
  if (!fs.existsSync('uat-artifacts/results.json')) return {}
  const r = JSON.parse(fs.readFileSync('uat-artifacts/results.json', 'utf8')), out = {}
  const walk = (s) => {
    for (const sp of s.specs || []) for (const t of sp.tests) {
      const st = t.results?.length ? t.results[t.results.length - 1].status : 'skipped'
      ;(out[sp.file] ||= []).push(st)
    }
    for (const c of s.suites || []) walk(c)
  }
  for (const s of r.suites || []) walk(s)
  out.__stats = r.stats
  return out
}

if (process.argv[1] && process.argv[1].endsWith('test-register.mjs')) {
  const add = addedBy(), run = lastRun()
  const list = listed()
  const specs = fs.readdirSync(DIR).filter((f) => f.endsWith('.spec.mjs')).sort().map((f) => {
    const src = fs.readFileSync(`${DIR}/${f}`, 'utf8'), lines = src.split('\n'), s = specInfo(f, src)
    // counts come from what Playwright collects (loops and helpers included), not from the source text
    s.tests = (list[f] || []).map((t) => ({ title: t.title, deployed: t.deployedTag, browser: /\(\s*\{[^}]*\bpage\b/.test(lines.slice(t.line - 1, t.line + 1).join(' ')) }))
    // the deployed flag comes from the collected tests' tags, not from text in the file (S120 names the tags it checks for)
    s.deployed = s.tests.length > 0 && s.tests.every((t) => t.deployed)
    s.responsive = s.tests.some((t) => /@responsive\b/.test(t.title))
    s.kind = STANDING.some((x) => s.guards.startsWith(x)) ? 'rule' : s.deployed ? 'deployed' : 'regression'
    return s
  })
  const status = (s) => {
    const r = run[s.file]
    if (s.deployed) return 'deployed track'
    if (!r) return 'not run'
    if (r.includes('failed') || r.includes('timedOut')) return 'failing'
    if (r.includes('skipped')) return 'skipped'
    return 'passing'
  }
  const sum = summarise(specs)
  const rows = specs.map((s) => {
    const a = add[s.file] || ['?', '?', '']
    const pr = (a[2].match(/\(#(\d+)\)/g) || []).pop() || a[0]
    const src = s.tests.filter((t) => !t.browser).length, br = s.tests.length - src
    const vp = s.tests.some((t) => t.deployed) ? 'desktop + phone (deployed gate)' : s.responsive ? (s.tests.every((t) => /@responsive\b/.test(t.title)) ? 'phone' : 'desktop + phone') : 'desktop'
    const live = s.tests.filter((t) => /@live-acting\b/.test(t.title)).length
    return `| ${s.id} | ${s.kind} | ${s.guards.replace(/\|/g, '/')} | ${src} / ${br} | ${vp} | ${live ? `yes (${live} of ${s.tests.length})` : 'no'} | ${pr.replace(/[()]/g, '')} ${a[1]} | ${status(s)} |`
  })
  const local = sum.total.local
  process.stdout.write([
    run.__stats ? `Status from the local run started ${new Date(run.__stats.startTime).toLocaleString('en-AU', { timeZone: 'Australia/Sydney' })}: ${run.__stats.expected} passed, ${run.__stats.skipped} skipped, ${run.__stats.unexpected} failed${run.__stats.expected + run.__stats.skipped + run.__stats.unexpected < local ? ' — **a partial run: regenerate after a full local run**' : ''}.` : 'No local run found: statuses are "not run".', '',
    `Generated by \`node scripts/test-register.mjs\` on ${new Date().toLocaleDateString('en-AU', { timeZone: 'Australia/Sydney', day: 'numeric', month: 'short', year: 'numeric' })}.`, '',
    ...summaryLines(sum), '',
    '| Id | Category | Guards | Tests (source / browser) | Viewports | Acts on live | Added | Status |', '|---|---|---|---|---|---|---|---|',
    ...rows, ''].join('\n'))
}
