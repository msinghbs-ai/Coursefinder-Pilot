// Guards: CF-247 Operations load speed (Platform Admin P1, 10 Nov 2026): every cold load of Layer 2/3 > Operations answers well inside the 8 second API limit with no change to what the screen shows; the scheduler history behind the lane funnels is a stale-marked summary (never shown as current), and the migration, held scripts, fixture and workflow keep to the housekeeping and recovery rules.
// Source contract on the migration, the held scripts, the fixture and its workflow (the database behaviour itself is proved by tests/fixtures/operations-load-speed/run.sh, run in CI by operations-load-speed-test.yml), plus a mocked-browser check of the stale and unknown notes on the lane funnels. The central rules (G2 s32, G3 s57, housekeeping/G1 s42) are not repeated here.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { mockLaneFunnels, LANES } from './support/lane-funnel-mock.mjs'

const mig = fs.readFileSync('supabase/migrations/20261110020000_cf247_operations_load_speed.sql', 'utf8')
const rec = fs.readFileSync('supabase/held/operations_load_speed_forward_recovery.sql', 'utf8')
const eq = fs.readFileSync('supabase/held/operations_load_speed_equivalence.sql', 'utf8')
const run = fs.readFileSync('tests/fixtures/operations-load-speed/run.sh', 'utf8')
const after = fs.readFileSync('tests/fixtures/operations-load-speed/after.sql', 'utf8')
const idx = fs.readFileSync('tests/fixtures/operations-load-speed/index-benefit.sql', 'utf8')
const wf = fs.readFileSync('.github/workflows/operations-load-speed-test.yml', 'utf8')
const ui = fs.readFileSync('src/LaneFunnels.jsx', 'utf8')
const FUNCTIONS = ['security.lane_funnel_v1(text)', 'security.lane_funnel_refresh_v1(boolean)', 'security.intake_progress_repeats_v1()', 'security.process_results_recovery_v1()', 'public.admin_layer23(text,jsonb)']
const md5 = /^--   (\S+) ([0-9a-f]{32}) -> ([0-9a-f]{32})$/gm
const md5Rec = /^-- (\S+) ([0-9a-f]{32}) \(before the migration\) <- ([0-9a-f]{32}) \(after it\)$/gm
const code = (sql) => sql.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test.describe('Operations load speed: migration', () => {
  test('each of the five edited functions is guarded by the md5 of the live body, edits apply exactly once and the result is checked', () => {
    const rows = [...mig.matchAll(md5)]
    expect(rows.map((r) => r[1])).toEqual(FUNCTIONS)
    for (const r of rows) { expect(r[2]).not.toBe(r[3]); expect(mig).toContain(`pg_temp.edit_all('${r[1]}', '${r[2]}', '${r[3]}'`) }
    expect(mig).toContain('differs from the definition this change edits')
    expect(mig).toContain('must apply exactly once')
    expect(mig).toContain('has body md5')
    // no function is created or replaced wholesale except the new writer
    expect([...mig.matchAll(/create or replace function ([\w.]+)/gi)].map((m) => m[1])).toEqual(['security.lane_funnel_job_runs_refresh_v1', 'pg_temp.edit_all'])
  })

  test('the scheduler history is summarised once by the existing lane-funnel job: no new job, no scan of the run table in the read, a failure keeps the last good rows', () => {
    expect(mig).not.toMatch(/cron\.schedule\s*\(/i)
    expect(mig).toContain("perform security.lane_funnel_job_runs_refresh_v1(p_force);")
    const reader = mig.slice(mig.indexOf("select pg_temp.edit_all('security.lane_funnel_v1(text)'"), mig.indexOf("select pg_temp.edit_all('security.lane_funnel_refresh_v1(boolean)'"))
    // what the read becomes (the $new$ parts of its edits) never names the scheduler's run table
    const becomes = [...reader.matchAll(/\$new\$([\s\S]*?)\$new\$/g)].map((m) => code(m[1])).join('\n')
    expect(becomes.length).toBeGreaterThan(500)
    expect(becomes).not.toContain('cron.job_run_details')
    expect(becomes).toContain("'job_history'")
    expect(becomes).toContain("'history_known'")
    const writer = mig.slice(mig.indexOf('create or replace function security.lane_funnel_job_runs_refresh_v1'), mig.indexOf('create or replace function security.lane_funnel_job_runs_refresh_v1') + 5000)
    expect(writer).toContain('security definer')
    expect(writer).toMatch(/set search_path\s*(=|to)\s*''/)
    expect(writer).toContain('pg_backend_pid()')
    expect(writer).toContain('failed_at')
    expect(mig).toMatch(/revoke all on function security\.lane_funnel_job_runs_refresh_v1\(boolean\) from public, anon, authenticated/)
    expect(mig).toMatch(/alter table pipeline\.lane_funnel_job_runs enable row level security/)
  })

  test('the summary is made at the END of the lane-funnel run inside its own handler, so it is as recent as the run can make it and can never stop the run', () => {
    const refresh = mig.slice(mig.indexOf("select pg_temp.edit_all('security.lane_funnel_refresh_v1(boolean)'"), mig.indexOf("select pg_temp.edit_all('security.intake_progress_repeats_v1()'"))
    const added = [...refresh.matchAll(/\$new\$([\s\S]*?)\$new\$/g)].map((m) => m[1]).join('\n')
    expect(added).toMatch(/begin\s+perform security\.lane_funnel_job_runs_refresh_v1\(p_force\);\s+exception when others then\s+raise warning/)
    // it is placed after the stage counts: the only text after it is the restore of the statement time-out and the return
    expect(added.indexOf('lane_funnel_job_runs_refresh_v1')).toBeLessThan(added.indexOf("perform set_config('statement_timeout', v_prev, true)"))
    expect(refresh).not.toMatch(/pg_try_advisory_xact_lock[^$]*perform security\.lane_funnel_job_runs_refresh_v1/)
    expect(mig).toContain('is made before the stage counts, not at the end of the run')
  })

  test('a lane whose verdict would rest on a stale or unknown job history says unknown, and the two settings cannot leave the history stale for good', () => {
    const reader = mig.slice(mig.indexOf("select pg_temp.edit_all('security.lane_funnel_v1(text)'"), mig.indexOf("select pg_temp.edit_all('security.lane_funnel_refresh_v1(boolean)'"))
    const becomes = [...reader.matchAll(/\$new\$([\s\S]*?)\$new\$/g)].map((m) => m[1]).join('\n')
    expect(becomes).toContain("'job_history_state', v_jh_state")
    expect(becomes).toMatch(/when v_jh_state <> 'current' then 'unknown'/)
    expect(becomes).toMatch(/when coalesce\(v_off_switch, false\) or \(v_jobs_n > 0 and v_active = 0\) then 'off'\s+--[^\n]*\n\s+when v_jh_state <> 'current'/) // a lane that is off stays off
    expect(becomes).toMatch(/greatest\(security\.pipeline_num_v1\('lane_funnel\.job_runs_stale_minutes', 5\)::int \* 60,/)
    expect(becomes).toMatch(/2 \* greatest\(security\.pipeline_num_v1\('lane_funnel\.job_runs_refresh_seconds', 45\)::int, 60\) \+ 30\)/)
    expect(becomes).toContain("'stale_after_seconds', v_jr_stale_after")
    expect(mig).toContain('no allowed pair of settings leaves the history stale for good')
  })

  test('every line of the new code that holds a bare number is marked fixed with its reason (G2)', () => {
    const marked = (re) => mig.split('\n').filter((l) => re.test(l) && !/^\s*--/.test(l)).every((l) => /-- fixed: /.test(l))
    expect(marked(/left\(sqlerrm, 300\)/)).toBe(true)
    expect(marked(/left\(d\.return_message, 240\)/)).toBe(true)
    expect(marked(/\* 1000\)::int/)).toBe(true)
    expect(marked(/\* 60,/)).toBe(true)
    expect(marked(/\+ 30\)/)).toBe(true)
  })

  test('the partial index is kept only for a shown benefit: a scratch table of the live size, an index only scan, no heap fetch and a faster count', () => {
    expect(idx).toMatch(/^-- Guards: /m)
    expect(idx).toContain('generate_series(1, 208000)')
    expect(idx).toContain('Index Only Scan using evidence_artifacts_link_queue_idx')
    expect(idx).toContain('Heap Fetches: 0')
    expect(idx).toMatch(/t_after \* 1\.5 > t_before/)
    expect(run).toContain('index-benefit.sql')
    expect(run).toContain('-v ON_ERROR_STOP=1 -d $DB -f $F/after.sql') // a failed assertion stops the harness (it did not once)
    expect(mig).toContain('index-benefit.sql')
  })

  test('the numbers are settings (G2) and the other fixes are plain: materialised control log, grouped recovery pass, inbox without detail, partial index', () => {
    expect(mig).toContain("'lane_funnel.job_runs_refresh_seconds'")
    expect(mig).toContain("'lane_funnel.job_runs_stale_minutes'")
    expect(mig).toContain("security.pipeline_num_v1('lane_funnel.job_runs_stale_minutes', 5)")
    expect(mig).toContain('st as materialized (')
    expect(mig).toContain('layer4_inbox_items_v2(null, null, null, false)')
    expect(mig).toMatch(/create index if not exists evidence_artifacts_link_queue_idx\s+on pipeline\.evidence_artifacts/)
    expect(code(mig)).not.toMatch(/create\s+(unique\s+)?index[^;]*job_run_details/i) // no index on the pg_cron table
    expect(mig).not.toMatch(/(delete\s+from|truncate)\s+(cron|pipeline)/i)
  })

  test('the migration says what it replaces, drops nothing, and leaves the consumer API alone (G3)', () => {
    expect(mig).toMatch(/^-- Replaces: .+/m)
    expect(mig).toMatch(/^-- Retires: nothing/m)
    expect(mig).toContain('Nothing is dropped, deleted or renamed')
    expect(code(mig)).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|\bapi\.\w+\(/)
  })
})

