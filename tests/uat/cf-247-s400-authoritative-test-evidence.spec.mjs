// Guards: Platform Admin mandate 6 Nov 2026 11:00, authoritative test evidence
// Acceptance cases of section 8: (1) a code change invalidates earlier evidence; (2) a release-notes-only change reuses the full-suite result while
// the final-candidate release checks stay mandatory; (3) a test fixture or database-schema change invalidates. Also: incomplete or stale evidence
// fails closed, nothing is silently skipped, the register is reproducible from the retained results, and branch protection / required check names
// are untouched. Uses real repository file lists (git ls-tree of HEAD) with the changed file's blob replaced, so the proof is on this tree.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFileSync } from 'node:child_process'
import { loadClasses, treeEntries, fingerprint, classify, changedPaths, decideReuse, validateBundle, summariseResults, buildReadiness, readinessMarkdown, workflowPaths, workflowApplies, loadBundle, sha256 } from '../../scripts/test-evidence-lib.mjs'

const cfg = loadClasses()
const ENV = { nodeMajor: '22', os: 'linux' }
const head = treeEntries('HEAD')
const read = (p) => { try { return fs.readFileSync(p, 'utf8') } catch { return '' } }
const fpOf = (entries) => fingerprint(entries, cfg, ENV, read)
const base = fpOf(head)
const SHA_A = 'a'.repeat(40), SHA_B = 'b'.repeat(40), SHA_X = 'c'.repeat(40)
const bundle = (over = {}) => ({
  schema: 1, kind: 'executed', complete: true, incompleteReasons: [], result: 'pass', source: { sha: SHA_A }, fingerprint: base,
  suite: { totals: { total: 10, passed: 10, failed: 0, skipped: 0, flaky: 0 }, unexplainedSkips: [] },
  build: { result: 'pass' }, releaseContract: { result: 'pass' }, parity: { outcome: 'pass' }, finalChecks: { result: 'pass' },
  files: { 'results.json': 'd1' }, ...over,
})
const files = { 'results.json': 'd1' }
const reuse = (entries, prior = { evidence: bundle(), files }) => decideReuse({ prior, candidateSha: SHA_B, candidateFingerprint: fpOf(entries), lineageShas: [SHA_A, SHA_B] })
const withBlob = (path_, blob = 'f'.repeat(40)) => ({ ...head, [path_]: blob })

test('unchanged tree reuses valid evidence (control for the three cases)', () => {
  expect(reuse(head).reuse).toBe(true)
})

test('case 1: a change to application, Worker, edge function, test, dependency, build, workflow or deployment configuration invalidates the evidence', () => {
  for (const p of ['src/ProcessResults.jsx', 'src/process-results-api.js', 'supabase/functions/website-api-v2/index.ts', 'tests/uat/cf-247-s32-controls-in-settings-contract.spec.mjs',
    'package.json', 'vite.config.js', 'wrangler.jsonc', 'playwright.config.mjs', '.github/workflows/pim-build.yml', 'index.html', 'scripts/verify-release-contract.mjs']) {
    expect(head[p], `${p} is tracked`).toBeTruthy()
    const d = reuse(withBlob(p))
    expect(d.reuse, p).toBe(false)
    expect(d.reasons.join(' '), p).toMatch(/fingerprint differs/)
  }
  // a brand new source file and a deleted one invalidate too
  expect(reuse({ ...head, 'src/NewThing.jsx': 'e'.repeat(40) }).reuse).toBe(false)
  const { 'src/ProcessResults.jsx': _gone, ...without } = head
  expect(reuse(without).reuse).toBe(false)
  // the runtime contract (node major, operating system) is part of the fingerprint
  expect(fingerprint(head, cfg, { nodeMajor: '20', os: 'linux' }, read).value).not.toBe(base.value)
})

// a docs file no spec names (naming a real doc here would itself make it a test input)
const plainDoc = Object.keys(head).find((p) => /^docs\/[^/]+\.md$/.test(p) && !base.promotedMetadata.includes(p))

