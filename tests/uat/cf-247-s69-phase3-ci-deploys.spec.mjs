// Guards: CF-247 (S69) Phase 3 CI deployment; Admin #382 exclusive controller ownership and production entry-point gate (6 Nov 2026).
// CF-247 (S69) Phase 3, 19 Oct 2026 (Platform Admin 09:29 "every function and database change deploys through the workflow"; the
// consumer API is not affected); Admin #382 controller ownership and production-entry-point adoption.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFileSync, spawnSync } from 'node:child_process'
const list = JSON.parse(fs.readFileSync('.github/edge-functions.json', 'utf8')).functions
const onMerge = fs.readFileSync('.github/workflows/deploy-on-merge.yml', 'utf8')
const drift = fs.readFileSync('.github/workflows/edge-drift-check.yml', 'utf8')
const manual = fs.readFileSync('.github/workflows/deploy-edge-functions.yml', 'utf8')
const apply = fs.readFileSync('scripts/ci/apply-migration.sh', 'utf8')
const deploy = fs.readFileSync('scripts/ci/deploy-function.sh', 'utf8')

test('every function folder is in the deploy list and every listed function has a folder', () => {
  const folders = fs.readdirSync('supabase/functions').filter(d => !d.startsWith('_') && fs.existsSync(`supabase/functions/${d}/index.ts`)).sort()
  expect(Object.keys(list).sort()).toEqual(folders)
  for (const v of Object.values(list)) expect(typeof v).toBe('boolean')
})

test('consumer API functions keep their recorded verify_jwt (Decision 266)', () => {
  for (const f of ['website-api-v2', 'wix-course-api', 'website-course-api', 'zoho-api-v2', 'zoho-course-api']) expect(list[f], f).toBe(false)
})

test('deploy on merge: new migrations first, in order, then changed functions; the Pilot only', () => {
  expect(onMerge).toMatch(/on:\n  push:\n    branches: \[main\]/)
  expect(onMerge).toContain("git diff --name-only --diff-filter=A \"$BEFORE\" \"$AFTER\" -- 'supabase/migrations/*.sql' | xargs -r -n1 basename | sort")
  expect(onMerge).toContain('scripts/ci/apply-migration.sh "$f"')
  expect(onMerge).toContain('scripts/ci/deploy-function.sh "$fn"')
  expect(onMerge.indexOf('Apply new migrations')).toBeLessThan(onMerge.indexOf('Deploy changed edge functions'))
  expect(onMerge).toContain('REF: ${{ vars.SUPABASE_PROJECT_REF }}')
  expect(manual).toContain('scripts/ci/deploy-function.sh "$fn"')
})

test('the shared scripts keep the safeguards', () => {
  expect(apply).toContain("grep -nEi '^(drop|delete|truncate)\\b|^alter table .* drop '")
  expect(apply).toContain('already applied (version $ver in the history); skipped')
  expect(apply).toContain('if [ "$got" != "$want" ]; then')
  expect(deploy).toContain('else "missing" end') // 19 Oct 2026: has(), not // (which read false as missing)
})

test('daily drift check fails on drift or on a function deployed by hand', () => {
  expect(drift).toContain("cron: '15 20 * * *'")
  expect(drift).toContain('Live but not in .github/edge-functions.json (deployed by hand)')
  expect(drift).toContain('if [ "${DRIFT:-0}" = "1" ]; then exit 1; fi')
})

test('retired probes and Layer 3 functions are on the retired list and have no source', () => {
  const retired = manual.match(/RETIRED="([^"]*)"/)[1].split(/\s+/).filter(Boolean)
  for (const f of ['layer1-ca-ab-alis-probe', 'layer1-ca-qc-audit', 'layer1-ca-northern-code-audit', 'layer3-model-routing', 'layer3-work-dispatch', 'layer3-work-interpret']) {
    expect(retired, f).toContain(f)
    expect(fs.existsSync(`supabase/functions/${f}`), f).toBe(false)
  }
})

test('Phase 5: every workflow pins the Supabase CLI (no "latest", which failed on a rate limit)', () => {
  for (const f of fs.readdirSync('.github/workflows')) {
    const y = fs.readFileSync(`.github/workflows/${f}`, 'utf8')
    if (y.includes('supabase/setup-cli')) expect(y, f).not.toMatch(/version:\s*latest/)
  }
})

