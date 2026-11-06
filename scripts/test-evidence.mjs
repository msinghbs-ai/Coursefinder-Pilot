// Guards: Platform Admin mandate 6 Nov 2026 11:00, authoritative test evidence.
// CLI for the evidence bundle (used by .github/workflows/test-evidence.yml, usable locally):
//   fingerprint [--ref REF]                     print the dependency fingerprint of a commit
//   plan --candidate SHA --lineage a,b,c --prior DIR [--out plan.json]   decide: run the full suite or reuse the earlier bundle in DIR
//   bundle --out DIR --sha SHA ...              assemble the immutable bundle (see below)
//   verify DIR [--sha SHA] [--fingerprint-of REF]   fail closed unless the bundle is whole, passing and current for SHA
//   register DIR                                regenerate the test register from the bundle's own results.json (no test run)
import fs from 'node:fs'
import path from 'node:path'
import { execFileSync } from 'node:child_process'
import { BUNDLE_SCHEMA, loadClasses, treeEntries, fingerprint, changedPaths, decideReuse, validateBundle, summariseResults, sha256, digestsOf, loadBundle } from './test-evidence-lib.mjs'

const argv = process.argv.slice(2), cmd = argv[0]
const opt = (k, d = null) => { const i = argv.indexOf(`--${k}`); return i >= 0 ? argv[i + 1] : d }
const cfg = loadClasses()
const env = { nodeMajor: String(process.versions.node.split('.')[0]), os: process.platform }
const readAt = (ref) => (p) => { try { return execFileSync('git', ['show', `${ref}:${p}`], { encoding: 'utf8', maxBuffer: 64 << 20, stdio: ['ignore', 'pipe', 'ignore'] }) } catch { return '' } }
const fpOf = (ref) => fingerprint(treeEntries(ref), cfg, env, readAt(ref))
const readJson = (f) => JSON.parse(fs.readFileSync(f, 'utf8'))
const specGuards = () => {
  const out = {}
  for (const f of fs.readdirSync('tests/uat').filter((x) => x.endsWith('.spec.mjs'))) out[f] = (fs.readFileSync(`tests/uat/${f}`, 'utf8').match(/^\/\/ Guards: (.+)$/m) || [])[1] || null
  return out
}
const toolVersion = (pkg) => { try { return readJson(`node_modules/${pkg}/package.json`).version } catch { return null } }

