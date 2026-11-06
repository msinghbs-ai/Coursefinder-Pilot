// Guards: CF-247 (S69) Phase 3 CI deployment; Admin #382 exclusive controller ownership and production entry-point gate (6 Nov 2026).
// CF-247 (S69) Phase 3, 19 Oct 2026 (Platform Admin 09:29 "every function and database change deploys through the workflow"; the
// consumer API is not affected); Admin #382 controller ownership and production-entry-point adoption.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { createHash } from 'node:crypto'
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
  const screenshots = fs.readFileSync('.github/workflows/ui-review-screenshots.yml', 'utf8')
  for (const workflow of [component, archive, screenshots]) {
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
  const capture = stepRun(screenshots, 'Verify controller authority for the fixed capture inputs') + '\n' + stepRun(screenshots, 'Capture screens')
  expect(screenshots).toContain("if: always() && steps.controller_gate.outcome == 'success'")
  expect(screenshots.indexOf('Verify controller authority')).toBeLessThan(screenshots.indexOf('      - name: Capture screens'))
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
    script('npx', 'echo CAPTURE >> "$GUARD_TEST_EVENTS"\n')
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
      DEFINITION: path.join(tmp, 'fixture.json'), SHOW_RUN: '123',
      UAT_BASE_URL: 'https://coursefinder-pilot.techm.workers.dev', SCREENS: 'jobs', ADAPTER_FILTERS: '' }
    const fixed = { ...process.env, UAT_BASE_URL: env.UAT_BASE_URL, SCREENS: env.SCREENS, ADAPTER_FILTERS: env.ADAPTER_FILTERS, STUDYSEARCH_UAT_ALLOWED_ORIGIN: env.UAT_BASE_URL }
    // Pure readers validate the independent credential target without a lease;
    // all five browser entrypoints run the same check before browser execution.
    const credentialWorkflows = ['m2-4-ux-audit.yml', 'release-currentness-deployed.yml',
      'deployed-uat.yml', 'deployed-weekly.yml', 'ui-review-screenshots.yml']
    for (const file of credentialWorkflows) {
      const workflow = fs.readFileSync(`.github/workflows/${file}`, 'utf8')
      expect(workflow, file).toContain("STUDYSEARCH_UAT_ALLOWED_ORIGIN: ${{ vars.STUDYSEARCH_UAT_ALLOWED_ORIGIN || 'https://coursefinder-pilot.techm.workers.dev' }}")
      expect(workflow.indexOf('--validate-uat-target'), file).toBeGreaterThan(-1)
      expect(workflow.indexOf('--validate-uat-target'), file).toBeLessThan(workflow.indexOf('npx playwright test'))
    }
    const trusted = execFileSync(realPython, ['scripts/ci/controller-guard.py', '--validate-uat-target'], { env: fixed, encoding: 'utf8' })
    expect(JSON.parse(trusted).validation).toBe('pass')
    for (const target of ['http://coursefinder-pilot.techm.workers.dev', 'https://coursefinder-pilot.techm.workers.dev.evil.example',
      'https://evil-coursefinder-pilot.techm.workers.dev', 'https://coursefinder-pilot.techm.workers.dev@evil.example',
      'https://user:password@coursefinder-pilot.techm.workers.dev', 'https://coursefinder-pilot.techm.workers.dev:443',
      'https://coursefinder-pilot.techm.workers.dev\\@evil.example', 'https://coursefinder-pilot.techm.workers.dev/other']) {
      const denied = spawnSync(realPython, ['scripts/ci/controller-guard.py', '--validate-uat-target'], {
        env: { ...fixed, UAT_BASE_URL: target }, encoding: 'utf8', timeout: 15000,
      })
      expect(denied.error).toBeUndefined()
      expect(denied.status, target).toBe(1)
      expect(denied.stderr, target).toContain('UAT target origin does not match')
    }
    // A choice input is still untrusted shell data when dispatched through API.
    const deployed = fs.readFileSync('.github/workflows/deployed-uat.yml', 'utf8')
    const tierRun = stepRun(deployed, 'Resolve validation tier').replaceAll('${{ github.event_name }}', 'workflow_dispatch')
    expect(tierRun).not.toContain('${{ inputs.')
    for (const tier of ['targeted', 'integration', 'acceptance', `targeted'; touch ${path.join(tmp, 'injected-tier')}; #`]) {
      const result = spawnSync('bash', ['-eo', 'pipefail', '-c', tierRun], {
        env: { ...env, REQUESTED_UAT_TIER: tier, GITHUB_OUTPUT: path.join(tmp, 'tier-output') }, encoding: 'utf8', timeout: 15000,
      })
      expect(result.error).toBeUndefined()
      expect(result.status, tier).toBe(['targeted', 'integration', 'acceptance'].includes(tier) ? 0 : 1)
      expect(fs.existsSync(path.join(tmp, 'injected-tier'))).toBe(false)
    }
    const resource = execFileSync(realPython, ['scripts/ci/controller-guard.py', '--print-ui-review-resource'], { env: fixed, encoding: 'utf8' }).trim()
    expect(resource).toBe('ui_review_sha256:' + createHash('sha256').update('ui-review-inputs-v1\n' + JSON.stringify([fixed.UAT_BASE_URL, fixed.SCREENS, fixed.ADAPTER_FILTERS])).digest('hex'))
    const repurposed = spawnSync(realPython, ['scripts/ci/controller-guard.py', '--entry-point', 'ui-review-screenshots', '--resource', resource], {
      env: { ...fixed, UAT_BASE_URL: fixed.UAT_BASE_URL + '/' }, encoding: 'utf8', timeout: 15000,
    })
    expect(repurposed.error).toBeUndefined()
    expect(repurposed.status).toBe(1)
    expect(repurposed.stderr).toContain('UI review input resource differs')
    for (const [shell, action] of [[update, 'WRITE'], [exporting, 'WRITE'], [capture, 'CAPTURE']]) for (const status of ['1', '0']) {
      fs.rmSync(events, { force: true })
      const result = spawnSync('bash', ['-eo', 'pipefail', '-c', shell], { env: { ...env, GUARD_TEST_STATUS: status }, encoding: 'utf8', timeout: 15000 })
      expect(result.error).toBeUndefined()
      expect(result.status, result.stderr).toBe(Number(status))
      expect(fs.readFileSync(events, 'utf8').trim().split('\n')).toEqual(status === '0' ? ['GUARD', action] : ['GUARD'])
    }
    // The two privileged throwaway-project writers are deliberately outside
    // production reservations: prove both reject the Pilot before any request.
    const pilot = 'a'.repeat(20)
    for (const file of ['db-baseline-rebuild-test.yml', 'db-migration-test.yml']) {
      fs.rmSync(events, { force: true })
      const workflow = fs.readFileSync(`.github/workflows/${file}`, 'utf8')
      const preflight = stepRun(workflow, 'Confirm the target is the throwaway test project').replaceAll('${{ vars.SUPABASE_PROJECT_REF }}', pilot)
      const refused = spawnSync('bash', ['-eo', 'pipefail', '-c', preflight], { env: { ...env, REF: pilot }, encoding: 'utf8', timeout: 15000 })
      expect(refused.error, file).toBeUndefined()
      expect(refused.status, file).toBe(1)
      expect(refused.stdout, file).toContain('Refused: that is the Pilot project')
      expect(fs.existsSync(events), file).toBe(false)
    }
    // Dispatch data is validated before requests and never interpolated into
    // shell source, including the evidence workflow's PR and filename inputs.
    const privilegedInputs = ['deploy-edge-functions.yml', 'db-function-snapshot.yml', 'db-schema-dump.yml', 'edge-drift-check.yml', 'test-evidence.yml']
    for (const file of privilegedInputs) {
      const workflow = fs.readFileSync(`.github/workflows/${file}`, 'utf8')
      const blocks = [...workflow.matchAll(/^        run: (?:\|[^\n]*\n((?:          [^\n]*\n|\n)*)|([^\n]+))/gm)]
      expect(blocks.length, file).toBeGreaterThan(0)
      for (const block of blocks) expect(block[1] || block[2], file).not.toMatch(/\$\{\{\s*inputs\./)
    }
    const dispatch = { ...env, REF: pilot, TARGET_REF: pilot, EXPECTED_REF: pilot, FUNCTIONS: 'coverage-sweep, coverage-admit', DELETE_FUNCTIONS: '', PATTERN: '.*' }
    const runProbe = (body, values, pass, label) => {
      fs.rmSync(events, { force: true })
      const result = spawnSync('bash', ['-eo', 'pipefail', '-c', body], { env: { ...dispatch, ...values }, encoding: 'utf8', timeout: 15000 })
      expect(result.error, label).toBeUndefined()
      expect(result.status, `${label}: ${result.stderr}`).toBe(pass ? 0 : 1)
      return fs.existsSync(events) ? fs.readFileSync(events, 'utf8').trim().split('\n') : []
    }
    const injected = `$(touch ${path.join(tmp, 'injected-dispatch')})`
    for (const file of privilegedInputs.slice(0, 4)) {
      const workflow = fs.readFileSync(`.github/workflows/${file}`, 'utf8')
      const preflight = stepRun(workflow, 'Confirm target project')
      expect(runProbe(preflight, {}, true, file)).toEqual([])
      for (const ref of [injected, pilot + '\nwhoami', 'b'.repeat(20)]) {
        expect(runProbe(preflight, { REF: ref, TARGET_REF: ref }, false, `${file} project`)).toEqual([])
      }
      if (['deploy-edge-functions.yml', 'edge-drift-check.yml'].includes(file)) {
        for (const list of [injected, 'coverage-sweep;whoami', 'coverage-sweep\ncoverage-admit']) {
          expect(runProbe(preflight, { FUNCTIONS: list }, false, `${file} functions`)).toEqual([])
        }
      }
      if (file === 'deploy-edge-functions.yml') {
        expect(runProbe(preflight, { DELETE_FUNCTIONS: injected }, false, 'retired list')).toEqual([])
        for (const name of ['Deploy', 'Delete retired functions']) {
          expect(runProbe(stepRun(workflow, name), { DELETE_FUNCTIONS: 'layer3-model-routing', GUARD_TEST_STATUS: '1' }, false, name)).toEqual(['GUARD'])
        }
      }
      if (file === 'db-function-snapshot.yml') expect(runProbe(preflight, { PATTERN: injected }, false, 'definition pattern')).toEqual([])
    }
    const evidenceWorkflow = fs.readFileSync('.github/workflows/test-evidence.yml', 'utf8')
    const resolvePr = stepRun(evidenceWorkflow, 'Resolve the pull request and its head revision')
    script('gh', 'echo GET >> "$GUARD_TEST_EVENTS"\necho \'{"head":{"sha":"fixture"},"base":{"sha":"fixture"},"draft":true,"labels":[]}\'\n')
    const evidenceEnv = { GITHUB_EVENT_NAME: 'workflow_dispatch', REPO: 'isolated/repository', GITHUB_OUTPUT: path.join(tmp, 'pr-output') }
    expect(runProbe(resolvePr, { ...evidenceEnv, REQUESTED_PR: '895' }, true, 'valid PR')).toEqual(['GET'])
    for (const pr of [injected, '895;whoami', '-1', '0', '895\nwhoami']) {
      expect(runProbe(resolvePr, { ...evidenceEnv, REQUESTED_PR: pr }, false, 'invalid PR')).toEqual([])
    }
    // A changed metadata filename remains one literal --changed argument.
    script('node', `
if [[ "$1" == scripts/test-evidence.mjs ]]; then
  prev=''
  for arg in "$@"; do
    if [[ "$prev" == --changed ]]; then printf '%s' "$arg" > "$RUNNER_TEMP/changed-argument"; fi
    prev="$arg"
  done
  exit 0
fi
exec "$GUARD_TEST_NODE" "$@"
`)
    const bundle = stepRun(evidenceWorkflow, 'Assemble the evidence bundle')
      .replaceAll("${{ steps.mode.outputs.mode }}", 'reuse')
      .replace(/\$\{\{\s*steps\.[^.]+\.outcome\s*\}\}/g, 'success')
      .replace(/\$\{\{[^}]+\}\}/g, 'fixture')
    const filename = `docs/platform/${injected}.md`
    expect(runProbe(bundle, { CHANGED_SINCE_EVIDENCE: filename, GUARD_TEST_NODE: process.execPath }, true, 'literal changed argument')).toEqual([])
    expect(fs.readFileSync(path.join(tmp, 'changed-argument'), 'utf8')).toBe(filename)
    expect(fs.existsSync(path.join(tmp, 'injected-dispatch'))).toBe(false)
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

