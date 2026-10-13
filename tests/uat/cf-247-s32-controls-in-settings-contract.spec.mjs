// CF-247 v2.15.269 (S32): Platform Admin, 13 Oct 2026 21:43: "Bring all controls to UI and make sure in future it's not getting hard coded.
// All controls need to be reflected and control in UI. Use current recommended settings and choices."
// The register, the jobs and functions that read it, the worker settings, and the guards that stop new fixed values: this file checks every
// migration from 20261013012900 on, and the worker, so a number written into a job or a business rule fails the build.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const MIG_DIR = 'supabase/migrations'
const FIRST = '20261013012900'
const mig = fs.readFileSync(`${MIG_DIR}/${FIRST}_cf247_all_controls_in_settings.sql`, 'utf8')
const worker = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const SETTING_CALL = /(pipeline_num_v1|scholarship_setting|fc_setting_num_v1)\('[^']+',\s*(\d+(\.\d+)?|null)\)/g

// A job command with a number written into it (a setting call is not counted). The same rule as security.controls_check_v1().
export function fixedInJob(cmd) {
  const s = cmd.replace(/''/g, "'").replace(SETTING_CALL, 'S')
  return /\(\s*\d+\s*[,)]|,\s*\d+\s*\)/.test(s.replace(/'[^']*'/g, 'T')) || /"\w+"\s*:\s*\d/.test(s)
}
// Business rules written into a function body: day/hour/week/month intervals and limits of 100 or more, unless marked "-- fixed: <why>".
export function fixedInFunctions(sql) {
  const out = []
  for (const m of sql.matchAll(/CREATE OR REPLACE FUNCTION ([a-z_]+\.[a-z0-9_]+)\([\s\S]*?\$function\$([\s\S]*?)\$function\$/g)) {
    const [, name, body] = m
    if (/\.admin_|_read$/.test(name)) continue // screens: display windows, not controls
    for (const raw of body.split('\n')) {
      const l = raw.trim()
      if (l.startsWith('--') || l.includes('-- fixed:')) continue
      if (/interval\s+'\d+\s*(day|days|hour|hours|week|weeks|month|months)\b/i.test(l) || /\blimit\s+\d{3,}/i.test(l)) out.push(`${name}: ${l.slice(0, 120)}`)
    }
  }
  return out
}

test('the register: one settings table, read at run time, every default is today’s value', () => {
  expect(mig).toContain("values ('pipeline', 'Pipeline (job sizes, re-reads and retries)', 'platform'")
  expect(mig).toContain("select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default)")
  for (const k of ["'batch.coverage_admit'", "'reread.scholarship_page_days'", "'onboarding.proposal_attempts'", "'retry.no_website_days'", "'search_stop_window_days'", "'map_limit_course_site'"]) expect(mig).toContain(k)
  expect(mig).toContain("('pipeline', 'reread.scholarship_page_days', 'Read a scholarship page again after'") // 90 days kept (recommended)
  expect(mig).toMatch(/'reread\.scholarship_page_days'[^\n]*to_jsonb\(90\)/)
  expect(mig).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  // the post-check refuses the migration if any running job still has a number written into it
  expect(mig).toContain("raise exception 'v2.15.269 post-check: % running job(s) still have a number written into them', v_n")
})

test('every job command in the migration reads its size from a setting', () => {
  const cmds = [...mig.matchAll(/command := '((?:[^']|'')*)'\);/g)].map(m => m[1].replace(/''/g, "'"))
  expect(cmds.length).toBeGreaterThanOrEqual(31)
  for (const c of cmds) expect(fixedInJob(c), c).toBe(false)
  expect(fixedInJob("select security.adapter_overwrite_v1(200)")).toBe(true)
  expect(fixedInJob(`select pipeline.svc_pilot_submit_nonce('coverage-sweep','{"mode":"read","limit":60}'::jsonb)`)).toBe(true)
  expect(fixedInJob("select security.adapter_overwrite_v1(security.pipeline_num_v1('batch.adapter_overwrite', 200)::int)")).toBe(false)
})

test('guard: no migration from v2.15.269 on writes a number into a job or a business rule into a function', () => {
  const files = fs.readdirSync(MIG_DIR).filter(f => f.endsWith('.sql') && f.slice(0, 14) >= FIRST).sort()
  expect(files[0]).toBe(`${FIRST}_cf247_all_controls_in_settings.sql`)
  for (const f of files) {
    const sql = fs.readFileSync(`${MIG_DIR}/${f}`, 'utf8')
    expect(fixedInFunctions(sql), f).toEqual([])
    for (const m of sql.matchAll(/cron\.schedule\(\s*'[^']+'\s*,\s*'[^']+'\s*,\s*'((?:[^']|'')*)'\s*\)/g)) expect(fixedInJob(m[1].replace(/''/g, "'")), `${f}: ${m[1]}`).toBe(false)
    for (const m of sql.matchAll(/command\s*(?::=|=>)\s*'((?:[^']|'')*)'/g)) expect(fixedInJob(m[1].replace(/''/g, "'")), `${f}: ${m[1]}`).toBe(false)
  }
})