test('deploy-function.sh reads verify_jwt false as false, not as missing (19 Oct 2026 fault)', () => {
  expect(deploy).not.toContain('.functions[$f] // "missing"')
  expect(deploy).toContain(`'if (.functions | has($f)) then (.functions[$f] | tostring) else "missing" end'`)
  for (const [f, want] of [['zoho-api-v2', 'false'], ['ranking-evidence-export', 'true'], ['nope', 'missing']]) {
    const got = execFileSync('jq', ['-r', '--arg', 'f', f, 'if (.functions | has($f)) then (.functions[$f] | tostring) else "missing" end', '.github/edge-functions.json']).toString().trim()
    expect(got, f).toBe(want)
  }
})

test('Admin #382 controller adapter refuses stale, unreserved or changed-code production writes', () => {
  // Behavioural negative/positive cases execute the same pure gate called by production.
  expect(() => execFileSync('python3', ['scripts/ci/controller-guard.py', '--self-test'], { stdio: 'pipe' })).not.toThrow()
  // A recovery candidate may predate the guard. Run the protected workflow's
  // staged verifier, never a missing/replaced file from that candidate.
  for (const file of ['db-apply-migration.yml', 'deploy-edge-functions.yml', 'db-archive-export.yml']) {
    const workflow = fs.readFileSync(`.github/workflows/${file}`, 'utf8')
    const trusted = workflow.indexOf('ref: ${{ github.workflow_sha }}')
    const staged = workflow.indexOf('install -m 0500 scripts/ci/controller-guard.py')
    const candidate = workflow.indexOf('ref: ${{ inputs.git_ref }}')
    expect(trusted, file).toBeGreaterThanOrEqual(0)
    expect(staged, file).toBeGreaterThan(trusted)
    expect(candidate, file).toBeGreaterThan(staged)
    expect(workflow, file).toContain('python3 "$RUNNER_TEMP/studysearch-controller-guard.py" --entry-point')
  }
  const component = fs.readFileSync('.github/workflows/component-register.yml', 'utf8')
  const archive = fs.readFileSync('.github/workflows/db-archive-export.yml', 'utf8')
  for (const workflow of [component, archive]) {
    expect(workflow).toContain('studysearch-controller-production')
    expect(workflow).toContain('cancel-in-progress: false')
    for (const name of ['CONTROLLER_EXECUTION_ID', 'CONTROLLER_GENERATION', 'CONTROLLER_OPERATION_ID']) expect(workflow).toContain(name + ':')
  }
  // Run the actual workflow shell steps with local executables standing in for
  // network writes. This catches a guard failure followed by an accidental write.
  // The real adapter's authority/resource decisions run in the self-test above.
  const stepRun = (workflow, name) => {
    const section = workflow.split('      - name: ' + name + '\n')[1]?.split(/\n      - /)[0]
    const body = section?.split('        run: |\n')[1]
    expect(body, name).toBeTruthy()
    return body.replace(/^          /gm, '')
  }
  const update = stepRun(component, 'Update the register')
  const exporting = stepRun(archive, 'Export, read back and check')
  const showing = stepRun(archive, 'Show an earlier manifest without creating a bucket or exporting')
  const outputs = new Map(['export.log', 'manifest.json'].map(file => [file, fs.existsSync(file) ? fs.readFileSync(file) : null]))
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'controller-workflow-gates-'))
  try {
    const bin = path.join(tmp, 'bin'); fs.mkdirSync(bin)
    const realPython = execFileSync('which', ['python3'], { encoding: 'utf8' }).trim()
    const script = (name, body) => fs.writeFileSync(path.join(bin, name), '#!/usr/bin/env bash\nset -euo pipefail\n' + body, { mode: 0o700 })
    script('python3', `
if [[ "$1" == *controller-guard.py ]]; then
  echo GUARD >> "$GUARD_TEST_EVENTS"
  exit "$GUARD_TEST_STATUS"
fi
if [[ "$1" == scripts/archive_export.py ]]; then
  echo WRITE >> "$GUARD_TEST_EVENTS"
  echo 'Isolated export fixture completed'
  echo 'MANIFEST {"prefix":"fixture","sets":[]}'
  exit 0
fi
exec "$GUARD_TEST_PYTHON" "$@"
`)
    script('curl', `
if [[ "$*" == *"-X POST"* ]]; then
  echo WRITE >> "$GUARD_TEST_EVENTS"
  while [[ $# -gt 0 ]]; do if [[ "$1" == -o ]]; then printf '[{"ingest":0,"sync":0}]' > "$2"; break; fi; shift; done
  printf 200
elif [[ "$*" == *api-keys* ]]; then
  echo GET >> "$GUARD_TEST_EVENTS"
  echo '[{"name":"service_role","api_key":"isolated-test-key"}]'
else
  echo GET >> "$GUARD_TEST_EVENTS"
  echo '{"definition":"fixture.json","git_sha":"fixture","sets":[]}'
fi
`)
    fs.writeFileSync(path.join(tmp, 'calls.json'), '{"result":[]}')
    fs.writeFileSync(path.join(tmp, 'fixture.json'), '{"bucket":"fixture-bucket","prefix":"fixture"}')
    const events = path.join(tmp, 'events')
    const env = { ...process.env, PATH: `${bin}${path.delimiter}${process.env.PATH}`, RUNNER_TEMP: tmp,
      GITHUB_STEP_SUMMARY: path.join(tmp, 'summary'), GUARD_TEST_EVENTS: events, GUARD_TEST_PYTHON: realPython,
      REF: 'isolated-fixture', PROJECT_REF: 'isolated-fixture', SUPABASE_ACCESS_TOKEN: 'isolated-test-token',
      DEFINITION: path.join(tmp, 'fixture.json'), SHOW_RUN: '123' }
    for (const shell of [update, exporting]) for (const status of ['1', '0']) {
      fs.rmSync(events, { force: true })
      const result = spawnSync('bash', ['-eo', 'pipefail', '-c', shell], { env: { ...env, GUARD_TEST_STATUS: status }, encoding: 'utf8', timeout: 15000 })
      expect(result.error).toBeUndefined()
      expect(result.status, result.stderr).toBe(Number(status))
      expect(fs.readFileSync(events, 'utf8').trim().split('\n')).toEqual(status === '0' ? ['GUARD', 'WRITE'] : ['GUARD'])
    }
    // SHOW_RUN must bypass the bucket-creating exporter and use GETs only.
    fs.rmSync(events, { force: true })
    const reader = spawnSync('bash', ['-eo', 'pipefail', '-c', showing], { env: { ...env, GUARD_TEST_STATUS: '1' }, encoding: 'utf8', timeout: 15000 })
    expect(reader.error).toBeUndefined()
    expect(reader.status, reader.stderr).toBe(0)
    expect(fs.readFileSync(events, 'utf8').trim().split('\n')).toEqual(['GET', 'GET'])
    for (const prefix of ['../outside', `$(touch ${path.join(tmp, 'injected-command')})`]) {
      fs.rmSync(events, { force: true })
      fs.writeFileSync(path.join(tmp, 'fixture.json'), JSON.stringify({ bucket: 'fixture-bucket', prefix }))
      const unsafe = spawnSync('bash', ['-eo', 'pipefail', '-c', showing], { env, encoding: 'utf8', timeout: 15000 })
      expect(unsafe.error).toBeUndefined()
      expect(unsafe.status).not.toBe(0)
      expect(unsafe.stderr + unsafe.stdout).toContain('Refused unsafe archive bucket or prefix')
      expect(fs.existsSync(events)).toBe(false)
      expect(fs.existsSync(path.join(tmp, 'injected-command'))).toBe(false)
    }
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true })
    for (const [file, original] of outputs) {
      if (original === null) fs.rmSync(file, { force: true })
      else fs.writeFileSync(file, original)
    }
  }
  // Production credentials are moving out of repository scope. Keep reviewed
  // readers as well as writers attached to the existing environment so that
  // old, unscoped workflow revisions lose access without stranding reporting.
  // This proves wiring only; the account's protection policy is a live gate.
  const privileged = /secrets\.(SUPABASE_ACCESS_TOKEN|SUPABASE_DB_PASSWORD|COURSEFINDER_UAT_EMAIL|COURSEFINDER_UAT_PASSWORD|ADMIN_REPO_TOKEN)/
  for (const file of fs.readdirSync('.github/workflows')) {
    const workflow = fs.readFileSync(`.github/workflows/${file}`, 'utf8')
    const [header, jobs = ''] = workflow.split(/\njobs:\s*\n/)
    const globalCredential = privileged.test(header)
    for (const block of jobs.matchAll(/^  ([A-Za-z0-9_-]+):\s*\n([\s\S]*?)(?=^  [A-Za-z0-9_-]+:\s*\n|(?![\s\S]))/gm)) {
      if (globalCredential || privileged.test(block[2])) {
        expect(block[2], `${file}:${block[1]}`).toMatch(/^    environment: pilot\s*$/m)
      }
    }
  }
})

