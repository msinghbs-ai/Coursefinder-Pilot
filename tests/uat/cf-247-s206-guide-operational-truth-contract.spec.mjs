// Guards: SS-016 UR-01, UR-02, UR-03, UR-17 (Platform Admin 1 Nov 2026 20:08); SS-016 UR-08, UR-10, UR-11, UR-12, UR-16 (Platform Admin 1 Nov 2026 22:01); SS-016 UR-03 mirror ancestor guard and role truth P1 (Curator) / P2 (Counsellor) (acceptance walkthrough findings, 1 Nov 2026)
// CF-247 S206. Source: admin docs/platform/nz-enrichment-brief/2026-11-01-role-guides-usability-operability-review.md (UR-01, UR-02, UR-03,
// UR-17). The guides state operational truth: alerts by push and e-mail as OPERATIONAL-LIMITS v1.3 states them (D12); the Pipeline Operator
// diagnoses, records and escalates while the PIM Admin (or higher) paces and pauses (live: security.admin_automation_control_v1 needs rank 5,
// then the job's control rank); AER items are decided by the Platform Admin only with the current three choices; the SOP mirror is checkable.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { spawnSync } from 'node:child_process'
import { mockAdmin } from './support/admin-mock.mjs'
import * as G from '../../src/guide/platformGuide.js'
import { SOPS, AUTOMATION, RULES as SOP_RULES } from '../../src/guide/sops.js'

// Active text: everything the guides tell people now. Version histories (`changes`) are history and keep their old words.
const guideText = JSON.stringify([G.ROLES, G.RULES, G.DAILY_ROUTINE, G.SCREENS, G.SIGNALS, G.ADMIN_DUTIES, G.ALERTS, G.SPECIALIST_TASKS])
const sopText = JSON.stringify([AUTOMATION, SOP_RULES, SOPS.map(({ changes, ...s }) => s)])
const admin = SOPS.find((s) => s.id === 'admin-sop')
const operator = SOPS.find((s) => s.id === 'operator-sop')
// The part of a sentence addressed to the Pipeline Operator: from "Pipeline Operator:" or "Operator:" to the next role label.
// Text with no "Operator:" label is read whole.
const operatorPart = (x) => /Operator:/.test(x) ? x.match(/(?:Pipeline )?Operator:([^]*?)(?=PIM Admin|Platform Admin|$)/)[1] : String(x)
const CONTROL = /lower "per run"|batch size|^\s*pause|\bpause (it|the job) with\b/i

test('UR-01: no planned-mail or on-screen-only claims remain in active guide or SOP text', () => {
  for (const text of [guideText, sopText]) {
    expect(text).not.toMatch(/mailgun/i)
    expect(text).not.toMatch(/on screen only/i)
  }
})

test('UR-01: alert delivery, delay, confirmation, cooldown, reminder, recovery and receipt as OPERATIONAL-LIMITS v1.3 states them', () => {
  const a = G.ALERTS
  expect(a.status).toContain('push and e-mail')
  expect(a.status).toContain('the hourly "Work queue alerts" scheduled task (at :59)')
  expect(a.status).toContain('up to about 75 minutes from an issue to the message: 15 minutes to qualify, up to 10 for the job and up to 60 for the task')
  const row = (name) => a.rows.find((r) => r.alert === name)
  expect(row('Confirmation')).toMatchObject({ setting: 'alerts.confirm_minutes' })
  expect(row('Confirmation').when).toContain('15 minutes')
  expect(row('Cooldown')).toMatchObject({ when: 'One alert per check within 60 minutes', setting: 'alerts.cooldown_minutes' })
  expect(row('Reminder').when).toContain('Every 12 hours while the issue is open and not acknowledged')
  expect(row('Reminder').when).toContain('the acknowledgement is cleared')
  expect(row('Recovery').setting).toBe('alerts.recovery_notice (on)')
  expect(row('Delivery retries').when).toBe('5 attempts, from 10 minutes, doubling')
  expect(a.receipt).toContain('"Delivered" means the alert was sent, not that anyone read it')
  expect(a.receipt).toContain('The person on call confirms they received it')
  expect(a.receipt).toContain('SS-014')
  // the Platform Admin SOP repeats it where an alert is acted on
  const sop = admin.interventions.find((x) => x.trigger.startsWith('A StudySearch alert by push or e-mail'))
  expect(sop?.action).toContain('up to about 75 minutes after the issue (15 minutes to qualify, up to 10 for the platform-alerts job, up to 60 for the task)')
  expect(sop?.action).toContain('"Delivered" means sent, not read')
})