test('worker v0.21.7: the Firecrawl proxy, site map sizes and search results come from settings', () => {
  expect(worker).toContain('const WORKER = "coverage-sweep-worker-v0.21.7";')
  expect(worker).toContain('const ws: Record<string, unknown> = (await rpc("svc_worker_settings_v1", {}).catch(() => ({}))) || {};')
  expect(worker).not.toContain('proxy: "basic"')
  for (const line of worker.split('\n').filter(l => l.includes('api.firecrawl.dev'))) expect(line, line.slice(0, 120)).not.toMatch(/\blimit:\s*\d/)
  expect(mig).toContain("grant execute on function public.svc_worker_settings_v1() to service_role;")
})

test('live guard: the controls check is a notice and shows on Pipeline settings', () => {
  expect(mig).toContain("'key', 'pipeline:0:fixed_value:' || c.jobname")
  expect(fs.readFileSync('src/Toolsets.jsx', 'utf8')).toContain("case'pipeline:fixed_value':return{need:'action'")
  expect(fs.readFileSync('src/PipelineSettings.jsx', 'utf8')).toContain('<SettingsRegister onError={onError}/>')
})

test.describe('mocked browser', () => {
  test('Pipeline settings: controls check, the register by section, a change needs a reason; policy tables change with a reason', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#environment')
    const reg = page.locator('[data-settings-register]').first()
    await expect(reg.locator('[data-controls-check="ok"]')).toContainText('all 89 running jobs read their sizes from settings')
    const sec = reg.locator('[data-register-section="Job sizes"]')
    await sec.locator('.cf-card-toggle').click()
    const row = sec.locator('[data-register-setting="batch.coverage_admit"]')
    await expect(row).toContainText('Used by: coverage-admit (every 10 minutes)')
    await row.getByLabel('Admit official page and English').fill('400')
    const save = row.getByRole('button', { name: 'Save' })
    await expect(save).toBeDisabled()
    await row.getByLabel('Reason').fill('Smaller runs while the database is busy')
    await save.click()
    await expect.poll(() => page.l3calls.find(c => c.toolsets === 'setting')?.args).toEqual({ toolset: 'pipeline', key: 'batch.coverage_admit', value: 400, reason: 'Smaller runs while the database is busy' })
    const pol = page.locator('[data-policy-table="provider_fee_profiles"]')
    await pol.locator('.cf-card-toggle').click()
    const cell = pol.locator('[data-policy-cell="provider_fee_profiles.active:fp-1"]')
    await cell.getByRole('checkbox').uncheck()
    await cell.getByLabel('Reason').fill('Rule withdrawn by the provider')
    await cell.getByRole('button', { name: 'Save' }).click()
    await expect.poll(() => page.l3calls.find(c => c.policy)?.policy).toEqual({ p_table: 'provider_fee_profiles', p_row: 'fp-1', p_column: 'active', p_value: false, p_reason: 'Rule withdrawn by the provider' })
  })
})
