// CF-247 (S69) Phase 3, 19 Oct 2026 (Platform Admin 09:29 "every function and database change deploys through the workflow"; the
// consumer API is not affected).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { execFileSync } from 'node:child_process'
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