test('UR-02: the Operator SOP and guide do not tell the Pipeline Operator to pause or change pace; the PIM Admin does', () => {
  for (const x of [...operator.schedule.flatMap((b) => b.steps), ...operator.weekly].filter((x) => x.role === 'Pipeline Operator')) {
    expect(x.do, x.do).not.toMatch(CONTROL)
    expect(x.do).not.toMatch(/start (one|it|jobs?) again/i)
  }
  for (const x of operator.interventions) expect(operatorPart(x.action), x.trigger).not.toMatch(CONTROL)
  expect(operator.owns.find((o) => o.startsWith('Pipeline Operator:'))).not.toMatch(/starting jobs again|pac|paus/i)
  expect(operator.owns.find((o) => o.startsWith('PIM Admin:'))).toContain('pausing')
  expect(operator.escalate.join(' ')).toContain('Pipeline Operator diagnoses, records and escalates; the PIM Admin (or a higher role) changes pace or pauses; automations marked Platform Admin go to the Platform Admin')
  for (const s of G.SIGNALS.filter((s) => /Operator/.test(s.who))) {
    expect(operatorPart(s.act), s.see).not.toMatch(CONTROL)
  }
  const role = (n) => G.ROLES.find((r) => r.role === n)
  expect(role('Pipeline Operator').can).toContain('Diagnoses, records and escalates automations')
  expect(role('Pipeline Operator').daily.join(' ')).not.toMatch(/start one again/i)
  expect(role('PIM Admin').can).toContain('Pause, resume, run now and pace')
  expect(role('Platform Admin').can).toContain('controls on automations marked Platform Admin')
})

test('UR-17: AER decisions are Platform Admin only, with the current three choices and D4; no "More evidence" choice in active text', () => {
  for (const text of [guideText, sopText]) expect(text).not.toMatch(/more evidence/i)
  expect(G.ROLES.find((r) => r.role === 'Curator').can).toContain('entry requirement (AER) items only the Platform Admin') // SS-016 P1 wording
  const aer = G.SPECIALIST_TASKS.find((t) => t.task === 'Decide an entry requirement (AER) item in Layer 4')
  expect(aer.role).toMatch(/^Platform Admin only/)
  for (const c of ['Approve all rows', 'Approve except…', 'Reject the read', 'D4']) expect(aer.choices).toContain(c)
  const course = admin.interventions.find((x) => x.trigger.startsWith('Layer 4: Course entry first read'))
  expect(course.action).toContain('Platform Admin only, one item at a time')
  expect(course.action).toContain('not for a course that already has active entry rows')
  expect(operator.interventions.find((x) => x.trigger === 'Layer 4 Review item').action).toContain('Entry requirement (AER) items are decided by the Platform Admin only')
})

test('UR-17: every specialist task names its lowest role, source, saved evidence, escalation, guide and an existing screen', async () => {
  const { PAGES } = await import('../../src/nav-map.js')
  expect(G.SPECIALIST_TASKS.length).toBeGreaterThanOrEqual(6)
  for (const t of G.SPECIALIST_TASKS) {
    for (const k of ['task', 'role', 'source', 'evidence', 'escalate', 'doc']) expect(t[k], `${t.task}: ${k}`).toBeTruthy()
    expect(PAGES[t.page], t.task).toBeTruthy()
    if (t.tab) expect(PAGES[t.page].tabs.some((x) => x.key === t.tab)).toBe(true)
  }
  expect(G.SPECIALIST_TASKS.map((t) => t.doc).join(' ')).toContain('AER-ROLE-GUIDES.md')
  expect(G.SPECIALIST_TASKS.map((t) => t.doc).join(' ')).toContain('production-environment-runbook')
  const counsellor = G.ROLES.find((r) => r.role === 'Counsellor').daily.join(' ')
  for (const w of ['estimate', 'does not state a grading scale', 'contact the provider', 'Counsellor report', 'Fixed or Not changed']) expect(counsellor).toContain(w)
})

