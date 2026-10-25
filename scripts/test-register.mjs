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
  const n = (k) => specs.filter((s) => s.kind === k)
  const tests = (a) => a.reduce((x, s) => x + s.tests.length, 0)
  const rows = specs.map((s) => {
    const a = add[s.file] || ['?', '?', '']
    const pr = (a[2].match(/\(#(\d+)\)/g) || []).pop() || a[0]
    const src = s.tests.filter((t) => !t.browser).length, br = s.tests.length - src
    const vp = s.tests.some((t) => t.deployed) ? 'desktop + phone (deployed gate)' : s.responsive ? (s.tests.every((t) => /@responsive\b/.test(t.title)) ? 'phone' : 'desktop + phone') : 'desktop'
    const live = s.tests.filter((t) => /@live-acting\b/.test(t.title)).length
    return `| ${s.id} | ${s.kind} | ${s.guards.replace(/\|/g, '/')} | ${src} / ${br} | ${vp} | ${live ? `yes (${live} of ${s.tests.length})` : 'no'} | ${pr.replace(/[()]/g, '')} ${a[1]} | ${status(s)} |`
  })
  const local = specs.reduce((x, s) => x + s.tests.filter((t) => !t.deployed).length, 0)
  const dep = specs.reduce((x, s) => x + s.tests.filter((t) => t.deployed).length, 0)
  const liveN = specs.reduce((x, s) => x + s.tests.filter((t) => /@live-acting\b/.test(t.title)).length, 0)
  const phoneN = specs.reduce((x, s) => x + s.tests.filter((t) => /@responsive\b/.test(t.title)).length, 0)
  process.stdout.write([
    run.__stats ? `Status from the local run started ${new Date(run.__stats.startTime).toLocaleString('en-AU', { timeZone: 'Australia/Sydney' })}: ${run.__stats.expected} passed, ${run.__stats.skipped} skipped, ${run.__stats.unexpected} failed${run.__stats.expected + run.__stats.skipped + run.__stats.unexpected < local ? ' — **a partial run: regenerate after a full local run**' : ''}.` : 'No local run found: statuses are "not run".', '',
    `Generated by \`node scripts/test-register.mjs\` on ${new Date().toLocaleDateString('en-AU', { timeZone: 'Australia/Sydney', day: 'numeric', month: 'short', year: 'numeric' })}.`, '',
    `| Category | Specs | Tests |`, `|---|---|---|`,
    `| Rule guards (standing rules) | ${n('rule').length} | ${tests(n('rule'))} |`,
    `| Regression guards (one decision or change each) | ${n('regression').length} | ${tests(n('regression'))} |`,
    `| Deployed track (run against the live site by deployed-uat) | ${n('deployed').length} | ${tests(n('deployed'))} |`,
    `| **Total** | **${specs.length}** | **${tests(specs)}** |`, '', `Local suite (\`--grep-invert @deployed\`): ${local} tests, one run each (desktop; phone only for \`@responsive\`). Phone-width tests (\`@responsive\`, phone project only): ${phoneN}. Deployed track: ${dep} tests, desktop plus the phone gate; ${liveN} of them act on the live site (\`@live-acting\`) and run only when the live-acting switch is on (default off), so ${dep - liveN} safe tests run each week.`, '',
    '| Id | Category | Guards | Tests (source / browser) | Viewports | Acts on live | Added | Status |', '|---|---|---|---|---|---|---|---|',
    ...rows, ''].join('\n'))
}