test('case 2: release notes, changelog text and docs reuse the full-suite evidence; the final-candidate checks remain required', () => {
  const entries = { ...head, 'CHANGELOG.md': '1'.repeat(40), 'docs/release-notes/v2.15.999.md': '2'.repeat(40), 'docs/platform/TEST-REGISTER.md': '3'.repeat(40), [plainDoc]: '4'.repeat(40) }
  expect(fpOf(entries).value).toBe(base.value)
  const d = reuse(entries)
  expect(d.reuse).toBe(true)
  expect(changedPaths(head, entries).every((p) => classify(p, cfg) === 'metadata')).toBe(true)
  // the lightweight release-contract and governance checks are mandatory on the candidate and name real specs
  const fc = cfg.finalCandidateChecks
  expect(fc.commands).toContain('node scripts/verify-release-contract.mjs')
  for (const id of ['cf-247-s32-controls-in-settings-contract', 'cf-247-s42-housekeeping-contract', 'cf-247-s57-consumer-api-frozen', 'cf-247-s120-test-governance-contract', 'm245-release-history-v21575-persistence-contract'])
    expect(fc.specs, id).toContain(id)
  for (const id of fc.specs) expect(fs.existsSync(`tests/uat/${id}.spec.mjs`), id).toBe(true)
  const wf = read('.github/workflows/test-evidence.yml')
  expect(wf).toContain("steps.mode.outputs.mode == 'reuse'")
  expect(wf).toContain('verify-release-contract.mjs')
  expect(wf).toContain('npm run build')
})

test('case 2b: the version bump, SOPs, paste files and anything unclassified are NOT metadata (fail closed)', () => {
  for (const p of ['package.json', 'src/release-manifest.js', 'docs/sops/admin-sop.md', 'docs/paste/PASTE-20261104-aer-render-pilot.sql', 'some-new-config.toml', 'docs/diagram.png', '.github/workflows/test-evidence.yml'])
    expect(classify(p, cfg), p).toBe('execution')
  // a metadata file that a test reads directly becomes an input (README.md is named by cf-247-baseline-contract)
  const pro = fpOf(head).promotedMetadata
  expect(pro).toContain('README.md')
  expect(reuse(withBlob('README.md')).reuse).toBe(false)
})

test('case 3: a fixture, database-schema, migration or parity change invalidates the evidence', () => {
  for (const p of Object.keys(head).filter((x) => /^tests\/fixtures\/.*parity-tables\.sql$/.test(x)).slice(0, 2).concat(
    Object.keys(head).filter((x) => /^supabase\/migrations\/.+\.sql$/.test(x)).slice(-1), ['tests/fixtures/prod-parity/run.sh'])) {
    expect(head[p], p).toBeTruthy()
    const d = reuse(withBlob(p))
    expect(d.reuse, p).toBe(false)
  }
  const m = fpOf(withBlob(Object.keys(head).filter((x) => /^supabase\/migrations\//.test(x)).pop()))
  expect(m.migrations).not.toBe(base.migrations)
  const f = fpOf(withBlob('tests/fixtures/prod-parity/run.sh'))
  expect(f.parityFixtures).not.toBe(base.parityFixtures)
})

test('git integration: the fingerprint is read from commits, so any two commits can be compared without a checkout', () => {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), 'ev-git-'))
  const g = (...a) => execFileSync('git', ['-c', 'user.email=t@t', '-c', 'user.name=t', ...a], { cwd: d, encoding: 'utf8' })
  g('init', '-q'); fs.mkdirSync(path.join(d, 'src')); fs.mkdirSync(path.join(d, 'docs/release-notes'), { recursive: true })
  fs.writeFileSync(path.join(d, 'src/a.js'), '1'); fs.writeFileSync(path.join(d, 'CHANGELOG.md'), 'x'); g('add', '.'); g('commit', '-qm', 'one')
  const c1 = g('rev-parse', 'HEAD').trim()
  fs.writeFileSync(path.join(d, 'CHANGELOG.md'), 'y'); fs.writeFileSync(path.join(d, 'docs/release-notes/v1.md'), 'n'); g('add', '.'); g('commit', '-qm', 'notes only')
  const c2 = g('rev-parse', 'HEAD').trim()
  fs.writeFileSync(path.join(d, 'src/a.js'), '2'); g('add', '.'); g('commit', '-qm', 'code')
  const c3 = g('rev-parse', 'HEAD').trim()
  const f = (c) => fingerprint(treeEntries(c, d), cfg, ENV, () => '').value
  expect(f(c2)).toBe(f(c1))
  expect(f(c3)).not.toBe(f(c2))
  expect(changedPaths(treeEntries(c1, d), treeEntries(c2, d))).toEqual(['CHANGELOG.md', 'docs/release-notes/v1.md'])
})