test('UR-03: export-sops --check-mirror passes an identical mirror and reports a stale or unmarked one (exit 1)', () => {
  const run = (dir) => spawnSync(process.execPath, ['scripts/export-sops.mjs', '--check-mirror', dir], { encoding: 'utf8' })
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'sop-mirror-'))
  try {
    for (const s of SOPS) fs.copyFileSync(`docs/sops/${s.id}.md`, path.join(tmp, `${s.id}.md`))
    const same = run(tmp)
    expect(same.status, same.stdout + same.stderr).toBe(0)
    expect(same.stdout).toContain(`All ${SOPS.length} SOP documents match`)

    const file = path.join(tmp, 'operator-sop.md')
    const lines = fs.readFileSync(file, 'utf8').split('\n')
    const i = lines.findIndex((l) => l.startsWith('## 1. Purpose')) + 2
    lines[i] = `${lines[i]} (stale)`
    fs.writeFileSync(file, lines.join('\n'))
    const stale = run(tmp)
    expect(stale.status).toBe(1)
    expect(stale.stdout).toMatch(/differs\s+.*operator-sop\.md/)
    expect(stale.stdout).toContain('content-sha256 does not match the content')
    expect(stale.stdout).toMatch(/^same\s+.*admin-sop\.md/m)

    // a copy made before provenance lines (as the admin mirror was) is drift too
    const body = fs.readFileSync(path.join(tmp, 'admin-sop.md'), 'utf8').replace(/^<!-- sop-export: .* -->\n/, '')
    fs.writeFileSync(path.join(tmp, 'admin-sop.md'), body)
    const unmarked = run(tmp)
    expect(unmarked.status).toBe(1)
    expect(unmarked.stdout).toMatch(/no provenance\s+.*admin-sop\.md/)
  } finally { fs.rmSync(tmp, { recursive: true, force: true }) }
})

test.describe('mocked browser', () => {
  test('the Platform guide shows alerts by push and e-mail, the receipt check and the specialist tasks', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#platform-guide')
    const g = page.locator('[data-platform-guide]')
    await expect(g.locator('[data-guide-alerts]')).toContainText('Alerts (push and e-mail)')
    await expect(g.locator('[data-guide-alert-receipt]')).toContainText('"Delivered" means the alert was sent, not that anyone read it')
    await expect(g.locator('[data-guide-tasks]')).toContainText('Platform Admin only (the server refuses anyone else)')
    await expect(g.locator('[data-guide-choices]')).toContainText('Reject the read')
    await expect(g).not.toContainText('Mailgun')
  })
})

// SS-016 §2 (Platform Admin 1 Nov 2026 21:02): the automation control's floor names the role it checks; the boundary is unchanged
test('automation control: the rank-5 refusal names the PIM Admin, and the boundary is unchanged', () => {
  const m = fs.readFileSync('supabase/migrations/20261101090000_cf247_automation_denial_message.sql', 'utf8')
  expect(m).toContain("'30c319b8ed37dbc1df6700a0d3f5c46f', '71951aa2faf643f0dd86aae580e6c34d'")
  expect(m).toContain("if auth.uid() is null or v_rank<5 then raise exception 'PIM Admin role or above required to change automations.")
  expect(m).toContain("array[1]")
  expect(m).not.toMatch(/v_rank<[0-46-9]/)
  expect(m).toMatch(/^-- Replaces: /m)
  expect(m).toMatch(/^-- Retires: nothing/m)
})

// ---- SS-016 UR-08, UR-10, UR-11, UR-12, UR-16 (Platform Admin 1 Nov 2026 22:01) -------------------------------------------------------------
// Live facts read on 1 Nov 2026 (read only, project fxcwkweaxjtknorudmwp): provider_onboarding_settings.auto_admit on; Pipeline settings
// central.auto_approve and central.auto_approve_english_all on (job policy-auto-approve, control_rank 6); platform_toolsets openrouter
// enforcement 'observe' (security.ai_use_allowed_v1 lets every AI use run unless the mode is 'stop'); firecrawl daily_budget_on true;
// security.admin_automation_control_v1 floor rank 5, then the job's control_rank (policy-add-tests has 4, so its effective owner is the PIM Admin).
import { CONTROL_ROLE, controlOwner, ADMISSION_PATHS, ADMISSION_WORDS, BUDGET_GATES, gateFor, FRESHNESS_WORDS, checkFreshness, RETIREMENT_CRITERIA } from '../../src/guide/operatingWords.js'
import { summarise, summaryLines } from '../../scripts/test-register.mjs'

