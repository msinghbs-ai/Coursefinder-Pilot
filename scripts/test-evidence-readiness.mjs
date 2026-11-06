// Guards: Platform Admin mandate 6 Nov 2026 11:00, authoritative test evidence.
// GitHub-facing half of the evidence tooling (REST through the gh CLI; GraphQL is not used).
//   parity --sha SHA --base BASE --repo R [--wait] --out parity.json   outcome of the isolated-PostgreSQL / production-parity workflows for SHA
//   report --repo R (--pr N | --sha SHA) [--dir DIR] [--out DIR]        the one readiness report for the Integration Controller
// Fails closed: missing, expired, stale or incomplete evidence is a blocker, never a pass.
import fs from 'node:fs'
import path from 'node:path'
import os from 'node:os'
import { execFileSync } from 'node:child_process'
import { loadClasses, buildReadiness, readinessMarkdown, workflowPaths, workflowApplies, validateBundle, treeEntries, fingerprint, loadBundle } from './test-evidence-lib.mjs'

const argv = process.argv.slice(2), cmd = argv[0]
const opt = (k, d = null) => { const i = argv.indexOf(`--${k}`); return i >= 0 ? argv[i + 1] : d }
const flag = (k) => argv.includes(`--${k}`)
const cfg = loadClasses()
const gh = (url) => JSON.parse(execFileSync('gh', ['api', url, '--paginate', '--slurp'], { encoding: 'utf8', maxBuffer: 64 << 20 }))
const ghPages = (url, key) => gh(url).flatMap((pg) => (key ? pg[key] : pg))
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const git = (...a) => execFileSync('git', a, { encoding: 'utf8', maxBuffer: 64 << 20 })

