// Guards: SS-016 UR-01, UR-02, UR-03, UR-17 (Platform Admin 1 Nov 2026 20:08)
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
  expect(G.ROLES.find((r) => r.role === 'Curator').can).toContain('Layer 4 decisions except entry requirement (AER) items, which only the Platform Admin decides')
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