// Task text: what a person is told to do now (roles, daily routine, signals, duties, specialist tasks, SOP steps, owners and interventions).
const taskText = [
  ...G.ROLES.flatMap((r) => [r.can, ...r.daily]), ...G.DAILY_ROUTINE.map((d) => d.text), ...G.SIGNALS.flatMap((x) => [x.means, x.act]),
  ...G.ADMIN_DUTIES.flatMap((d) => d.items), ...G.SPECIALIST_TASKS.flatMap((t) => [t.task, t.source, t.escalate]),
  ...SOPS.flatMap((x) => [...x.owns, ...x.schedule.flatMap((b) => b.steps.map((st) => st.do)), ...x.weekly.map((st) => st.do), ...x.interventions.map((i) => i.action), ...x.watch, ...x.escalate]),
  ...AUTOMATION.flatMap((a) => [a.runs, a.person]),
]
const sentences = (t) => String(t).split(/(?<=[.;])\s+/)
// Screens retired from the menu (src/nav-map.js LEGACY and its retirement notes); task text may name one only to say it is gone.
const RETIRED = ['Priority queue', 'Scrapers & fetchers', 'Review queue', 'AI could not decide', 'Websites to find', 'Live activity', 'Running now', 'Levers', 'Scholarship publishing', 'Manual batch runs']

test('UR-16: no task line sends a person to a retired screen; a retired name appears only with the words that it is gone', () => {
  for (const line of taskText) for (const sn of sentences(line)) for (const name of RETIRED) {
    if (sn.includes(name)) expect(sn, `"${name}" named as a current destination`).toMatch(/retired|was |were |moved|replac|until|since|old address/i)
  }
})

test('UR-08: the PIM Admin owns no retired queue; the guide and SOP name no priority queue as a current task', () => {
  const pim = G.ROLES.find((r) => r.role === 'PIM Admin')
  expect(`${pim.can} ${pim.daily.join(' ')}`).not.toMatch(/priority queue/i)
  expect(operator.owns.find((o) => o.startsWith('PIM Admin:'))).not.toMatch(/priority queue/i)
})

test('UR-08 and UR-16: the effective role that changes an automation is the higher of rank 5 and its control rank, in every text', () => {
  expect(CONTROL_ROLE).toEqual({ 5: 'PIM Admin', 6: 'Platform Admin' })
  expect([controlOwner(4), controlOwner(5), controlOwner(6), controlOwner(undefined), controlOwner(null)]).toEqual(['PIM Admin', 'PIM Admin', 'Platform Admin', 'Platform Admin', 'Platform Admin'])
  // no active text gives automation controls to a lower role
  for (const line of [...taskText, ...Object.values(G.SCREENS).flatMap((x) => x.act)]) {
    expect(line, line).not.toMatch(/(pause|resume|run now)[^.;]*\((Viewer|Counsellor|Curator|Pipeline Operator|Operator) and above\)/i)
  }
  expect(G.SCREENS.jobs.act.join(' ')).toContain('Changed by PIM Admin or Platform Admin')
})

test('UR-08: one set of admission words; every automatic path names its switch and where a person decides instead', () => {
  expect(Object.keys(ADMISSION_WORDS)).toEqual(['proposed', 'auto', 'person', 'reads'])
  for (const a of ADMISSION_PATHS) {
    expect(ADMISSION_WORDS[a.path], a.job).toBeTruthy()
    for (const k of ['job', 'what', 'switch', 'person']) expect(a[k], `${a.job}: ${k}`).toBeTruthy()
    if (a.path === 'auto') expect(a.switch, a.job).not.toMatch(/^None/)
  }
  const jobs = ADMISSION_PATHS.map((a) => a.job)
  for (const j of ['provider-onboarding', 'policy-auto-approve', 'central-ai', 'provider-facts', 'fee-reader', 'layer4-auto-admit', 'entry-matrix-read']) expect(jobs).toContain(j)
  expect(ADMISSION_PATHS.find((a) => a.job === 'policy-auto-approve').path).toBe('auto')
  expect(ADMISSION_PATHS.find((a) => a.job === 'provider-onboarding').switch).toContain('Admit automatically')
  // the old person-only claims are gone while the automatic switches are on
  const active = JSON.stringify([taskText, G.SCREENS.providers.read])
  for (const old of ['Nothing is written before a person decides', 'admitting stays a person\'s step', 'Ready to admit waits for a person:', 'for a person to approve. Nothing is admitted']) expect(active).not.toContain(old)
  const stage4 = AUTOMATION.find((a) => a.stage === '4. Admit')
  expect(stage4.runs).toContain('policy-auto-approve')
  expect(stage4.runs).toContain('Fee schedules always wait for a Platform Admin')
})

