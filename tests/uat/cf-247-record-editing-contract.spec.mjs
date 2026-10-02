// v2.15.114 record editing (Decision 179, CRUD first): values entered by hand always win over automation.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const read = p => fs.readFileSync(p, 'utf8')

test('database: guard triggers on every fact table, courses and providers; guarded edits; role checks; grants', () => {
  const m = read('supabase/migrations/20260930120000_cf247_crud_manual_first.sql')
  for (const t of ['course_links', 'course_intakes', 'course_english_requirements', 'course_fees'])
    expect(m).toContain(`create trigger manual_lock_guard before insert or update or delete on catalogue.${t} for each row execute function security.manual_fact_guard();`)
  for (const t of ['courses', 'providers'])
    expect(m).toContain(`create trigger manual_lock_guard before update on catalogue.${t} for each row execute function security.manual_field_guard();`)
  expect(m).toContain("if coalesce(current_setting('cf.manual_edit', true), '') = 'on' then")
  expect(m).toContain("'755335cd5cf4caa469e88482bb430ec6'")
  expect(m).toContain("'99ce501d5e0379f08ffff370d3273145'")
  expect(m).toContain("if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required'")
  expect(m).toContain("if p_action in ('archive','restore') and v_rank < 5 then raise exception 'PIM Operator role or above required'")
  expect(m).toContain("security.current_role_rank() < 5 then raise exception 'PIM Operator role or above required'")
  for (const f of ['admin_course_edit_read(uuid)', 'admin_course_edit(uuid, text, jsonb)', 'admin_course_create(jsonb)', 'admin_provider_edit_read(uuid)', 'admin_provider_edit(uuid, text, jsonb)', 'admin_provider_create(jsonb)']) {
    expect(m).toContain(`revoke all on function public.${f} from public, anon;`)
    expect(m).toContain(`grant execute on function public.${f} to authenticated;`)
  }
  expect(m).toContain("escalation_reason = 'Superseded: value entered by hand on the course page'")
  const w = read('supabase/functions/coverage-sweep/index.ts')
  expect(w).toContain('|| (it.manual === true ? "manual" : null)')
})

test.describe('mocked browser', () => {
  test('course: edit tuition, English and the official page, remove intakes, hand a value back to automation', async ({ page }) => {
    await mockAdmin(page)
    page.on('dialog', d => d.accept())
    await page.goto('/#courses?id=0b1fb6d4-c02f-47c7-98d0-9f0d57240fd5')
    const panel = page.locator('[data-editor="course"]')
    await expect(panel).toContainText('1 value entered by hand') // v2.15.159: values and their Change buttons show at once; no fold
    await expect(panel.getByRole('button', { name: /Edit this course/ })).toHaveCount(0)
    await expect(panel).toContainText('Entered by hand')
    await panel.getByLabel(/^Reason for the change/).fill('Checked on the RMIT website')
    await panel.getByRole('button', { name: 'Change Tuition (international)' }).click()
    await panel.getByLabel('Tuition amount').fill('39,500')
    await panel.getByLabel('Fee period').selectOption('per_semester')
    await panel.getByRole('button', { name: 'Save' }).click()
    await expect.poll(() => page.l3calls.find(c => c.p_action === 'set_tuition')).toEqual({ p_course_id: '0b1fb6d4-c02f-47c7-98d0-9f0d57240fd5', p_action: 'set_tuition', p_args: { amount: '39500', fee_year: '2027', basis: 'per_semester', currency: 'AUD', reason: 'Checked on the RMIT website' } })
    await panel.getByRole('button', { name: 'Change English requirement' }).click()
    await panel.getByLabel('Test 1 overall score').fill('7')
    await panel.getByLabel('Test 1 lowest band').fill('6.5')
    await panel.getByRole('button', { name: 'Save' }).click()
    await expect.poll(() => page.l3calls.find(c => c.p_action === 'set_english')?.p_args?.tests).toEqual([{ test: 'IELTS', overall: '7', components: { min_band: 6.5 } }])
    await panel.getByRole('button', { name: 'Change Official course page' }).click()
    await panel.locator('input[type="url"]').fill('https://www.rmit.edu.au/study/ad029')
    await panel.getByRole('button', { name: 'Save' }).click()
    await expect.poll(() => page.l3calls.find(c => c.p_action === 'set_official_url')?.p_args?.url).toBe('https://www.rmit.edu.au/study/ad029')
    await panel.getByRole('button', { name: 'Remove Intakes' }).click()
    await expect.poll(() => page.l3calls.some(c => c.p_action === 'remove_intakes')).toBe(true)
    await panel.locator('.re-row', { hasText: 'Tuition (international)' }).getByRole('button', { name: 'Let automation update this' }).click()
    await expect.poll(() => page.l3calls.find(c => c.p_action === 'release')?.p_args?.field).toBe('tuition')
    await expect(panel.getByRole('button', { name: 'Archive course' })).toBeVisible()
    await expect(panel).toContainText('Changes made by hand (1)')
  })

  test('add a course and a provider', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#courses')
    await page.getByRole('button', { name: 'Add course' }).click()
    const dlg = page.getByRole('dialog', { name: 'Add a course' })
    await dlg.getByLabel('Find the provider').fill('Macq')
    await dlg.getByRole('button', { name: 'Choose' }).click()
    await dlg.locator('label', { hasText: 'Course title' }).locator('input').fill('Graduate Certificate in Test Design')
    await dlg.getByRole('button', { name: 'Add course' }).click()
    await expect.poll(() => page.l3calls.find(c => c.p_args?.title)?.p_args).toMatchObject({ title: 'Graduate Certificate in Test Design', provider_id: 'p-mq' })
    await page.goto('/#providers')
    await page.getByRole('button', { name: 'Add provider' }).click()
    const pd = page.getByRole('dialog', { name: 'Add a provider' })
    await pd.locator('label', { hasText: 'Provider name' }).locator('input').fill('Example Institute of Technology')
    await pd.locator('label', { hasText: /^Country/ }).locator('select').selectOption('c-nz')
    await pd.getByRole('button', { name: 'Add provider' }).click()
    await expect.poll(() => page.l3calls.find(c => c.p_args?.name)?.p_args).toMatchObject({ name: 'Example Institute of Technology', country_id: 'c-nz' })
  })

  test('viewer: no Add button', async ({ page }) => {
    await mockAdmin(page, { rank: 1 })
    await page.goto('/#courses')
    await expect(page.getByRole('button', { name: 'Compare courses' })).toBeVisible()
    await expect(page.getByRole('button', { name: 'Add course' })).toHaveCount(0)
  })
})
