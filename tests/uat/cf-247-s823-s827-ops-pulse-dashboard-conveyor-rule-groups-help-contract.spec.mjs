// Guards: CF-247 S1-UX s823 to s827 (Platform Admin 20 Nov 2026 10:31, 10:46 and 11:24, chat S1-UX; layered on S1-RM-Design PR 1411): s823 the stored ops pulse
// and state-transition logging (migration 20261120140000), s824 the Dashboard KPI cards with icons and country bars and no pipeline read for rank 1-2,
// s825 the 4-stage pipeline board under the s817 executive view, s826 Layer 4 Waiting, grouped by rule, and s827 the ? help drawer.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { completenessBars, flowReach, groupsWorthShowing, kpiCards, pulseOf, ruleGroups, ruleOf, spendOf, stageCards, HELP_GUIDES, STAGES } from '../../src/lib/ops-pulse.js'

const MIG = fs.readFileSync('supabase/migrations/20261120140000_cf247_s823_ops_pulse_snapshot_state_transition_logging.sql', 'utf8')
const read = (f) => fs.readFileSync(f, 'utf8')

test('s823: the stored pulse answers the health read, with the live counts kept as the fallback; no public object', () => {
  expect(MIG).toContain('create table if not exists pipeline.ops_pulse_snapshot (')
  expect(MIG).toContain("select pg_temp.cf_edit_def('security.admin_platform_health_cf221()'::regprocedure, null,")
  expect(MIG).toContain(" if security.ops_pulse_fresh_v1() then return security.ops_pulse_cf221_v1(v_rank); end if;  -- CF-247 s823")
  expect(MIG).toContain("security.pipeline_num_v1('ops.pulse_max_age_minutes', 15)")
  expect(MIG).toContain("select cron.schedule('ops-pulse-refresh', '*/5 * * * *', 'select security.ops_pulse_refresh_v1()')")
  expect(MIG).toContain("insert into pipeline.automation_catalogue (jobname, area, sort, label, description, control_rank, batch_editable) values\n ('ops-pulse-refresh'")
  expect(MIG).toContain('from security.layer4_inbox_items_v2(null, null, null, false) r group by r.kind')
  // a part that fails is unknown, never 0
  expect(MIG).toContain("v_l4 := null; v_l4_total := null;")
  expect(MIG).toContain("'pulse', case when p_rank >= 3 then")
  expect(MIG).toContain("if h ? 'pulse' or h ? 'api_activity' then raise exception 'post-check: a rank 1-2 user was given the pulse or API activity'")
  expect(MIG).toContain("if v_ms > 50 then raise exception 'post-check: the stored read took % ms'")
  expect(MIG).not.toMatch(/create (or replace )?(function|view|table)( if not exists)? (public|api)\./)
  expect((MIG.match(/v jsonb := security\.consumer_api_check_v1\(\);/g) || []).length).toBe(2) // read before and after
})

test('s823: a run of idle calls updates one ledger row; work, failures and errors are recorded as before', () => {
  expect(MIG).toContain("select pg_temp.cf_edit_def('public.svc_worker_report_v1(text,integer,integer,jsonb,text)'::regprocedure, 'b110a648a8149eede42cbc69cce43a77',")
  expect(MIG).toContain('  v_id := security.worker_idle_collapse_v1(p_mode, p_status, p_ms, p_body, p_worker);  -- CF-247 s823: a run of idle calls updates one row')
  expect(MIG).toContain('  perform security.worker_idle_note_v1(p_mode, p_worker, v_id);  -- CF-247 s823')
  expect(MIG).toContain("security.pipeline_num_v1('telemetry.idle_collapse_minutes', 15)")
  expect(MIG).toContain("and not coalesce(p_body ? 'error', false)")
  expect(MIG).toContain("raise exception 'cf-s823-undo';")
  expect(MIG).toContain("if v_a <> v_b or v_rows <> 1 or v_polls <> 3 then")
})