test('UR-10: each budget notice names its gate; observe mode never reads as stopped; no drifting figures in task text', () => {
  for (const k of ['openrouter:over_guard', 'openrouter:low_balance', 'openrouter:refused', 'firecrawl:daily_budget', 'firecrawl:low_balance', 'firecrawl:cap_reached']) {
    const [t, kind] = k.split(':')
    expect(gateFor(t, kind), k).toBeTruthy()
  }
  expect(gateFor('openrouter', 'refused').gate).toContain('outside StudySearch')
  for (const g of BUDGET_GATES) for (const f of ['gate', 'mode', 'where', 'who']) expect(g[f], `${g.key}: ${f}`).toBeTruthy()
  expect(gateFor('openrouter', 'over_guard').mode).toContain('Observe only: notices only, nothing stops')
  // the notice plan follows the server's severity: info in Observe only (nothing stopped), warning in Stop at limits
  expect(fs.readFileSync('src/Toolsets.jsx', 'utf8')).toContain("case'openrouter:over_guard':return{need:'info',say:n.severity==='info'?'Nothing to do: Observe only, so nothing has stopped; it is recorded for the top-up review.'")
  const floor = G.SIGNALS.find((x) => x.see === 'OpenRouter credit approaching the floor')
  expect(floor.means).toContain('Observe only: nothing stops')
  expect(JSON.stringify([taskText, G.SCREENS.layer2.read])).not.toMatch(/will stop at the floor/)
  // live values are named, not copied: no credit totals or "(N now)" in what people are told to do
  for (const line of [...taskText, ...G.SCREENS.layer2.read]) {
    expect(line, line).not.toMatch(/\b\d{1,3}(,\d{3})+ credits\b/)
    expect(line, line).not.toMatch(/\(\d+ now\)/)
  }
})

test('UR-11: a check says which run measured it; no result is never OK; report-time figures say so', async () => {
  const f = checkFreshness([{ checked_at: '2026-11-01T10:58:00Z' }, { checked_at: '2026-11-01T10:18:00Z' }, { checked_at: null }])
  expect([f({ checked_at: '2026-11-01T10:58:00Z' }), f({ checked_at: '2026-11-01T10:18:00Z' }), f({ checked_at: null }), f({})]).toEqual(['current', 'earlier', 'missing', 'missing'])
  expect(FRESHNESS_WORDS.missing).toBe('No result yet')
  const src = fs.readFileSync('src/PlatformHealth.jsx', 'utf8')
  expect(src).toContain("pending when recorded (the live count is on Layer 4)")
  expect(src).toContain("fresh(c)==='missing'?<StatusChip value=\"missing\"")
  // academic entry requirements have a reader (AER); the coverage label names the measure, not a missing reader
  expect(fs.readFileSync('src/course-coverage.jsx', 'utf8')).toContain("academic_entry:{label:'Academic entry requirements',layer:'Not measured here yet: read and admitted on Catalogue › Entry requirements'}")
  // a rising Layer 4 count names its possible causes, not only "reviewers are behind"
  const l4 = G.SIGNALS.find((x) => x.see.startsWith('Layer 4 waiting count rises'))
  for (const w of ['new arrivals', 'evidence that cannot be opened', 'the same defect repeating', 'another step', 'report time']) expect(l4.means).toContain(w)
  expect(operator.watch.join(' ')).not.toMatch(/: reviewers are behind\./)
})

test('UR-12: retirement checks are shown with screen use and beside a retiring automation; low use alone retires nothing', () => {
  expect(RETIREMENT_CRITERIA).toHaveLength(5)
  for (const w of ['Purpose', 'Unique coverage', 'Dependencies and replacement', 'Consumers', 'Walk-through']) expect(RETIREMENT_CRITERIA.join(' ')).toContain(w)
  const use = fs.readFileSync('src/ScreenUse.jsx', 'utf8')
  expect(use).not.toContain('candidates to retire')
  expect(use).toContain('RETIREMENT_CRITERIA.map')
  expect(JSON.stringify(G.SCREENS.health.read)).not.toContain('candidates to retire')
  expect(fs.readFileSync('src/Automations.jsx', 'utf8')).toContain("no replacement named yet, so removal needs an approved decision")
})