test('incomplete, failing, stale or foreign evidence is never reused (fail closed)', () => {
  const bad = (over, re) => { const d = reuse(head, { evidence: bundle(over), files }); expect(d.reuse, JSON.stringify(over)).toBe(false); expect(d.reasons.join(' ')).toMatch(re) }
  bad({ complete: false, incompleteReasons: ['build fail'] }, /incomplete/)
  bad({ result: 'fail' }, /result is fail/)
  bad({ suite: { totals: { total: 10, passed: 9, failed: 1, skipped: 0, flaky: 0 }, unexplainedSkips: [] } }, /failed test/)
  bad({ suite: { totals: { total: 10, passed: 9, failed: 0, skipped: 1, flaky: 0 }, unexplainedSkips: [] } }, /skipped/)
  bad({ build: { result: 'fail' } }, /build result/)
  bad({ releaseContract: { result: 'missing' } }, /releaseContract/)
  bad({ parity: { outcome: 'missing' } }, /parity/)
  bad({ schema: 2 }, /schema/)
  bad({ source: { sha: SHA_X } }, /unrelated branch/)           // a passing run from another branch
  bad({ kind: 'reused' }, /executed bundle/)
  bad({ fingerprint: { ...base, schema: 9 } }, /fingerprint schema/)
  expect(reuse(head, null).reuse).toBe(false)
  // the retained results must match their recorded digest
  expect(reuse(head, { evidence: bundle(), files: { 'results.json': 'tampered' } }).reasons.join(' ')).toMatch(/digest/)
  expect(reuse(head, { evidence: bundle(), files: {} }).reasons.join(' ')).toMatch(/missing from the bundle/)
})

test('a skip is explained only for tests of the deployed track; anything else is an unexplained skip', () => {
  const mk = (title, results) => ({ stats: { startTime: '2026-11-06T00:00:00.000Z', duration: 1000 }, suites: [{ title: 'a.spec.mjs', specs: [{ file: 'a.spec.mjs', title, tests: [{ projectName: 'chromium-desktop', results }] }], suites: [] }] })
  const s1 = summariseResults(mk('x @deployed', []))
  expect(s1.totals.skipped).toBe(1); expect(s1.unexplainedSkips).toEqual([])
  const s2 = summariseResults(mk('plain test', [{ status: 'skipped' }]))
  expect(s2.unexplainedSkips).toHaveLength(1)
  const s3 = summariseResults(mk('plain', [{ status: 'failed' }, { status: 'passed' }]))
  expect(s3.totals).toMatchObject({ passed: 0, flaky: 1, failed: 0 })
  expect(s3.completedAt).toBe('2026-11-06T00:00:01.000Z')
})

test('readiness report: one verdict with PR, revision, evidence, parity, required checks and blockers; missing evidence blocks', () => {
  const checks = [{ name: 'build-and-smoke', status: 'completed', conclusion: 'success' }, { name: 'Workers Builds: coursefinder-pilot', status: 'completed', conclusion: 'success' }, { name: 'isolated-postgres', status: 'in_progress' }]
  const req = [{ name: 'build-and-smoke' }, { name: 'Workers Builds: coursefinder-pilot' }, { name: 'isolated-postgres' }, { name: 'release-history-contract', applicable: false }]
  const ev = bundle({ source: { sha: SHA_B } })
  const waiting = buildReadiness({ pr: 7, sha: SHA_B, evidence: ev, parity: ev.parity, checks, requiredChecks: req })
  expect(waiting.verdict).toBe('WAITING'); expect(waiting.blockers).toEqual([])
  expect(waiting.requiredChecks.find((c) => c.name === 'release-history-contract').state).toBe('not-applicable')
  const ready = buildReadiness({ pr: 7, sha: SHA_B, evidence: ev, parity: ev.parity, checks: checks.map((c) => ({ ...c, status: 'completed', conclusion: 'success' })), requiredChecks: req })
  expect(ready.verdict).toBe('READY'); expect(readinessMarkdown(ready)).toMatch(/Remaining blockers\n- none/)
  const none = buildReadiness({ pr: 7, sha: SHA_B, evidence: null, parity: null, checks, requiredChecks: req })
  expect(none.verdict).toBe('BLOCKED'); expect(none.evidenceValid).toBe(false)
  expect(none.blockers.join('\n')).toMatch(/No test evidence bundle/)
  const stale = buildReadiness({ pr: 7, sha: SHA_B, evidence: ev, evidenceProblems: ['stale: dependency fingerprint of the candidate differs from the bundle'], parity: ev.parity, checks, requiredChecks: req })
  expect(stale.verdict).toBe('BLOCKED')
  const wrongSha = buildReadiness({ pr: 7, sha: SHA_X, evidence: ev, parity: ev.parity, checks, requiredChecks: req })
  expect(wrongSha.verdict).toBe('BLOCKED')
  const failedCheck = buildReadiness({ pr: 7, sha: SHA_B, evidence: ev, parity: ev.parity, checks: [{ name: 'build-and-smoke', status: 'completed', conclusion: 'failure' }], requiredChecks: [{ name: 'build-and-smoke' }] })
  expect(failedCheck.blockers.join()).toMatch(/build-and-smoke: fail/)
  for (const conclusion of ['skipped', 'neutral']) {
    const held = buildReadiness({ pr: 7, sha: SHA_B, evidence: ev, parity: ev.parity,
      checks: [{ name: 'build-and-smoke', status: 'completed', conclusion }], requiredChecks: [{ name: 'build-and-smoke' }] })
    expect(held.verdict, conclusion).toBe('BLOCKED')
  }
  const noParity = buildReadiness({ pr: 7, sha: SHA_B, evidence: ev, parity: { outcome: 'missing', problems: ['x'] }, checks, requiredChecks: [] })
  expect(noParity.parityValid).toBe(false)
})

