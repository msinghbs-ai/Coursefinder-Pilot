// Guards: Platform Admin mandate 6 Nov 2026 11:00, authoritative test evidence.
// Pure functions for the evidence bundle: file classification, dependency fingerprint, reuse decision, bundle validation, results summary and the
// Integration Controller readiness report. No network access here; scripts/test-evidence.mjs and scripts/test-evidence-readiness.mjs call it.
import fs from 'node:fs'
import crypto from 'node:crypto'
import path from 'node:path'
import { execFileSync } from 'node:child_process'

export const BUNDLE_SCHEMA = 1
export const FINGERPRINT_SCHEMA = 1
export const loadClasses = (file = 'scripts/test-evidence-classes.json') => JSON.parse(fs.readFileSync(file, 'utf8'))
export const sha256 = (buf) => crypto.createHash('sha256').update(buf).digest('hex')

// GitHub-style glob: ** crosses directories, * does not
export function globToRegExp(g) {
  let r = ''
  for (let i = 0; i < g.length; i++) {
    const c = g[i]
    if (c === '*' && g[i + 1] === '*') { r += '.*'; i++; if (g[i + 1] === '/') i++ }
    else if (c === '*') r += '[^/]*'
    else r += c.replace(/[.+^${}()|[\]\\?]/g, '\\$&')
  }
  return new RegExp(`^${r}$`)
}
const matchAny = (globs, p) => globs.some((g) => globToRegExp(g).test(p))

// 'metadata' = may be reused when only these change; 'execution' = invalidates. Anything unclassified is execution (fail closed).
export function classify(p, cfg) {
  if (matchAny(cfg.executionOverrides || [], p)) return 'execution'
  return matchAny(cfg.reusableMetadata || [], p) ? 'metadata' : 'execution'
}

// path -> blob sha for a commit, from git itself (no checkout needed, so any commit can be compared)
export function treeEntries(ref, cwd = process.cwd()) {
  const out = execFileSync('git', ['ls-tree', '-r', '-z', ref], { cwd, encoding: 'utf8', maxBuffer: 256 << 20 })
  const m = {}
  for (const row of out.split('\0').filter(Boolean)) {
    const tab = row.indexOf('\t'), [mode, , sha] = row.slice(0, tab).split(' ')
    if (mode !== '160000') m[row.slice(tab + 1)] = sha  // submodule pointers are not file content
  }
  return m
}

// Metadata files that a test reads directly are execution inputs, unless the final-candidate checks re-read them on the candidate.
export function testReadPromotions(entries, cfg, readFile) {
  const out = new Set()
  const tests = Object.keys(entries).filter((p) => /^tests\/.+\.(mjs|js|sh|sql)$/.test(p))
  const meta = Object.keys(entries).filter((p) => classify(p, cfg) === 'metadata' && !matchAny(cfg.coveredByFinalChecks || [], p))
  const bodies = tests.map((t) => readFile(t))
  for (const m of meta) {
    const re = new RegExp(`(^|[^\\w/.-])${m.replace(/[.+^${}()|[\]\\?*]/g, '\\$&')}`)
    if (bodies.some((b) => b && re.test(b))) out.add(m)
  }
  return [...out]
}