test('s826: cards are grouped by the rule that holds them; one group, or groups of one, show no panel', () => {
  const items = [
    { kind: 'provider_description', ref: 'a', subject: 'A', detail: { machine: { reason_code: 'policy_banned_words' } } },
    { kind: 'provider_description', ref: 'b', subject: 'B', detail: { machine: { reason_code: 'check_unsupported_marketing' } } },
    { kind: 'provider_description', ref: 'c', subject: 'C', detail: { machine: { reason_code: 'check_length' } } },
    { kind: 'course_link', ref: 'd', subject: 'D', why: 'The page we hold moved. A new page was found.' },
    { kind: 'course_link', ref: 'e', subject: 'E', why: 'The page we hold moved; check it.' }]
  expect(ruleOf(items[0]).label).toBe('Marketing or claim wording')
  expect(ruleOf(items[3]).label).toBe('The page we hold moved')
  const g = ruleGroups(items)
  expect(g.map((x) => [x.label, x.n])).toEqual([['Marketing or claim wording', 2], ['The page we hold moved', 2], ['Longer than the limit', 1]])
  expect(groupsWorthShowing(g)).toBe(true)
  expect(groupsWorthShowing(ruleGroups(items.slice(2, 4)))).toBe(false)
  const inbox = read('src/Layer4Inbox.jsx'), side = read('src/Layer4RuleGroups.jsx')
  expect(inbox).toContain('<Layer4RuleGroups items={items.items} renderSettle={pv=>settleFor(pv,kinds,')  // s892: the Inbox gives the settle box (Layer4SettleBox.jsx); the panel still decides nothing
  expect(inbox).toContain('render={it=><Item key={`${it.kind}:${it.ref}`}')
  expect(side).not.toMatch(/supabase|rpc\(|adminRead/) // reads nothing, decides nothing
  expect(side).toContain('href="#layer-4-review?view=grid"')
})

const PULSE = {
  status: 'warning', critical: 0, warning: 2, blockers: 0, layer4_waiting: 46, layer4_by_kind: { provider_description: 30, course_link: 16 },
  budget: { spend_usd: 3.2, cap_usd: 14 }, completeness: { AU: { completeness: 71.4, courses: 21000 }, NZ: { completeness: 58, courses: 6000 }, CA: { completeness: 44.2, courses: 9000 } },
  checks: { total: 9, attention: 2, healthy: 6, skipped: 1, unmapped: 1 }, refreshed_at: '2026-11-20T00:05:00Z', run_ms: 640,
  stages: [
    { stage: 1, name: 'Official Registers', status: 'ok', checks: 2, attention: [], queued: 3 },
    { stage: 2, name: 'Page Capture', status: 'warning', checks: 3, attention: [{ key: 'edge_calls', label: 'Edge function calls', status: 'warning' }], queued: 1210 },
    { stage: 3, name: 'AI Extraction & Auto-Clean', status: 'warning', checks: 2, attention: [{ key: 'budgets', label: 'Budgets', status: 'warning' }], queued: 4380 },
    { stage: 4, name: 'Live Catalogue', status: 'ok', checks: 1, attention: [], queued: 46 }]
}

test('s824/s825: cards, country bars, stage meters and the flow track come from the stored pulse only', () => {
  expect(pulseOf({ pulse: PULSE })).toBe(PULSE); expect(pulseOf({ overall: 'ok' })).toBe(null)
  const cards = stageCards(PULSE)
  expect(cards.map((c) => c.tone)).toEqual(['ok', 'warn', 'warn', 'ok'])
  expect(cards[1].meterText).toBe('2 of 3 checks passing'); expect(cards[1].meterPct).toBe(67)
  expect(flowReach(cards)).toBe(2)
  expect(completenessBars(PULSE).map((b) => b.text)).toEqual(['71%', '58%', '44%'])
  expect(completenessBars({}).map((b) => b.text)).toEqual(['—', '—', '—']) // unknown is never 0
  expect(spendOf(PULSE)).toMatchObject({ text: 'US$3.20', capText: 'of the US$14.00 daily cap', pct: 23 })
  expect(kpiCards(PULSE).map((k) => k.label)).toEqual(['System status', 'Catalogue completeness', 'Decisions waiting on you', 'Active blockers', 'AI & crawl spend today'])
  expect(STAGES.map((s) => s.name)).toEqual(['Official Registers', 'Page Capture', 'AI Extraction & Auto-Clean', 'Live Catalogue'])
  for (const k of ['dashboard', 'health', 'layer4', 'catalogue']) expect(HELP_GUIDES[k].steps).toHaveLength(3)
})

async function withPulse(page) {
  await page.route('**/rest/v1/rpc/admin_read', async (route) => {
    const body = route.request().postDataJSON() || {}
    if ((body.p_operation || body.operation) !== 'platform_health') return route.fallback()
    const cur = '2026-11-20T00:05:00Z'
    return route.fulfill({ contentType: 'application/json', body: JSON.stringify({ generated_at: cur, overall: 'warning', counts: { critical: 0, warning: 2, info: 0 }, issues: [], history: [], pulse: PULSE, pulse_source: 'snapshot', checks: [
      { key: 'cron', area: 'scheduled jobs', label: 'Scheduled jobs', status: 'ok', detail: {}, checked_at: cur },
      { key: 'edge_calls', area: 'edge functions', label: 'Edge function calls', status: 'warning', detail: {}, checked_at: cur },
      { key: 'budgets', area: 'budgets', label: 'Budgets', status: 'warning', detail: {}, checked_at: cur } ] }) })
  })
}

test.describe('mocked browser', () => {
  test('Platform Health: the 4-stage board sits under the s817 executive view, the slowed stage selected; Technical details stay closed', async ({ page }) => {
    await mockAdmin(page)
    await withPulse(page)
    await page.goto('/#platform-health')
    await expect(page.locator('[data-ph-exec]')).toBeVisible()
    const board = page.locator('[data-health-pulse] [data-pipeline-board]')
    await expect(board.locator('[data-stage]')).toHaveCount(4)
    await expect(board.locator('[data-stage="2"]')).toHaveAttribute('data-stage-tone', 'warn')
    await expect(page.locator('[data-stage-panel="2"]')).toContainText('Page Capture')
    await board.locator('[data-stage="4"]').click()
    await expect(page.locator('[data-stage-panel="4"]')).toContainText('Open Layer 4 by rule')
    await expect(page.locator('[data-stage-meter]').nth(1)).toHaveText('2 of 3 checks passing')
    await expect(page.locator('[data-ph-technical]')).not.toHaveAttribute('open', '')
    expect(await page.evaluate(() => [...document.querySelectorAll('[data-ph-exec], [data-health-pulse]')].map((e) => e.hasAttribute('data-ph-exec') ? 'exec' : 'board'))).toEqual(['exec', 'board'])
  })

  test('Dashboard: a Viewer makes no pipeline or telemetry read; a Platform Admin gets the cards, country bars and Active failures', async ({ page }) => {
    await mockAdmin(page, { rank: 1 })
    await page.goto('/#dashboard')
    await expect(page.locator('[data-db-search]')).toBeVisible()
    await page.waitForTimeout(400)
    const ops = (page.readCalls || []).map((b) => b.p_operation)
    expect(ops).not.toContain('dashboard'); expect(ops).not.toContain('platform_health')
    await expect(page.locator('[data-db-pulse]')).toHaveCount(0)
  })

  test('Dashboard (Platform Admin): five cards with icons, country bars and Active failures from the stored pulse', async ({ page }) => {
    await mockAdmin(page)
    await withPulse(page)
    await page.goto('/#dashboard')
    await expect(page.locator('[data-db-pulse] [data-kpi]')).toHaveCount(5)
    await expect(page.locator('[data-db-pulse] .op-badge svg')).toHaveCount(5)
    await expect(page.locator('[data-db-pulse] [data-country-bar]')).toHaveCount(3)
    await expect(page.locator('[data-db-failures="0"]')).toContainText('No failure or warning needs a person') // s836: genuine failures only (this answer has no open issue)
  })

  test('s826 Layer 4: Waiting, grouped by rule groups the page, previews a batch and narrows the list; the cards keep their own bars', async ({ page }) => {
    await mockAdmin(page)
    const kinds = { course_link: { label: 'Course link', order: 1, choices: [{ key: 'use', label: 'Use the new page', returns: 'x' }] } }
    const item = (ref, why, subject) => ({ kind: 'course_link', ref, o: 1, provider_id: 'p1', provider: 'University of Waikato', subject, why, created_at: '2026-10-20T00:00:00Z', detail: {} })
    await page.route('**/rest/v1/rpc/admin_layer4_inbox', async (route) => {
      const b = route.request().postDataJSON() || {}
      if (b.p_action === 'summary') return route.fulfill({ json: { kinds, target_days: 7, rank: 6, total: 5, universities: 1, late: 0, by_kind: { course_link: { n: 5 } } } })
      if (b.p_action === 'universities') return route.fulfill({ json: { total: 0, items: [] } })
      if (b.p_action === 'items') return route.fulfill({ json: { total: 5, before: 0, items: [
        item('r1', 'Two pages could be this course. Check the code.', 'Course A'), item('r2', 'Two pages could be this course', 'Course B'),
        item('r3', 'Two pages could be this course; pick one.', 'Course C'), item('r4', 'The page we hold moved.', 'Course D'), item('r5', 'The page we hold moved', 'Course E')] } })
      return route.fulfill({ json: {} })
    })
    await page.goto('/#layer-4-review?view=kind&kind=course_link')
    const side = page.locator('[data-l4-rule-groups="2"]')
    await expect(side.locator('[data-l4-rule]')).toHaveCount(3) // All, and the two rules
    await expect(page.locator('[data-l4-rule-shown="5"] [data-l4-item]')).toHaveCount(5)
    await side.locator('[data-l4-rule="course_link:two pages could be this course"]').click()
    await expect(page.locator('[data-l4-rule-preview]')).toContainText('3 cards on this page')
    await expect(page.locator('[data-l4-rule-shown="3"] [data-l4-item]')).toHaveCount(3)
    await expect(page.locator('[data-l4-ref="r1"] [data-l4-choice="use"]')).toBeVisible()
    await side.locator('[data-l4-rule="all"]').click()
    await expect(page.locator('[data-l4-rule-shown="5"] [data-l4-item]')).toHaveCount(5)
  })

  test('? help: the header opens three steps for the screen and Escape closes it', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#layer-4-review?view=university')
    await page.locator('[data-help-open="layer4"]').first().click()
    const d = page.locator('[data-help-drawer="layer4"]')
    await expect(d.locator('[data-help-steps="3"] li')).toHaveCount(3)
    await expect(d.locator('[data-help-guide]')).toHaveAttribute('href', '#platform-guide')
    await page.keyboard.press('Escape')
    await expect(d).toHaveCount(0)
  })
})