test('UR-16: the register counts come from one pass: the category table and the narrative agree, mixed specs included', () => {
  const t = (title, deployed) => ({ title, deployed })
  const specs = [
    { kind: 'rule', tests: [t('a', false)] },
    { kind: 'regression', tests: [t('b', false), t('c @deployed', true)] },  // a deployed test inside a regression spec (the 89 / 92 case)
    { kind: 'deployed', tests: [t('d @deployed', true), t('e @deployed @live-acting', true)] },
    { kind: 'regression', tests: [t('f @responsive', false)] },
  ]
  const sum = summarise(specs)
  expect(sum.total).toEqual({ specs: 4, tests: 6, local: 3, deployed: 3 })
  expect(sum.byKind.deployed).toEqual({ specs: 1, tests: 2, local: 0, deployed: 2 })
  expect([sum.live, sum.phone, sum.safeDeployed]).toEqual([1, 1, 2])
  const md = summaryLines(sum).join('\n')
  expect(md).toContain('| **Total** | **4** | **6** | **3** | **3** |')
  expect(md).toContain('Deployed track: 3 tests (2 in deployed specs, 1 tagged `@deployed` inside rule or regression specs)')
  expect(md).toContain('so 2 safe tests run each week')
  expect(md).toContain('Local suite (`--grep-invert @deployed`): 3 tests')
})

test.describe('mocked browser (SS-016 22:01)', () => {
  test('Automations names who changes each job and how its values get in; a retired job shows the checks before removal', async ({ page }) => {
    await mockAdmin(page, { rank: 5 })
    await page.route('**/rest/v1/rpc/admin_automations_read', (route) => route.fulfill({ contentType: 'application/json', body: JSON.stringify({
      generated_at: new Date().toISOString(), rank: 5, events: [],
      jobs: [
        { job: 'policy-auto-approve', area: 'Admission', sort: 1, label: 'Approve checked AI readings of central pages', description: 'Every 10 minutes.', schedule: '*/10 * * * *', active: true, control_rank: 6, batch: null, last: null, runs_24h: 0, failed_24h: 0 },
        { job: 'policy-add-tests', area: 'Enrichment', sort: 1, label: 'English policies: add new tests', description: 'Hourly.', schedule: '5 * * * *', active: true, control_rank: 4, batch: null, last: null, runs_24h: 0, failed_24h: 0 },
        { job: 'l4-rule-low-agreement', area: 'Admission', sort: 2, label: 'Review rule: sources disagree', description: 'RETIRED.', schedule: '0 3 * * *', active: false, control_rank: 5, batch: null, last: null, runs_24h: 0, failed_24h: 0,
          retirement: { status: 'retiring', replaced_by: null, retire_after: '2026-11-14' } },
      ] }) }))
    await page.goto('/#scheduled-jobs?tab=automations')
    const auto = page.locator('tr[data-job="policy-auto-approve"]')
    await expect(auto.locator('[data-control-owner]')).toHaveText('Changed by Platform Admin')
    await expect(auto.locator('[data-admission-path="auto"]')).toContainText('Automatic while its switch is on')
    await expect(auto).toContainText('Platform Admin only')
    await expect(page.locator('tr[data-job="policy-add-tests"] [data-control-owner]')).toHaveText('Changed by PIM Admin')
    const retired = page.locator('tr[data-job="l4-rule-low-agreement"]')
    await expect(retired).toContainText('no replacement named yet, so removal needs an approved decision')
    await retired.locator('[data-retirement-criteria] summary').click()
    await expect(retired.locator('[data-retirement-criteria]')).toContainText('Unique coverage')
  })

  test('the Platform guide shows who admits, the budget gates and the retirement checks; health checks say which run measured them', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#platform-guide')
    const g = page.locator('[data-platform-guide]')
    await expect(g.locator('[data-guide-admission-path="policy-auto-approve"]')).toContainText('Automatic while its switch is on')
    await expect(g.locator('[data-guide-gate="openrouter-refused"]')).toContainText('outside StudySearch')
    await expect(g.locator('[data-guide-retire]')).toContainText('Few opens on Platform health › Screen use is a question, not a decision')

    const old = '2026-11-01T07:18:00Z', cur = '2026-11-01T10:58:00Z'
    await page.route('**/rest/v1/rpc/admin_read', async (route) => {
      const body = route.request().postDataJSON() || {}
      if ((body.p_operation || body.operation) !== 'platform_health') return route.fallback()
      return route.fulfill({ contentType: 'application/json', body: JSON.stringify({ generated_at: cur, overall: 'ok', counts: {}, issues: [], history: [], checks: [
        { key: 'cron', area: 'scheduled jobs', label: 'Scheduled jobs', status: 'ok', detail: {}, checked_at: cur },
        { key: 'field_stalled', area: 'coverage', label: 'Fields not moving', status: 'ok', detail: {}, checked_at: old },
        { key: 'edge_deployed', area: 'edge functions', label: 'Edge functions deployed', status: 'ok', detail: {}, checked_at: null } ] }) })
    })
    await page.goto('/#platform-health')
    await expect(page.locator('[data-check-freshness="current"]')).toContainText('This run')
    await expect(page.locator('[data-check-freshness="earlier"]')).toContainText('From an earlier run')
    const missing = page.locator('tr', { has: page.locator('[data-check-freshness="missing"]') })
    await expect(missing).toContainText('No result yet')
    await expect(missing).not.toContainText('OK')
    await expect(page.locator('[data-health-earlier="2"]')).toBeVisible()
  })

  test('a budget notice names its gate and who changes it', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#models-services?tab=limits')
    await page.locator('[data-card="services.toolsets"] .cf-card-toggle').click()
    const n = page.locator('[data-toolset-notices] [data-notice="openrouter:3:refused:key_limit"]')
    await expect(n.locator('[data-notice-gate="openrouter-refused"]')).toContainText('Gate: Refused by OpenRouter (outside StudySearch)')
  })
})