export function fingerprint(entries, cfg, env = {}, readFile = () => '') {
  const promoted = new Set(testReadPromotions(entries, cfg, readFile))
  const inputs = Object.keys(entries).filter((p) => classify(p, cfg) === 'execution' || promoted.has(p)).sort()
  const h = crypto.createHash('sha256')
  h.update(`schema:${FINGERPRINT_SCHEMA}\nnode:${env.nodeMajor || ''}\nos:${env.os || ''}\n`)
  for (const p of inputs) h.update(`${p}\0${entries[p]}\n`)
  const sub = (re) => { const x = crypto.createHash('sha256'); for (const p of inputs.filter((q) => re.test(q))) x.update(`${p}\0${entries[p]}\n`); return x.digest('hex') }
  return {
    schema: FINGERPRINT_SCHEMA, value: h.digest('hex'), inputFiles: inputs.length, ignoredMetadataFiles: Object.keys(entries).length - inputs.length,
    promotedMetadata: [...promoted].sort(), environmentContract: { nodeMajor: env.nodeMajor || '', os: env.os || '' },
    migrations: sub(/^supabase\/migrations\//), parityFixtures: sub(/^tests\/fixtures\//),
  }
}

export function changedPaths(a, b) {
  const out = []
  for (const p of new Set([...Object.keys(a), ...Object.keys(b)])) if (a[p] !== b[p]) out.push(p)
  return out.sort()
}

// the earlier bundle must be complete, passing and whole before anything is reused
export function validateBundle(ev, files = {}) {
  const why = []
  if (!ev || typeof ev !== 'object') return ['evidence.json missing or unreadable']
  if (ev.schema !== BUNDLE_SCHEMA) why.push(`bundle schema ${ev.schema} != ${BUNDLE_SCHEMA}`)
  if (ev.complete !== true) why.push(`bundle is incomplete: ${(ev.incompleteReasons || ['no reason recorded']).join('; ')}`)
  if (ev.result !== 'pass') why.push(`bundle result is ${ev.result}`)
  if (!/^[0-9a-f]{40}$/.test(ev.source?.sha || '')) why.push('source commit sha missing')
  if (!ev.fingerprint?.value) why.push('fingerprint missing')
  const t = ev.suite?.totals
  if (!t || !(t.total > 0)) why.push('no test totals')
  else {
    if (t.failed) why.push(`${t.failed} failed test(s)`)
    if (t.skipped) why.push(`${t.skipped} skipped test(s): nothing may be silently skipped`)
    if (t.passed + t.failed + t.skipped + (t.flaky || 0) !== t.total) why.push('totals do not add up')
  }
  if (ev.suite?.unexplainedSkips?.length) why.push('unexplained skips recorded')
  for (const k of ['build', 'releaseContract']) if (ev[k]?.result !== 'pass') why.push(`${k} result is ${ev[k]?.result || 'missing'}`)
  if (ev.parity?.outcome !== 'pass' && ev.parity?.outcome !== 'not-applicable') why.push(`parity outcome is ${ev.parity?.outcome || 'missing'}`)
  for (const [name, digest] of Object.entries(ev.files || {})) {
    if (!(name in files)) why.push(`file ${name} is missing from the bundle`)
    else if (files[name] !== digest) why.push(`file ${name} does not match its recorded digest`)
  }
  if (!ev.files || !ev.files['results.json']) why.push('results.json is not part of the bundle')
  return why
}

// Reuse decision. prior = {evidence, files}. Fails closed: any doubt means run the full suite.
export function decideReuse({ prior, candidateSha, candidateFingerprint, lineageShas }) {
  if (!prior) return { reuse: false, reasons: ['no earlier evidence found for this pull request'] }
  const reasons = validateBundle(prior.evidence, prior.files)
  const ev = prior.evidence
  if (ev?.source?.sha && !lineageShas.includes(ev.source.sha)) reasons.push('evidence is from a commit outside this pull request (unrelated branch)')
  if (ev?.kind === 'reused') reasons.push('only an executed bundle can be reused; a reused bundle points at its source')
  if (ev?.fingerprint?.schema !== candidateFingerprint.schema) reasons.push('fingerprint schema differs')
  if (ev?.fingerprint?.value !== candidateFingerprint.value) reasons.push('dependency fingerprint differs: executable, test, fixture, migration, dependency, build or configuration input changed')
  return reasons.length ? { reuse: false, reasons } : { reuse: true, reasons: [], from: ev.source.sha, candidate: candidateSha }
}

// Summarise a Playwright JSON report. A skip is explained only when the test is tagged @deployed (needs the live environment).
export function summariseResults(report, specGuards = {}) {
  const tests = []
  const walk = (s, chain = '') => {
    for (const sp of s.specs || []) for (const t of sp.tests || []) {
      const rs = t.results || [], last = rs[rs.length - 1]
      const status = !last ? 'skipped' : last.status === 'passed' ? (rs.length > 1 ? 'flaky' : 'passed') : last.status === 'skipped' ? 'skipped' : 'failed'
      tests.push({ file: sp.file, title: `${chain} ${sp.title}`.trim(), project: t.projectName, status, retries: Math.max(0, rs.length - 1), guard: specGuards[sp.file] || null })
    }
    for (const c of s.suites || []) walk(c, c.title && !/\.mjs$/.test(c.title) ? `${chain} ${c.title}` : chain)
  }
  for (const s of report.suites || []) walk(s)
  const n = (st) => tests.filter((t) => t.status === st).length
  const unexplainedSkips = tests.filter((t) => t.status === 'skipped' && !/@deployed\b/.test(t.title)).map((t) => `${t.file}: ${t.title}`)
  const st = report.stats || {}
  return {
    totals: { total: tests.length, passed: n('passed'), failed: n('failed'), skipped: n('skipped'), flaky: n('flaky') },
    unexplainedSkips, tests,
    startedAt: st.startTime || null, durationMs: st.duration ?? null,
    completedAt: st.startTime && st.duration != null ? new Date(new Date(st.startTime).getTime() + st.duration).toISOString() : null,
  }
}

// ---- readiness report for the Integration Controller ----
export function buildReadiness({ pr, sha, evidence, evidenceProblems = [], evidenceSource = null, parity, checks, requiredChecks, finalChecks }) {
  const blockers = [], pending = []
  const evidenceValid = !!evidence && evidenceProblems.length === 0
  if (!evidence) blockers.push('No test evidence bundle for this revision (the suite has not run, or the bundle expired).')
  for (const p of evidenceProblems) blockers.push(`Evidence: ${p}`)
  if (evidence && evidence.source?.sha !== sha) blockers.push(`Evidence is for ${evidence.source?.sha}, not ${sha}`)
  const parityValid = !!parity && (parity.outcome === 'pass' || parity.outcome === 'not-applicable')
  if (!parityValid) blockers.push(`Production-parity outcome is ${parity?.outcome || 'missing'}${parity?.problems?.length ? `: ${parity.problems.join('; ')}` : ''}`)
  const reqRows = requiredChecks.map((r) => {
    const c = checks.find((x) => x.name === r.name)
    // An applicable required check must actually pass. A skipped/neutral check
    // is not execution evidence; only an inapplicable track may be omitted.
    let state = !c ? (r.applicable === false ? 'not-applicable' : 'not-reported') : c.status !== 'completed' ? 'pending' : c.conclusion === 'success' ? 'pass' : r.applicable === false && ['skipped', 'neutral'].includes(c.conclusion) ? 'not-applicable' : 'fail'
    if (state === 'fail' || state === 'not-reported') blockers.push(`Required check ${r.name}: ${state}`)
    if (state === 'pending') pending.push(`Required check ${r.name}: pending`)
    return { name: r.name, state, url: c?.html_url || null }
  })
  const fc = finalChecks || evidence?.finalChecks
  if (!fc || fc.result !== 'pass') blockers.push(`Final-candidate release-contract and governance checks: ${fc?.result || 'missing'}`)
  const verdict = blockers.length ? 'BLOCKED' : pending.length ? 'WAITING' : 'READY'
  return {
    schema: 1, pr, sha, verdict, evidenceValid, evidenceKind: evidence?.kind || null, evidenceSource: evidenceSource || evidence?.reuse?.from || evidence?.source?.sha || null,
    fingerprint: evidence?.fingerprint?.value || null, parityValid, parityOutcome: parity?.outcome || null,
    suite: evidence?.suite?.totals || null, requiredChecks: reqRows, finalChecks: fc ? { result: fc.result } : null,
    blockers, waitingOn: pending,
    note: 'Release readiness is development evidence only. Production acceptance (live version, guarded hashes, Worker and UI behaviour, admission results) is recorded separately against this evidence reference. The merge stays subject to the established release gates.',
  }
}

export function readinessMarkdown(r) {
  const L = [`# Release readiness: ${r.verdict}`, '', `- Pull request: ${r.pr ? `#${r.pr}` : 'unknown'}`, `- Source revision: \`${r.sha}\``,
    `- Test evidence: ${r.evidenceValid ? 'valid' : 'NOT valid'}${r.evidenceKind ? ` (${r.evidenceKind}${r.evidenceKind === 'reused' ? ` from \`${r.evidenceSource}\`` : ''})` : ''}`,
    `- Dependency fingerprint: \`${r.fingerprint || 'none'}\``,
    `- Production-parity: ${r.parityValid ? 'valid' : 'NOT valid'} (${r.parityOutcome || 'none'})`,
    r.suite ? `- Suite: ${r.suite.passed} passed, ${r.suite.failed} failed, ${r.suite.skipped} skipped, ${r.suite.flaky} flaky of ${r.suite.total}` : '- Suite: no result',
    `- Final-candidate release-contract and governance checks: ${r.finalChecks?.result || 'missing'}`, '', '| Required check | State |', '|---|---|',
    ...r.requiredChecks.map((c) => `| ${c.name} | ${c.state} |`), '', '## Remaining blockers', ...(r.blockers.length ? r.blockers.map((b) => `- ${b}`) : ['- none']), '']
  if (r.waitingOn.length) L.push('## Still running', ...r.waitingOn.map((b) => `- ${b}`), '')
  L.push(r.note, '')
  return L.join('\n')
}

// 'paths:' list of the pull_request trigger of a workflow file
export function workflowPaths(text) {
  const lines = text.split('\n'), out = []
  const pr = lines.findIndex((l) => /^\s{2}pull_request:\s*$/.test(l))
  if (pr < 0) return null
  let inPaths = false
  for (let i = pr + 1; i < lines.length; i++) {
    const l = lines[i]
    if (/^\s{2}\S/.test(l) && !/^\s{2}pull_request/.test(l)) break
    if (/^\s{4}paths:\s*$/.test(l)) { inPaths = true; continue }
    if (inPaths) { const m = l.match(/^\s{6}-\s*['"]?([^'"]+?)['"]?\s*$/); if (m) out.push(m[1]); else if (/^\s{4}\S/.test(l)) inPaths = false }
  }
  return out.length ? out : null  // null: runs on every pull request
}
export const workflowApplies = (paths, changed) => paths === null || changed.some((c) => matchAny(paths, c))

export const digestsOf = (dir) => Object.fromEntries(fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => f !== 'evidence.json' && fs.statSync(path.join(dir, f)).isFile()).map((f) => [f, sha256(fs.readFileSync(path.join(dir, f)))]) : [])
export function loadBundle(dir) {
  const f = path.join(dir, 'evidence.json')
  return { evidence: fs.existsSync(f) ? JSON.parse(fs.readFileSync(f, 'utf8')) : null, files: digestsOf(dir) }
}