test.describe('Operations load speed: held scripts, fixture and workflow', () => {
  test('forward recovery restores the five bodies byte for byte, guarded by the md5 of what is live, and is held (not a migration)', () => {
    expect(rec).toContain('HELD (not a migration)')
    const rows = [...rec.matchAll(md5Rec)]
    expect(rows.map((r) => r[1])).toEqual(FUNCTIONS)
    for (const r of [...mig.matchAll(md5)]) expect(rec).toContain(`'${r[1]}', '${r[3]}', '${r[2]}'`) // guard = the migration's after, expected = the production text
    expect(rec).toContain('has body md5')
    expect(rec).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  })

  test('the equivalence script is read only, compares old and new answers on live data and times both', () => {
    expect(eq).toMatch(/read only/i)
    for (const f of ['lane_funnel_v1', 'intake_progress_repeats_v1', 'process_results_recovery_v1', 'layer4_inbox_items_v2']) expect(eq).toContain(f)
    expect(eq).toMatch(/clock_timestamp\(\)/)
    // only this session's temporary schema and its own result table are written
    expect(eq).not.toMatch(/^\s*(insert into (?!eq_out)|update (?!eq_out)|delete|drop|truncate|alter|grant)/im)
    expect(eq.match(/create (or replace )?(temp |function pg_temp\.)?\w+( \w+)?/gi).every((c) => /temp table eq_out|function pg_temp\.old_/i.test(c))).toBe(true)
    expect(eq).not.toMatch(/refresh_v1\s*\(/)
  })

  test('the fixture proves refusal, equality, staleness, failure, recovery and idempotence on a scratch database only', () => {
    expect(run).toMatch(/^# Guards: /m)
    expect(run).toContain('case "$DB" in g_*)')
    for (const w of ['differs from the definition this change edits', 'applied again: no change', 'forward recovery', 'check_function_bodies=off']) expect(run).toContain(w)
    for (const w of ['stale', 'unknown', 'last good rows', 'pg_backend_pid', 'materialised', 'without its detail', 'two settings']) expect(after).toContain(w)
    expect(run).not.toMatch(/fxcwkweaxjtknorudmwp|coursefinder-demo|supabase\.co|mcp__/i)
  })

  test('the workflow runs the fixture on an isolated PostgreSQL image', () => {
    expect(wf).toMatch(/^# Guards: /m)
    expect(wf).toContain('postgres:17.6-alpine')
    expect(wf).toContain('tests/fixtures/operations-load-speed/run.sh')
    expect(wf).toContain('supabase/migrations/20261110020000_cf247_operations_load_speed.sql')
    expect(wf).toContain('supabase/held/operations_load_speed_forward_recovery.sql')
  })

  test('the lane funnel screen marks a stale or unknown job history and keeps the data attribute off a current one', () => {
    expect(ui).toContain('data-lf-job-history')
    expect(ui).toContain('history_known')
    expect(ui).toContain('job_history_state')
    expect(ui).toContain('data-lf-as-at')
  })
})

const withHistory = (jh, jobPatch = {}) => {
  const lanes = JSON.parse(JSON.stringify(LANES))
  lanes.job_history = jh
  for (const l of lanes.lanes) for (const j of l.jobs || []) Object.assign(j, { history_known: true }, jobPatch)
  return lanes
}

test.describe('Operations load speed: lane funnels screen', () => {
  const OPERATIONS = '/#layer-2-discovery?tab=operations'
  const at = (m) => new Date(Date.now() - m * 60000).toISOString()

  test('a current job history shows no note and the job figures as before', async ({ page }) => {
    await mockAdmin(page); await mockLaneFunnels(page, { lanes: withHistory({ known: true, stale: false, measured_at: at(0.5), age_seconds: 30 }) })
    await page.goto(OPERATIONS)
    const root = page.locator('[data-lane-funnels]')
    await expect(root.locator('[data-lf-lane]')).toHaveCount(3)
    await expect(root.locator('[data-lf-job-history]')).toHaveCount(0)
    await root.locator('[data-lf-lane="fee"] summary').click()
    await expect(root.locator('[data-lf-job="fee-reader"]')).toContainText('12 / 0')
  })

  test('a stale job history is said to be stale with when it was counted, and a failed recount shows its error', async ({ page }) => {
    await mockAdmin(page); await mockLaneFunnels(page, { lanes: withHistory({ known: true, stale: true, measured_at: at(12), age_seconds: 720, error: 'canceling statement due to statement timeout' }) })
    await page.goto(OPERATIONS)
    const note = page.locator('[data-lane-funnels] [data-lf-job-history]')
    await expect(note).toHaveAttribute('data-lf-job-history', 'stale')
    await expect(note).toContainText('is stale')
    await expect(note).toContainText('12 min ago')
    await expect(note).toContainText('failed: canceling statement due to statement timeout')
  })

  test('a running job and the lane job result say as at when the summary was counted', async ({ page }) => {
    const lanes = withHistory({ known: true, stale: false, measured_at: at(0.5), age_seconds: 30 })
    lanes.lanes[0].jobs[0].running = true
    await mockAdmin(page); await mockLaneFunnels(page, { lanes })
    await page.goto(OPERATIONS)
    const root = page.locator('[data-lane-funnels]')
    await root.locator('[data-lf-lane="fee"] summary').click()
    const row = root.locator('[data-lf-job="fee-reader"]')
    await expect(row.locator('td[data-label="State"]')).toContainText('Running')
    await expect(row.locator('[data-lf-as-at]')).toContainText('as at')
    await expect(root.locator('[data-lf-lane="fee"] [data-lf-three]')).toContainText('as at')
  })

  test('a lane whose job history is stale says unknown for its job result and its verdict, not a confident value', async ({ page }) => {
    const lanes = withHistory({ known: true, stale: true, measured_at: at(12), age_seconds: 720 })
    lanes.lanes[0].job_history_state = 'stale'; lanes.lanes[0].verdict = 'unknown'
    await mockAdmin(page); await mockLaneFunnels(page, { lanes })
    await page.goto(OPERATIONS)
    const fee = page.locator('[data-lane-funnels] [data-lf-lane="fee"]')
    await expect(fee).toHaveAttribute('data-lf-verdict', 'unknown')
    await fee.locator('summary').click()
    await expect(fee.locator('[data-lf-job-result]')).toHaveText('unknown')
    await expect(fee.locator('[data-lf-three]')).toContainText('stale')
    await expect(page.locator('[data-lf-lane="aer"] [data-lf-three]')).toHaveCount(0) // a closed lane keeps its body hidden
  })

  test('an unknown job history says unknown for the running state, last attempt and runs, never 0', async ({ page }) => {
    await mockAdmin(page); await mockLaneFunnels(page, { lanes: withHistory({ known: false, stale: true, measured_at: null }, { history_known: false, runs: 0, succeeded: 0, failed: 0, last_start: null, last_status: null }) })
    await page.goto(OPERATIONS)
    const root = page.locator('[data-lane-funnels]')
    await expect(root.locator('[data-lf-job-history]')).toHaveAttribute('data-lf-job-history', 'unknown')
    await root.locator('[data-lf-lane="fee"] summary').click()
    const row = root.locator('[data-lf-job="fee-reader"]')
    await expect(row.locator('td[data-label="Runs"]')).toHaveText('unknown')
    await expect(row.locator('td[data-label="Last attempt"]')).toHaveText('unknown')
    await expect(row.locator('td[data-label="State"]')).toContainText('Unknown')
  })
})
