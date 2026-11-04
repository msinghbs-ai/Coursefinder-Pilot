// Guards: Decision 269 amendments (Platform Admin 4 Nov 2026 about 05:40; approval 06:53 §2) and Option A (direction 4 Nov 2026 10:00 §8): Refresh schedules "Rewire, then retire" (Layer 1 › Sources' Schedule and Run now act on the Layer 1 refresh policies with the legacy controls' ranks, reasons and audit; then the Automations section retires), Link refresh stays on Coverage › Courses, 47 tabs on 20 pages
// SS-020 follow-up items 1, 2 and 4. The behaviour runs on tests/fixtures/ss020-followup/run.sh (scratch PostgreSQL 16; the live
// admin_layer1_schedule, refresh_scheduler_tick_impl and the two legacy Refresh schedules implementations rebuilt and checked against their
// live md5s; the migration applied twice; every role, reason and audit case; a register's schedule changed on Layer 1 › Sources moves its next
// run, which the scheduler then queues). This spec holds the contract.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { PAGES, LEGACY, resolveTarget } from '../../src/nav-map.js'
import { mockAdmin } from './support/admin-mock.mjs'

const read = (p) => fs.readFileSync(p, 'utf8')
const MIG = 'supabase/migrations/20261104510000_cf247_ss020_followup_layer1_schedule.sql'
const m = read(MIG)
const FX = 'tests/fixtures/ss020-followup'
const run = read(`${FX}/run.sh`)
const LIVE = { 'public.admin_layer1_schedule': '53b48153be94af028d322e2d5851962a', 'security.refresh_scheduler_tick_impl': '5f7b3ece8e91919d622b16af652b9250',
  'security.scheduler_policy_edit_v1_browser_bridge': '863025c7a7c6c39dd445ff5419ff58ce', 'security.scheduler_policy_run_now_v1_browser_bridge': 'be60535243220790e08d56e4ee47d4e0' }

test('item 1: md5-guarded both ways against the live definitions the fixture rebuilds', () => {
  expect(m).toContain("select pg_temp.replace_once('public.admin_layer1_schedule(uuid,text,text)', '53b48153be94af028d322e2d5851962a', 'cc0c680d0a1768410d0dd9c516ff4af7'")
  expect(m).toContain("select pg_temp.create_once('public.admin_layer1_policy_run_v1(uuid,text)', '574e4ece482e5907d539a171e389f01a'")
  for (const [f, h] of Object.entries(LIVE)) { expect(run, f).toContain(h); if (f !== 'public.admin_layer1_schedule') expect(m, f).toContain(`'${h}'`) }
  for (const f of ['admin_layer1_schedule', 'refresh_scheduler_tick_impl', 'scheduler_policy_edit_v1_browser_bridge', 'scheduler_policy_run_now_v1_browser_bridge'])
    expect(read(`${FX}/stubs.sql`)).toContain(`\\i live/${f}.sql`)
})

test('item 1 (Option A): ranks 4 and 5 keep Schedule and Run now on a register with a policy, through the legacy controls; nothing widened', () => {
  const def = m.slice(m.indexOf('create or replace function public.admin_layer1_schedule'), m.indexOf('$def$);'))
  expect(def).toContain("if auth.uid() is null or v_rank < 4 then raise exception 'Pipeline Operator required'")
  expect(def).toContain('perform security.scheduler_policy_edit_v1_browser_bridge(v_policy.id, v_policy.updated_at, v_days, v_next, v_policy.enabled, p_reason);')
  expect(def).toContain("if v_rank < 6 and p_schedule = 'manual' then raise exception")
  expect(def).toContain("if length(btrim(coalesce(p_reason, ''))) < 5 then")
  expect(def).toContain('v_next := greatest(now(), coalesce(v_policy.next_due_at - coalesce(v_policy.cadence_interval, make_interval()), now()) + make_interval(days => v_days));')
  const withPolicy = def.slice(def.indexOf('if found then'), def.indexOf('  else\n'))
  expect(withPolicy).not.toContain('verification_cadence_days =')
  expect(withPolicy).toContain('if v_rank >= 6 then')
  const noPolicy = def.slice(def.indexOf('  else\n'))
  expect(noPolicy).toContain("if v_rank < 6 then raise exception 'Platform Admin required'")
  const runDef = m.slice(m.indexOf('create or replace function public.admin_layer1_policy_run_v1'))
  expect(runDef).toContain('return security.scheduler_policy_run_now_v1_browser_bridge(v_policy, p_reason);')
  expect(m).toContain('revoke all on function public.admin_layer1_policy_run_v1(uuid, text) from public, anon;')
  for (const c of ['"Curator (rank 3) schedule"', '"a 4-character reason"', '"Pipeline Operator choosing Manual"', '"PIM Admin on a source without a policy"',
    '"Pipeline Operator run of a source without a policy"', '"operator: policy 1 day, next run within a day (legacy edit)"', '"legacy audit row (refresh_policy_action_events)"',
    '"operator run: one queued manual request, not duplicated"', '"after: the tick queues the CRICOS run within 2 days"', '"NZQA next run moved from 6 days to 29 days"',
    '"no policy: verification cadence written as before"', '"no policy created (nothing switched on)"', 'second run: unchanged']) expect(run).toContain(c)
  const l1 = read('src/layer1-operations-entry.jsx')
  expect(l1).toContain("{rank>=4&&rank<6&&hasPolicy&&!active&&<button className=\"primary\" data-l1-policy-run onClick={policyRun}")
  expect(l1).toContain("supabase.rpc('admin_layer1_policy_run_v1',{p_source_id:source.source_id,p_reason:why})")
  expect(l1).toContain("{!canEdit&&rank>=4&&hasPolicy&&<div className=\"xl-form\" data-l1-policy-schedule>")
  expect(l1).toContain("if(!v||v==='custom'||v==='manual')return")
})

