// CF-247 Decisions 226 and 227 (v2.15.153): concentrate on intakes and English requirements.
import fs from 'node:fs/promises'
import { execFileSync } from 'node:child_process'
import os from 'node:os'
import path from 'node:path'
import { test, expect } from '@playwright/test'

test('Decision 226: quote failures sent back to Layer 3; tuition retry respects the regulator gate', async () => {
  const m = await fs.readFile('supabase/migrations/20261002182700_cf247_quote_failures_rerun.sql', 'utf8')
  expect(m).toContain("l.field_code in ('course_intake', 'course_english')")
  expect(m).toContain("like 'The AI quoted text that is not on the saved page%'")
  expect(m).toContain("status = 'superseded'")
  expect(m).toContain('9e8d37c5fa530978105e50ceb3a9f3eb')
  expect(m).toContain('security.tuition_chase_enabled((select c.provider_id from catalogue.courses c where c.id=entity_id))')
  expect(m).not.toMatch(/\bdrop\s|delete\s+from|truncate/i)
})

test('Decision 227: English policy and calendar documents are read, parsed into proposals, applied only after approval', async () => {
  const read = await fs.readFile('supabase/migrations/20261002182800_cf247_read_english_calendar_sources.sql', 'utf8')
  expect(read).toContain("or f.kind in ('english_policy', 'intake_calendar'))")
  expect(read).toContain('08626bd03d652647b2fc8c49b08c8ac2')
  const prop = await fs.readFile('supabase/migrations/20261002183000_cf247_provider_policy_proposals.sql', 'utf8')
  expect(prop).toContain('create table if not exists pipeline.provider_policy_proposals')
  expect(prop).toContain("status in ('proposed', 'no_values', 'approved', 'rejected', 'superseded')")
  const plan = await fs.readFile('supabase/migrations/20261002183100_cf247_english_policy_defaults.sql', 'utf8')
  for (const s of ["'held|research degree'", "'held|double degree'", "'held|named in the policy (it may have its own requirement)'", "'held|level not covered by the policy default'",
    "when q.any_row then 'other_value'", "when q.locked then 'set_by_hand'", "when q.in_review then 'in_review'", "when q.in_l3 or q.page_waiting then 'waiting'",
    "where outcome = 'write' loop", "if x.status <> 'approved' then raise exception 'proposal is not approved'", 'security.current_role_rank() < 6', "cron.schedule('provider-english-defaults'"]) expect(plan).toContain(s)
  // a course with any English row is never written (hand-entered and course-page values are kept)
  expect(plan).toContain('exists (select 1 from catalogue.course_english_requirements r where r.course_id = co.id) any_row')
  const gate = await fs.readFile('supabase/migrations/20261002183200_cf247_english_policy_agreement_gate.sql', 'utf8')
  expect(gate).toContain('if v_ag + v_df >= 10 and v_df > v_ag then')
  expect(gate).toContain('bff1631490ab3348960e8564b8909eba')
  for (const m of [read, prop, plan, gate]) expect(m).not.toMatch(/\bdrop\s|delete\s+from|truncate|on delete cascade/i)
  const w = await fs.readFile('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(w).toMatch(/coverage-sweep-worker-v0\.(?:9\.[5-9]|1\d\.\d+)/)
  expect(w).toContain('mode === "provider_facts_inspect" || mode === "provider_facts_parse"')
  expect(w).toContain('svc_provider_policy_record')
})

async function policyParser() {
  const out = path.join(os.tmpdir(), `policy-${process.pid}.mjs`)
  execFileSync('npx', ['esbuild', 'supabase/functions/coverage-sweep/policy.ts', '--format=esm', `--outfile=${out}`, '--log-level=error'])
  return import(out)
}

test('policy parser: level defaults, split levels, named courses, exclusions', async () => {
  const { englishPolicy, calendarStarts } = await policyParser()
  const ielts = (r, lv) => r.defaults[lv]?.find((q) => q.test_code === 'IELTS')
  const deakin = englishPolicy('Deakin’s current minimum IELTS requirement is 6.0 (CEFR B2) for undergraduate courses and 6.5 (CEFR C1) for postgraduate coursework courses. Some courses have higher requirements, so always check your course page.')
  expect(ielts(deakin, 'undergraduate').overall_score).toBe(6)
  expect(ielts(deakin, 'postgraduate').overall_score).toBe(6.5)
  expect(deakin.caveats).toContain('higher_unlisted')
  const flinders = englishPolicy('## Undergraduate programs\n| Undergraduate courses | IELTS (Academic) | TOEFL iBT* |\n|---|---|---|\n| Applicable to all undergraduate courses except those specified below | 6.0 Overall with 6.0 Speaking 6.0 Writing | 72 Total score |\n| Exercise Science<br>Human Nutrition | 6.5 Overall | 79 |')
  expect(ielts(flinders, 'undergraduate')).toMatchObject({ overall_score: 6, component_scores: { speaking: 6, writing: 6 } })
  expect(flinders.exceptions.map((e) => e.name)).toEqual(['Exercise Science', 'Human Nutrition'])
  const cqu = englishPolicy('- [CB77 – Bachelor of Science (Chiropractic)](https://x) – Minimum academic IELTS score of 7.0 with no individual band score of less than 7.0.')
  expect(cqu.style).toBe('named_courses')
  expect(cqu.exceptions[0]).toMatchObject({ name: 'Bachelor of Science (Chiropractic)' })
  // pathways, study abroad, "courses that require", "any course with" and equivalence statements are not defaults
  for (const md of ['## Study abroad\n| Program | IELTS |\n|---|---|\n| All programs except where specified below | 6.0 overall (min. 5.5 in each subtest) |',
    'undergraduate and postgraduate QUT courses that require a minimum IELTS score of 6.5 and no sub-score less than 6.0.',
    'This applies to Nursing courses as well as any course with an IELTS score of 7.0 or more.'])
    expect(englishPolicy(md).defaults).toEqual({})
  // a document with several different IELTS scores and no level is not a default
  expect(englishPolicy('| Test | Overall |\n|---|---|\n| IELTS | 6.5 |\n\n## Bachelor of Nursing\n| Test | Overall |\n|---|---|\n| IELTS | 7.0 |').defaults).toEqual({})
  const cal = calendarStarts('## 2027 key dates\n| Date | Event |\n|---|---|\n| 1 March 2027 | Semester 1 starts |\n| 26 July 2027 | Semester 2 begins |\n| 10 June 2027 | Semester 1 exams |')
  expect(cal.periods.map((p) => `${p.period}:${p.months.join(',')}`)).toEqual(['semester 1:3', 'semester 2:7'])
})

test.describe('browser: English policies panel', () => {
  test('Platform Admin reviews courses, sees agreement, cannot approve a default most pages disagree with, approves', async ({ page }) => {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    await mockAdmin(page)
    page.on('dialog', (d) => d.accept())
    await page.goto('/#coverage?tab=attributes')
    const pp = page.locator('[data-provider-policies]')
    await expect(pp.getByRole('heading', { name: 'English policies' })).toBeVisible()
    await expect(pp.locator('[data-policy="ep1"] [data-policy-default="undergraduate"]')).toContainText('IELTS 6 (no band below 6)')
    await expect(pp.locator('[data-policy="ep1"] [data-agreement]')).toContainText('57 agree · 12 differ')
    await expect(pp.locator('[data-policy="ep2"] [data-blocked]')).toBeVisible()
    await expect(pp.locator('[data-policy="ep2"]').getByRole('button', { name: 'Approve' })).toBeDisabled()
    await expect(pp.locator('[data-policy="ep2"] [data-caveat="level_not_stated"]')).toBeVisible()
    await pp.getByRole('button', { name: 'Flinders University' }).click()
    await expect(pp.locator('[data-policy-rows] [data-outcome="held"]')).toContainText('Held back: research degree')
    await expect(pp.locator('[data-policy-rows] [data-outcome="differs"]')).toContainText('Different score on record (not changed)')
    await pp.locator('[data-policy="ep1"]').getByRole('button', { name: 'Approve' }).click()
    await expect.poll(() => page.l3calls.find((c) => c.policyDecide)?.policyDecide).toEqual({ p_id: 'ep1', p_action: 'approve', p_note: null })
    await pp.getByRole('button', { name: 'Academic calendars' }).click()
    await expect(pp.locator('[data-policy="cp1"]')).toContainText('Semester 1: March')
  })

  test('v2.15.155: bulk approval sends only documents that can be approved; blocked ones keep a reason', async ({ page }) => {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    await mockAdmin(page)
    page.on('dialog', (d) => d.accept())
    await page.goto('/#coverage?tab=attributes')
    const pp = page.locator('[data-provider-policies]')
    await expect(pp.locator('[data-policy-bulk]')).toBeVisible()
    await expect(pp.locator('[data-policy="ep2"]').getByRole('button', { name: 'Approve' })).toHaveAttribute('title', /cannot be approved/)
    await pp.getByRole('button', { name: /Select all that can be approved/ }).click()
    await expect(pp.locator('[data-policy="ep2"] input[type=checkbox]')).not.toBeChecked()
    await pp.getByRole('button', { name: /Approve selected/ }).click()
    await expect.poll(() => page.l3calls.find((c) => c.policyBulk)?.policyBulk?.p_action).toEqual('approve')
    expect(page.l3calls.find((c) => c.policyBulk).policyBulk.p_ids).not.toContain('ep2')
    await expect(pp.locator('[data-policy-bulk-result]')).toContainText('Approved')
  })

  test('v2.15.155: Platform Admin raises the course-page search cap on the Priority queue screen', async ({ page }) => {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    await mockAdmin(page)
    page.on('dialog', (d) => d.accept())
    await page.goto('/#jobs?tab=priority')
    const c = page.locator('[data-search-cap]')
    await expect(c.locator('[data-cap-reached]')).toContainText('320 searches are waiting')
    await c.getByLabel('Course-page search monthly cap').fill('80000')
    await c.getByRole('button', { name: 'Save cap' }).click()
    await expect.poll(() => page.l3calls.find((x) => x.searchCap)?.searchCap).toEqual({ p_monthly_credit_cap: 80000 })
    await expect(c).toContainText('Saved: 80,000 credits a month.')
  })

  test('Pipeline Operator sees the panel but cannot decide', async ({ page }) => {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    await mockAdmin(page, { rank: 4 })
    await page.goto('/#coverage?tab=attributes')
    const pp = page.locator('[data-provider-policies]')
    await expect(pp.locator('[data-policy="ep1"]')).toContainText('Waiting for a Platform Admin')
    await expect(pp.getByRole('button', { name: 'Approve' })).toHaveCount(0)
  })
})
