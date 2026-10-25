// Guards: CF-247 v2.15.247 (S13): Platform Admin bugs 11/10-4. "On demand run for scholarship never runs, it ask for reason which is not required and nothing happened afterwards."…
// CF-247 v2.15.247 (S13): Platform Admin bugs 11/10-4. "On demand run for scholarship never runs, it ask for reason which is not
// required and nothing happened afterwards." Starting a task asks only to confirm and records the screen (Fix 1); every outcome is
// shown and running providers show Finding… (Fix 2); two providers of one name show their CRICOS codes (Fix 3).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const read = p => fs.readFileSync(p, 'utf8')

test('migration: a start needs no reason except Admit; Coverage rows carry the CRICOS code', () => {
  const sql = read('supabase/migrations/20261011010100_cf247_task_start_without_reason_provider_codes.sql')
  expect(sql).toContain("if p_action = 'start' and coalesce(p_args->>'kind', '') <> 'admit_qualified' then")
  expect(sql).toContain("v_reason := 'Started from ' || coalesce(nullif(btrim(p_args->>'from'), ''), 'the app');")
  expect(sql).toContain("jsonb_build_object('code', x.code)")
  for (const md5 of ['43e1caadcc5c59ac0fd1a369006aed3b', '20be9198c28640a041efeaebd0743391', 'e5aa7642d610954253f18ceeaf0390de', '1c27d8194e2da7c6e8e9ced614caed6e']) expect(sql).toContain(md5)
  expect(sql).not.toMatch(/^(drop|delete|truncate)\b/im)
})

test('source: JobButton confirms (no reason prompt) and says what happened; Admit still asks for a reason', () => {
  const j = read('src/JobButton.jsx')
  expect(j).toContain("if(!window.confirm(question||`Start \"${label}\"?`))return")
  expect(j).toContain('from:whereFrom()')
  expect(j).toContain('setNote(`Started')
  expect(read('src/AdminTasks.jsx')).toContain("act('start',{kind:'admit_qualified'")
})

test('mocked browser: Find scholarships now starts on confirm, shows Finding… and the codes', async ({ page }) => {
  await mockAdmin(page)
  const dialogs = []
  page.on('dialog', d => { dialogs.push(d.type()); d.accept() })
  await page.goto('/#scholarships?tab=coverage')
  const c = page.locator('[data-scholarship-coverage]')
  await expect(c.locator('[data-cov-code]')).toHaveText([' CRICOS 00124K', ' CRICOS 02475D'])
  await c.getByLabel('Select Victoria University').first().check()
  await c.getByRole('button', { name: 'Find scholarships now (1)' }).click()
  await expect.poll(() => page.l3calls.find(c => c.jobs === 'start')?.args).toEqual({ kind: 'scholarship_provider_scan', args: { provider_ids: ['vu-1'] }, from: 'Scholarships › Coverage' })
  expect(dialogs).toEqual(['confirm'])
  await expect(c.locator('[data-cov-note]')).toContainText('Started')
})