test('the test register is generated from the retained results of the authoritative run and is reproducible', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ev-reg-'))
  const results = { stats: { startTime: '2026-11-06T01:00:00.000Z', duration: 5, expected: 1, skipped: 0, unexpected: 0, flaky: 0 }, suites: [{ title: 'cf-247-s400-authoritative-test-evidence.spec.mjs', file: 'cf-247-s400-authoritative-test-evidence.spec.mjs', specs: [{ file: 'cf-247-s400-authoritative-test-evidence.spec.mjs', title: 'x', tests: [{ results: [{ status: 'passed' }] }] }], suites: [] }] }
  fs.writeFileSync(path.join(dir, 'results.json'), JSON.stringify(results))
  const run = () => execFileSync('node', ['scripts/test-register.mjs', '--results', path.join(dir, 'results.json'), '--source', 'abcd1234, run 1', '--generated', '2026-11-06'], { encoding: 'utf8', maxBuffer: 64 << 20 })
  const a = run(), b = run()
  expect(a).toBe(b)
  expect(a).toMatch(/Status from the authoritative CI test run \(abcd1234, run 1\)/)
  expect(a).toMatch(/on 6 Nov 2026/)
  expect(a).toMatch(/cf-247-s400-authoritative-test-evidence \| rule|cf-247-s400-authoritative-test-evidence \| regression/)
  // without --results the old behaviour (uat-artifacts/results.json) is unchanged
  expect(read('scripts/test-register.mjs')).toContain("argOf('--results') || 'uat-artifacts/results.json'")
})

test('bundle files are digest-checked: loadBundle sees any change', () => {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), 'ev-b-'))
  fs.writeFileSync(path.join(d, 'results.json'), '{}'); fs.writeFileSync(path.join(d, 'evidence.json'), JSON.stringify(bundle({ files: { 'results.json': sha256('{}') } })))
  expect(validateBundle(...Object.values(loadBundle(d)))).toEqual([])
  fs.writeFileSync(path.join(d, 'results.json'), '{"x":1}')
  expect(validateBundle(...Object.values(loadBundle(d))).join()).toMatch(/digest/)
})

test('workflow: normal artifact with retention, no competing register or ledger, no branch-protection change, existing required check names untouched', () => {
  const wf = read('.github/workflows/test-evidence.yml')
  expect(wf).toMatch(/uses: actions\/upload-artifact@v4[\s\S]*name: test-evidence-\$\{\{ steps\.ctx\.outputs\.sha \}\}[\s\S]*retention-days: 90/)
  expect(wf).toMatch(/name: release-readiness-/)
  expect(wf).not.toMatch(/pull_request_target|contents:\s*write|branches\/main\/protection|--force|supabase|wrangler|db push/i)
  expect(wf).not.toMatch(/TEST-REGISTER\.md >|git push|git commit/)
  // required check names (mandate: not bypassed) still exist as jobs in the workflows they came from
  for (const r of cfg.requiredChecks.filter((x) => x.workflow)) expect(read(`.github/workflows/${r.workflow}`), r.name).toMatch(new RegExp(`^  ${r.name}:`, 'm'))
  expect(cfg.requiredChecks.map((r) => r.name)).toEqual(['Workers Builds: coursefinder-pilot', 'build-and-smoke', 'release-history-contract', 'isolated-postgres'])
  // the new job name does not shadow a required check
  expect(wf).toMatch(/^  test-evidence:/m)
  // path-filter reading used to tell "not applicable" from "missing"
  const rh = workflowPaths(read('.github/workflows/release-history-contract.yml'))
  expect(rh).toContain('CHANGELOG.md')
  expect(workflowApplies(rh, ['src/x.jsx'])).toBe(false)
  expect(workflowApplies(rh, ['CHANGELOG.md'])).toBe(true)
  expect(workflowPaths(read('.github/workflows/pim-build.yml'))).toBe(null)
})

