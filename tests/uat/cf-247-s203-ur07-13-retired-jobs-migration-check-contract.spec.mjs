// Guards: StudySearch usability remediation UR-07 and UR-13 (Platform Admin mandate 1 Nov 2026 11:48, Tranche C; admin record §36): a retiring or retired job cannot be resumed, run or re-scheduled singly or by Resume area and shows as Retired without controls; and the migration helper skips an already-applied version only when its recorded md5 equals the file, refusing a changed file before anything runs.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFileSync } from 'node:child_process'
import { mockAdmin } from './support/admin-mock.mjs'

const m = fs.readFileSync('supabase/migrations/20261101070000_cf247_ur07_retired_jobs.sql', 'utf8')
const code = (s) => s.replace(/--[^\n]*/g, '')

test('UR-07 migration: md5-guarded; refuses switching on retired jobs; area resume skips them; read reports retirement', () => {
  expect(m).toContain("select pg_temp.edit_once('security.admin_automation_control_v1(text,text,jsonb)', 'd90af04ccda6b74a88a506c58c0299fb', '30c319b8ed37dbc1df6700a0d3f5c46f', array[")
  expect(m).toContain("select pg_temp.edit_once('security.admin_automations_read_v1()', '81d5e16a3b3101c9e308696377886c68', 'f5120aedfd35a82bdf905597cec0267f', array[")
  expect(m).toContain("and not (p_action='resume_area' and exists (select 1 from pipeline.component_register cr where cr.kind='job' and cr.name=j2.jobname and cr.status in ('retiring','retired'))) loop")
  expect(m).toContain("if p_action <> 'pause' and exists (select 1 from pipeline.component_register cr where cr.kind='job' and cr.name=p_job and cr.status in ('retiring','retired')) then")
  expect(m).toContain("'retirement',(select jsonb_build_object('status',cr.status,'replaced_by',cr.replaced_by,'retire_after',cr.retire_after)")
  expect(code(m)).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

// UR-13: the real helper against a stand-in for the Management API (absent, identical and changed versions)
function run(history) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ur13-'))
  const bin = path.join(dir, 'bin'); fs.mkdirSync(bin)
  fs.mkdirSync(path.join(dir, 'supabase/migrations'), { recursive: true })
  const file = '20991231000000_ur13_probe.sql'
  fs.writeFileSync(path.join(dir, 'supabase/migrations', file), 'select 1;\n')
  const log = path.join(dir, 'calls.log')
  fs.writeFileSync(path.join(bin, 'curl'), `#!/usr/bin/env bash
out=""; data=""; while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift;; --data) data="\${2#@}"; shift;; esac; shift; done
qq=$(jq -r .query "$data"); echo "$qq" | head -c 120 >> "${log}"; echo >> "${log}"
if echo "$qq" | grep -q 'count(\\*)::int'; then echo '[{"n": ${history ? 1 : 0}}]' > "$out"
elif echo "$qq" | grep -q '^begin;'; then echo '[]' > "$out"
elif echo "$qq" | grep -q 'md5(replace'; then echo '[{"m": "${history || ''}"}]' > "$out"; fi
printf 200`)
  fs.chmodSync(path.join(bin, 'curl'), 0o755)
  let status = 0, out = ''
  try { out = execFileSync('bash', [path.resolve('scripts/ci/apply-migration.sh'), file], { cwd: dir, env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, SUPABASE_ACCESS_TOKEN: 't', REF: 'r' }, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }) }
  catch (e) { status = e.status; out = String(e.stdout || '') + String(e.stderr || '') }
  return { status, out, calls: fs.readFileSync(log, 'utf8') }
}
const md5 = 'd8da4fd8f5d3d5a3d3b3d4d0b0b2b9a5' // not the file's md5

test('UR-13: absent version applies once; identical version skips after comparing; changed version is refused before anything runs', () => {
  const fileMd5 = execFileSync('bash', ['-c', "printf 'select 1;\\n' | md5sum | cut -c1-32"], { encoding: 'utf8' }).trim()
  const absent = run(null)
  expect(absent.calls).toContain('begin;')
  const same = run(fileMd5)
  expect(same.status).toBe(0)
  expect(same.out).toContain('already applied (version 20991231000000 in the history); skipped (recorded md5')
  expect(same.calls).not.toContain('begin;')
  const changed = run(md5)
  expect(changed.status).toBe(1)
  expect(changed.out).toContain('an applied migration was changed. Nothing was run.')
  expect(changed.calls).not.toContain('begin;')
})

test.describe('mocked browser', () => {
  test('Automations: a retiring job shows Retiring with its replacement and no Resume, run or schedule controls', async ({ page }) => {
    await mockAdmin(page, { rank: 6 })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_automations_read', (route) => route.fulfill({ json: { generated_at: '2026-11-01T03:00:00Z', rank: 6, events: [], jobs: [
      { job: 'l4-rule-low-agreement', area: 'Layer 4', sort: 1, label: 'Review rule: sources disagree', description: 'RETIRED', schedule: '17 3 * * *', active: false, control_rank: 6, catalogued: true, runs_24h: 0, failed_24h: 0,
        retirement: { status: 'retiring', replaced_by: 'Layer 4 review', retire_after: '2026-11-14' } },
      { job: 'layer4-ok', area: 'Layer 4', sort: 2, label: 'Active job', description: '', schedule: '*/10 * * * *', active: false, control_rank: 6, catalogued: true, runs_24h: 1, failed_24h: 0 }] } }))
    await page.goto('/#scheduled-jobs')
    const retired = page.locator('[data-job="l4-rule-low-agreement"]')
    await expect(retired).toContainText('Retiring')
    await expect(retired.locator('[data-retired-job]')).toContainText('replaced by Layer 4 review')
    await expect(retired.getByRole('button', { name: /Resume/ })).toHaveCount(0)
    await expect(retired.getByRole('combobox')).toHaveCount(0)
    await expect(page.locator('[data-job="layer4-ok"]').getByRole('button', { name: /Resume/ })).toBeVisible()
  })
})