// SS-016 acceptance S1, G1–G3 (role walkthrough fixtures, overnight mandate 1 Nov 2026 22:01): refusals and links name the role that acts
test('automation control: the per-automation refusal names its role; guide links above a role say which role opens them', () => {
  const m = fs.readFileSync('supabase/migrations/20261101110000_cf247_automation_owner_refusal.sql', 'utf8')
  expect(m).toContain("'71951aa2faf643f0dd86aae580e6c34d', '431aff603f21b8c8a030073b07a08259'")
  expect(m).toContain("if v_rank<coalesce(c.control_rank,6) then raise exception 'this automation is changed by the %'")
  expect(m).toMatch(/^-- Retires: nothing/m)
  expect(G.SPECIALIST_TASKS.find((t) => t.task === 'Read an entry requirement source again').tab).toBe('sources')
  const pg = fs.readFileSync('src/PlatformGuide.jsx', 'utf8')
  expect(pg).toContain('data-opens-from={m}>Opens from {roleName(m)} (rank {m})')
})

// ---- SS-016 UR-03 ancestor guard (Agent A rehearsal, 1 Nov 2026): a stale writer who pulls first and then overwrites the mirror with an
// export from an older source makes a fast-forward push git accepts; --write-mirror refuses it before writing anything.
import { mirrorGuard, sopDocument } from '../../scripts/export-sops.mjs'
import { execFileSync } from 'node:child_process'

test('UR-03: a mirror is written only by the same or a newer source; an older source or an unknown commit is refused', () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'sop-ancestor-'))
  const repo = path.join(tmp, 'repo'), mirror = path.join(tmp, 'mirror')
  fs.mkdirSync(repo); fs.mkdirSync(mirror)
  const git = (...a) => execFileSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@example.test', '-c', 'commit.gpgsign=false', ...a], { cwd: repo, encoding: 'utf8' }).trim()
  try {
    git('init', '-q')
    git('commit', '-q', '--allow-empty', '-m', 'older'); const older = git('rev-parse', '--short=12', 'HEAD')
    git('commit', '-q', '--allow-empty', '-m', 'newer'); const newer = git('rev-parse', '--short=12', 'HEAD')
    const put = (commit) => { for (const s of SOPS) fs.writeFileSync(path.join(mirror, `${s.id}.md`), sopDocument(s, commit)) }
    const guard = (head) => mirrorGuard(mirror, { repo, head })

    put(newer)                                      // the mirror holds the newer export; an older source tries to write over it
    expect(guard(older).every((r) => !r.ok)).toBe(true)
    expect(guard(older)[0].detail).toContain('not ' + older + ' or one of its ancestors')
    expect(guard(newer).every((r) => r.ok)).toBe(true)  // the same source may write again
    put(`${older}+local`)                           // a newer source over an older mirror (a "+local" export counts as its commit)
    expect(guard(newer).every((r) => r.ok)).toBe(true)
    put('0123456789ab')                             // a commit this clone does not know
    const unknown = guard(newer)
    expect(unknown.every((r) => !r.ok)).toBe(true)
    expect(unknown[0].detail).toContain('git fetch first')
    put('unknown')                                  // an export that could not read its commit cannot be checked
    expect(guard(newer).every((r) => !r.ok)).toBe(true)
    fs.rmSync(mirror, { recursive: true }); fs.mkdirSync(mirror)
    expect(guard(older).every((r) => r.ok && r.detail === 'new file')).toBe(true)
  } finally { fs.rmSync(tmp, { recursive: true, force: true }) }
})