export function integrationWorkflows(sha) {
  const out = []
  for (const f of git('ls-tree', '--name-only', sha, '.github/workflows/').split('\n').filter((x) => /\.ya?ml$/.test(x))) {
    const text = git('show', `${sha}:${f}`)
    if (!/image:\s*postgres:/.test(text) || !/^\s{2}pull_request:/m.test(text)) continue
    out.push({ file: path.basename(f), name: (text.match(/^name:\s*(.+)$/m) || [])[1]?.trim().replace(/^["']|["']$/g, ''), paths: workflowPaths(text) })
  }
  return out
}

export async function resolveParity({ repo, sha, base, wait }) {
  const changed = git('diff', '--name-only', base, sha).split('\n').filter(Boolean)
  const wfs = integrationWorkflows(sha), deadline = Date.now() + cfg.siblingWaitMinutes * 60000
  const tracks = []
  for (;;) {
    const runs = ghPages(`repos/${repo}/actions/runs?head_sha=${sha}&per_page=100`, 'workflow_runs')
    tracks.length = 0
    for (const w of wfs) {
      const applicable = workflowApplies(w.paths, changed)
      const run = runs.filter((r) => r.name === w.name).sort((a, b) => b.created_at.localeCompare(a.created_at))[0]
      tracks.push({ workflow: w.name, file: w.file, applicable, runId: run?.id || null, url: run?.html_url || null, status: run?.status || null, conclusion: run?.conclusion || null })
    }
    const open = tracks.filter((t) => t.applicable && t.runId && t.status !== 'completed')
    if (!wait || !open.length || Date.now() > deadline) break
    await sleep(30000)
  }
  const problems = []
  for (const t of tracks.filter((x) => x.applicable)) {
    if (!t.runId) problems.push(`${t.workflow}: applicable to this change but no run for ${sha.slice(0, 8)}`)
    else if (t.status !== 'completed') problems.push(`${t.workflow}: still running`)
    else if (t.conclusion !== 'success') problems.push(`${t.workflow}: ${t.conclusion}`)
  }
  const app = tracks.filter((t) => t.applicable)
  const outcome = problems.length ? (app.some((t) => t.conclusion === 'failure') ? 'fail' : app.some((t) => t.runId && t.status !== 'completed') ? 'pending' : 'missing') : app.length ? 'pass' : 'not-applicable'
  return { outcome, tracks, problems, changedFiles: changed.length }
}

async function downloadEvidence(repo, sha, dir) {
  const arts = ghPages(`repos/${repo}/actions/artifacts?name=test-evidence-${sha}&per_page=100`, 'artifacts').filter((a) => !a.expired && a.workflow_run?.head_sha === sha)
  arts.sort((a, b) => b.created_at.localeCompare(a.created_at))
  if (!arts.length) return null
  fs.mkdirSync(dir, { recursive: true })
  execFileSync('gh', ['run', 'download', String(arts[0].workflow_run.id), '-R', repo, '-n', arts[0].name, '-D', dir], { stdio: 'inherit' })
  return arts[0]
}

if (cmd === 'parity') {
  const p = await resolveParity({ repo: opt('repo'), sha: opt('sha'), base: opt('base'), wait: flag('wait') })
  if (opt('out')) fs.writeFileSync(opt('out'), JSON.stringify(p, null, 2))
  console.log(JSON.stringify(p, null, 2))
} else if (cmd === 'report') {
  const repo = opt('repo')
  let pr = opt('pr') ? Number(opt('pr')) : null, sha = opt('sha'), base
  if (pr) { const d = JSON.parse(execFileSync('gh', ['api', `repos/${repo}/pulls/${pr}`], { encoding: 'utf8' })); sha = d.head.sha; base = d.base.sha }
  else if (sha) { const ps = JSON.parse(execFileSync('gh', ['api', `repos/${repo}/commits/${sha}/pulls`], { encoding: 'utf8' })); pr = ps[0]?.number || null; base = ps[0]?.base?.sha }
  if (!sha) { console.error('--pr or --sha is required'); process.exit(2) }
  const dir = opt('dir') || fs.mkdtempSync(path.join(os.tmpdir(), 'evidence-'))
  let loaded = null, art = null
  if (opt('dir') && fs.existsSync(path.join(dir, 'evidence.json'))) loaded = loadBundle(dir)
  else { try { art = await downloadEvidence(repo, sha, dir); if (art) loaded = loadBundle(dir) } catch (e) { console.error(`evidence download failed: ${e.message}`) } }
  const evidence = loaded?.evidence || null
  const problems = loaded ? validateBundle(evidence, loaded.files) : []
  // the fingerprint in the bundle must be the fingerprint of the candidate right now
  if (evidence) {
    const env = { nodeMajor: evidence.fingerprint?.environmentContract?.nodeMajor, os: evidence.fingerprint?.environmentContract?.os }
    const now = fingerprint(treeEntries(sha), cfg, env, (p) => { try { return git('show', `${sha}:${p}`) } catch { return '' } })
    if (now.value !== evidence.fingerprint?.value) problems.push('stale: dependency fingerprint of the candidate differs from the bundle')
  }
  const checks = ghPages(`repos/${repo}/commits/${sha}/check-runs?per_page=100`, 'check_runs')
  const changed = base ? git('diff', '--name-only', base, sha).split('\n').filter(Boolean) : []
  const required = cfg.requiredChecks.map((r) => {
    let applicable = true
    if (r.workflow) { try { const t = git('show', `${sha}:.github/workflows/${r.workflow}`); applicable = workflowApplies(workflowPaths(t), changed) } catch { applicable = true } }
    return { ...r, applicable }
  })
  const report = buildReadiness({ pr, sha, evidence, evidenceProblems: problems, evidenceSource: art?.workflow_run?.id ? `run ${art.workflow_run.id}` : null, parity: evidence?.parity || null, checks, requiredChecks: required })
  const out = opt('out') || '.'
  fs.mkdirSync(out, { recursive: true })
  fs.writeFileSync(path.join(out, 'readiness.json'), JSON.stringify(report, null, 2))
  fs.writeFileSync(path.join(out, 'readiness.md'), readinessMarkdown(report))
  process.stdout.write(readinessMarkdown(report))
  if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, readinessMarkdown(report))
  process.exit(report.verdict === 'BLOCKED' ? 1 : 0)
} else { console.error('usage: test-evidence-readiness.mjs parity|report'); process.exit(2) }