if (cmd === 'fingerprint') {
  console.log(JSON.stringify(fpOf(opt('ref', 'HEAD')), null, 2))
} else if (cmd === 'plan') {
  const sha = opt('candidate'), lineage = (opt('lineage', '') || '').split(',').filter(Boolean)
  const fp = fpOf(sha), priorDir = opt('prior')
  const prior = priorDir && fs.existsSync(priorDir) ? loadBundle(priorDir) : null
  const d = decideReuse({ prior: prior?.evidence ? prior : null, candidateSha: sha, candidateFingerprint: fp, lineageShas: lineage })
  const plan = { ...d, candidate: sha, fingerprint: fp }
  if (prior?.evidence?.source?.sha) {
    try { plan.changedSincePriorEvidence = changedPaths(treeEntries(prior.evidence.source.sha), treeEntries(sha)) } catch { plan.changedSincePriorEvidence = null }
  }
  if (opt('out')) fs.writeFileSync(opt('out'), JSON.stringify(plan, null, 2))
  console.log(JSON.stringify({ reuse: plan.reuse, reasons: plan.reasons, from: plan.from || null, fingerprint: fp.value }, null, 2))
} else if (cmd === 'bundle') {
  const out = opt('out'), sha = opt('sha'), kind = opt('kind', 'executed')
  fs.mkdirSync(out, { recursive: true })
  const problems = []
  const fp = fpOf(sha)
  let suite, resultsFile = opt('results'), junit = opt('junit'), reuse = null
  if (kind === 'reused') {
    const prior = loadBundle(opt('reuse-dir'))
    const bad = validateBundle(prior.evidence, prior.files)
    if (bad.length) problems.push(...bad.map((b) => `reused evidence: ${b}`))
    if (prior.evidence?.fingerprint?.value !== fp.value) problems.push('reused evidence fingerprint differs from the candidate')
    suite = prior.evidence?.suite
    resultsFile = path.join(opt('reuse-dir'), 'results.json'); junit = fs.existsSync(path.join(opt('reuse-dir'), 'junit.xml')) ? path.join(opt('reuse-dir'), 'junit.xml') : null
    reuse = { from: prior.evidence?.source?.sha, fromRunId: prior.evidence?.ci?.runId, fromFingerprint: prior.evidence?.fingerprint?.value, changedPaths: opt('changed') ? opt('changed').split(',').filter(Boolean) : [], rule: 'only explicitly classified non-executable metadata changed (scripts/test-evidence-classes.json)' }
  } else {
    if (!resultsFile || !fs.existsSync(resultsFile)) problems.push('results.json missing: the suite did not produce its structured results')
    else {
      const s = summariseResults(readJson(resultsFile), specGuards())
      suite = { command: cfg.suiteCommand, startedAt: s.startedAt, completedAt: s.completedAt, durationMs: s.durationMs, totals: s.totals, unexplainedSkips: s.unexplainedSkips, tests: s.tests.map(({ file, title, project, status, retries, guard }) => ({ file, title, project, status, retries, guard })) }
      if (!s.totals.total) problems.push('no tests in results.json')
      // a partial run is not release evidence: the results must cover every test the suite command collects
      const listEnv = Object.fromEntries(Object.entries(process.env).filter(([k]) => !/^PLAYWRIGHT_(JSON|JUNIT|HTML)_/.test(k)))
      const listed = JSON.parse(execFileSync('npx', ['playwright', 'test', '--list', '--grep-invert', '@deployed', '--reporter=json'], { encoding: 'utf8', maxBuffer: 64 << 20, env: listEnv }))
      let expected = 0
      const count = (x) => { for (const sp of x.specs || []) expected += (sp.tests || []).length; for (const c of x.suites || []) count(c) }
      for (const x of listed.suites || []) count(x)
      suite.expectedTotal = expected
      if (s.totals.total !== expected) problems.push(`partial run: results hold ${s.totals.total} tests, the suite collects ${expected}`)
      if (s.totals.failed) problems.push(`${s.totals.failed} failed test(s)`)
      if (s.totals.skipped) problems.push(`${s.totals.skipped} skipped test(s)`)
      if (s.unexplainedSkips.length) problems.push(`${s.unexplainedSkips.length} unexplained skip(s)`)
    }
  }
  if (resultsFile && fs.existsSync(resultsFile)) fs.copyFileSync(resultsFile, path.join(out, 'results.json'))
  if (junit && fs.existsSync(junit)) fs.copyFileSync(junit, path.join(out, 'junit.xml'))
  const parity = opt('parity') && fs.existsSync(opt('parity')) ? readJson(opt('parity')) : { outcome: 'missing', tracks: [], problems: ['parity outcome was not supplied'] }
  if (parity.outcome !== 'pass' && parity.outcome !== 'not-applicable') problems.push(`parity outcome ${parity.outcome}`)
  parity.fixtureFingerprint = fp.parityFixtures; parity.migrationsFingerprint = fp.migrations
  const build = { result: opt('build', 'missing'), distSha256: opt('dist-sha'), command: 'npm run build' }
  const releaseContract = { result: opt('release-contract', 'missing'), command: cfg.finalCandidateChecks.commands.join(' && ') }
  const finalChecks = { result: opt('final-checks', 'missing'), source: opt('final-source', 'missing'), specs: cfg.finalCandidateChecks.specs, commands: cfg.finalCandidateChecks.commands }
  if (build.result !== 'pass') problems.push(`build ${build.result}`)
  if (releaseContract.result !== 'pass') problems.push(`release contract ${releaseContract.result}`)
  if (finalChecks.result !== 'pass') problems.push(`final-candidate checks ${finalChecks.result}`)
  const ev = {
    schema: BUNDLE_SCHEMA, kind, immutable: 'one bundle per validated commit; a later bundle never overwrites an earlier one (artifact name carries the sha)',
    source: { repository: opt('repo'), sha, prNumber: opt('pr') ? Number(opt('pr')) : null, baseSha: opt('base'), ref: opt('ref') },
    fingerprint: fp,
    environment: { ...env, node: process.versions.node, playwright: toolVersion('@playwright/test'), vite: toolVersion('vite'), react: toolVersion('react'), runner: process.env.ImageVersion || process.env.RUNNER_OS || null },
    suite, parity, integration: parity.tracks, build, releaseContract, finalChecks,
    ci: { workflow: opt('workflow', 'Test evidence'), runId: opt('run-id'), runAttempt: opt('attempt'), runUrl: opt('run-url') },
    reuse, retentionDays: cfg.retentionDays,
    complete: problems.length === 0, incompleteReasons: problems, result: problems.length === 0 ? 'pass' : 'fail',
  }
  fs.writeFileSync(path.join(out, 'evidence.json'), JSON.stringify(ev, null, 2))
  // the register comes from this bundle's results, never from another run
  if (fs.existsSync(path.join(out, 'results.json'))) {
    const src = `${sha.slice(0, 8)}, run ${ev.ci.runId || 'local'}${kind === 'reused' ? `, reused from ${String(reuse.from).slice(0, 8)}` : ''}`
    const reg = execFileSync('node', ['scripts/test-register.mjs', '--results', path.join(out, 'results.json'), '--source', src, '--generated', (suite?.completedAt || new Date().toISOString()).slice(0, 10)], { encoding: 'utf8', maxBuffer: 64 << 20 })
    const tracks = (parity.tracks || []).map((t) => `| ${t.workflow} | ${t.applicable ? 'yes' : 'no (path filter)'} | ${t.conclusion || 'not run'} | ${t.runId || ''} |`)
    fs.writeFileSync(path.join(out, 'TEST-REGISTER.md'), `${reg}\n## Integration tracks in this evidence\n\nTaken from the CI runs for the same commit; their own specs are outside the default UAT totals above.\n\n| Workflow | Applicable | Conclusion | Run |\n|---|---|---|---|\n${tracks.join('\n')}\n`)
  }
  // digests last, so the manifest covers every file
  ev.files = digestsOf(out)
  fs.writeFileSync(path.join(out, 'evidence.json'), JSON.stringify(ev, null, 2))
  console.log(JSON.stringify({ result: ev.result, complete: ev.complete, problems, totals: suite?.totals }, null, 2))
  process.exit(ev.complete ? 0 : 1)
} else if (cmd === 'verify') {
  const dir = argv[1], b = loadBundle(dir), why = validateBundle(b.evidence, b.files)
  const sha = opt('sha')
  if (sha && b.evidence?.source?.sha !== sha) why.push(`evidence is for ${b.evidence?.source?.sha}, not ${sha}`)
  if (opt('fingerprint-of') && b.evidence?.fingerprint?.value !== fpOf(opt('fingerprint-of')).value) why.push('dependency fingerprint is stale for the candidate')
  console.log(JSON.stringify({ valid: why.length === 0, problems: why }, null, 2))
  process.exit(why.length ? 1 : 0)
} else if (cmd === 'final-from-results') {
  // the governance specs ran inside the same results.json: read their outcome instead of running them twice
  const s = summariseResults(readJson(opt('results')))
  const want = cfg.finalCandidateChecks.specs.map((n) => `${n}.spec.mjs`)
  const missing = want.filter((f) => !s.tests.some((t) => t.file === f))
  const bad = s.tests.filter((t) => want.includes(t.file) && !['passed', 'flaky'].includes(t.status))
  const ok = !missing.length && !bad.length
  console.log(JSON.stringify({ result: ok ? 'pass' : 'fail', missing, notPassed: bad.map((t) => `${t.file}: ${t.title}`) }))
  process.exit(ok ? 0 : 1)
} else if (cmd === 'register') {
  const dir = argv[1], b = loadBundle(dir), why = validateBundle(b.evidence, b.files)
  if (why.length) { console.error(`evidence is not valid, no register written:\n- ${why.join('\n- ')}`); process.exit(1) }
  const ev = b.evidence
  process.stdout.write(execFileSync('node', ['scripts/test-register.mjs', '--results', path.join(dir, 'results.json'), '--source', `${ev.source.sha.slice(0, 8)}, run ${ev.ci.runId || 'local'}`, '--generated', (ev.suite.completedAt || '').slice(0, 10)], { encoding: 'utf8', maxBuffer: 64 << 20 }))
} else {
  console.error('usage: test-evidence.mjs fingerprint|plan|bundle|verify|register'); process.exit(2)
}