test('item 1: the section and the functions only it called are retiring with replaced_by and retire_after; the two implementations stay; nothing dropped', () => {
  expect(m).toContain("('screen', 'Scheduled jobs › Automations › Refresh schedules and one-off runs'")
  for (const f of ['public.scheduler_policies_list_v1', 'public.scheduler_policy_edit_v1', 'public.scheduler_policy_run_now_v1', 'public.refresh_intelligence_overview',
    'security.scheduler_policies_list_v1_browser_bridge', 'security.refresh_intelligence_overview_impl']) expect(m).toContain(`('function', '${f}'`)
  for (const f of ['security.scheduler_policy_edit_v1_browser_bridge', 'security.scheduler_policy_run_now_v1_browser_bridge']) expect(m).not.toContain(`('function', '${f}'`)
  expect(m.match(/', 'retiring',\s/g)).toHaveLength(7)
  expect(m).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

test('item 1: Automations no longer shows Refresh schedules; its runtime health stays; old addresses open Layer 1 › Sources', () => {
  const shell = read('src/mature-main.jsx'), entry = read('src/m2-3-intelligence-entry.jsx')
  expect(fs.existsSync('src/ScheduledJobsWorkspace.jsx')).toBe(false)
  expect(shell).not.toContain('RefreshWorkspace')
  expect(entry).not.toContain('export const Refresh')
  expect(entry).not.toContain('ScheduledJobsWorkspace')
  for (const slug of ['scheduled-tasks', 'refresh-scheduling']) { expect(LEGACY[slug]).toEqual({ page: 'layer1' }); expect(resolveTarget(slug).page).toBe('layer1') }
  expect(resolveTarget('scheduled-jobs', new URLSearchParams({ tab: 'schedules' })).page).toBe('layer1')
  expect(PAGES.jobs.min ?? Math.min(...PAGES.jobs.tabs.map((t) => t.min))).toBe(PAGES.layer1.min) // same rank opens the new home
  const l1 = read('src/layer1-operations-entry.jsx')
  expect(l1).toContain("const scheduleDays=s=>{const m=String(s?.cadence_interval||'').match(")
  expect(l1).toContain('SCHEDULES.find(([,d])=>d===scheduleDays(s))')
})

test('items 2 and 4: Link refresh stays on Coverage › Courses; no "conditional Layer 3" row wording; 47 tabs on 20 pages', () => {
  expect(read('src/mature-main.jsx')).toContain("<CoverageView view=\"courses\"/><LinkRefresh/>")
  expect(Object.keys(PAGES)).toHaveLength(20)
  expect(Object.values(PAGES).reduce((n, p) => n + (p.tabs?.length || 1), 0)).toBe(47)
  const texts = fs.readdirSync('src', { recursive: true }).filter((f) => /\.(jsx?|css)$/.test(f)).map((f) => read(`src/${f}`))
  for (const t of texts) { expect(t).not.toContain('conditional Layer 3'); expect(t).not.toMatch(/\b22 pages\b/) }
  expect(read('src/guide/platformGuide.js')).toContain('Refresh schedules and one-off runs is retired from Automations')
})

test.describe('mocked browser', () => {
  test('an old refresh schedules address opens Layer 1 › Sources, and Automations has no Refresh schedules section', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#refresh-scheduling')
    await expect(page).toHaveURL(/#layer-1-register/)
    await page.goto('/#scheduled-jobs?tab=automations')
    await expect(page.getByRole('heading', { name: 'Refresh schedules and one-off runs' })).toHaveCount(0)
  })
})