test('UR-03: --write-mirror writes nothing when one mirror file is refused, and writes all files when none is', () => {
  const run = (dir) => spawnSync(process.execPath, ['scripts/export-sops.mjs', '--write-mirror', dir], { encoding: 'utf8' })
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'sop-write-'))
  try {
    const stale = sopDocument(SOPS[1], '0123456789ab')
    fs.writeFileSync(path.join(tmp, `${SOPS[1].id}.md`), stale)
    const refused = run(tmp)
    expect(refused.status, refused.stdout + refused.stderr).toBe(1)
    expect(refused.stdout).toContain('nothing was written')
    expect(fs.existsSync(path.join(tmp, `${SOPS[0].id}.md`))).toBe(false)
    expect(fs.readFileSync(path.join(tmp, `${SOPS[1].id}.md`), 'utf8')).toBe(stale)
    fs.rmSync(path.join(tmp, `${SOPS[1].id}.md`))
    const ok = run(tmp)
    expect(ok.status, ok.stdout + ok.stderr).toBe(0)
    expect(ok.stdout).toContain(`Wrote ${SOPS.length} SOP documents`)
    expect(run(tmp).status).toBe(0)                 // writing again from the same source is allowed
  } finally { fs.rmSync(tmp, { recursive: true, force: true }) }
})

// ---- SS-016 P1 and P2 (acceptance walkthrough findings, 1 Nov 2026): the guides say only what the server allows. Live (read only, 1 Nov 2026):
// public.admin_layer4_inbox refuses a choice below coalesce(choice rank, 4) ("your role cannot make this choice"); AER items need rank 6;
// there is no shortlist or notes function or table. No rank is changed by this; the words follow the server.
test('P1: a Curator reads Layer 4 and corrects records; Inbox decisions are the Pipeline Operator\'s, AER the Platform Admin\'s', () => {
  const cur = G.ROLES.find((r) => r.role === 'Curator')
  const said = `${cur.can} ${cur.daily.join(' ')}`
  for (const w of ['Reads Layer 4 items and their evidence', 'every Layer 4 › Inbox choice needs the Pipeline Operator (rank 4) or above', 'correct the value on the course or entry requirement record', 'hand the Inbox decision to the Pipeline Operator', 'entry requirement (AER) items to the Platform Admin']) expect(said).toContain(w)
  expect(said).not.toMatch(/decide the items waiting|Layer 4 decisions except|give the missing provider websites/i)
  // no SOP step or automation line gives an Inbox decision to a Curator
  for (const st of operator.schedule.flatMap((b) => b.steps)) if (/Layer 4 › Inbox \((Course link|Held scholarship|Website needed)\)/.test(st.do)) expect(st.role, st.do).toBe('Pipeline Operator')
  for (const a of AUTOMATION) expect(a.person, a.stage).not.toMatch(/Curators decide/)
  expect(operator.owns.find((o) => o.startsWith('Pipeline Operator:'))).toContain('Layer 4 › Inbox decisions')
  expect(operator.interventions.find((x) => x.trigger === 'Layer 4 Review item').action).toMatch(/^Pipeline Operator and above: decide/)
  expect(G.SIGNALS.find((x) => x.see.startsWith('Layer 4 waiting count rises')).who).toMatch(/^Pipeline Operator/)
})

test('P2: no shortlist or notes claim for Counsellors; they search, read, quote and report from Zoho', () => {
  for (const text of [guideText, sopText]) expect(text).not.toMatch(/shortlist|and notes/i)
  const c = G.ROLES.find((r) => r.role === 'Counsellor')
  for (const w of ['Search and read', 'quote what the record shows', 'report a wrong or missing value from Zoho', 'Changes nothing in StudySearch']) expect(c.can).toContain(w)
})

test('P1: the Layer 4 screen entry gives Inbox choices and website entry to the Pipeline Operator, not the Curator', () => {
  const l4 = JSON.stringify(G.SCREENS.layer4)
  expect(l4).not.toMatch(/(Save|website)[^"]{0,40}\(Curator and above\)/i)
  expect(G.SCREENS.layer4.act.join(' ')).toContain('Approve, correct or reject, with a reason (Pipeline Operator and above')
})
