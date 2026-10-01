// v2.15.120 Edit in list: Courses and Providers edited in place, one cell at a time, using the same guarded edits.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

test('database: the list read is role-checked, capped and granted; saves reuse the guarded per-field edits', () => {
  const m = fs.readFileSync('supabase/migrations/20260930180000_cf247_list_edit_rows.sql', 'utf8')
  expect(m).toContain("if auth.uid() is null or v_rank < 3 then raise exception 'assigned CourseFinder role required'")
  expect(m).toContain("raise exception 'at most 100 rows at a time'")
  expect(m).toContain('revoke all on function public.admin_catalogue_edit_rows(text, uuid[]) from public, anon;')
  expect(m).toContain('grant execute on function public.admin_catalogue_edit_rows(text, uuid[]) to authenticated;')
  const ui = fs.readFileSync('src/ListEdit.jsx', 'utf8')
  expect(ui).toContain("rpc:'admin_course_edit'")
  expect(ui).toContain("rpc:'admin_provider_edit'")
})

test.describe('mocked browser', () => {
  test('edit a title, a duration and a course page in the list; hand-entered values show a lock', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#courses')
    await page.getByRole('button', { name: 'Edit in list' }).click()
    const t = page.locator('[data-list-edit="course"]')
    await expect(t.locator('tbody tr[data-edit-row]')).toHaveCount(2)
    await expect(t.locator('[data-edit-row="0b1fb6d4-c02f-47c7-98d0-9f0d57240fd5"] .le-lock')).toHaveCount(1)
    await t.getByRole('button', { name: 'Edit Title for Bachelor of Business (Accountancy)' }).click()
    await t.getByLabel('Title for Bachelor of Business (Accountancy)').fill('Bachelor of Business in Accountancy')
    await t.getByLabel('Title for Bachelor of Business (Accountancy)').press('Enter')
    await expect.poll(() => page.l3calls.find(c => c.p_args?.field === 'display_title')).toEqual({ p_course_id: 'c2', p_action: 'set_core', p_args: { field: 'display_title', value: 'Bachelor of Business in Accountancy' } })
    await expect(t.locator('[data-edit-row="c2"] .le-lock')).toHaveCount(1)
    await t.getByRole('button', { name: 'Edit Duration for Bachelor of Business (Accountancy)' }).click()
    await t.getByLabel('Duration for Bachelor of Business (Accountancy)', { exact: true }).fill('3')
    await t.getByLabel('Duration for Bachelor of Business (Accountancy) unit').selectOption('years')
    await t.getByLabel('Duration for Bachelor of Business (Accountancy)', { exact: true }).press('Enter')
    await expect.poll(() => page.l3calls.filter(c => ['duration_value', 'duration_unit'].includes(c.p_args?.field)).map(c => c.p_args)).toEqual([{ field: 'duration_value', value: '3' }, { field: 'duration_unit', value: 'years' }])
    await t.getByRole('button', { name: 'Edit Course page for Bachelor of Business (Accountancy)' }).click()
    await t.getByLabel('Course page for Bachelor of Business (Accountancy)').fill('https://www.rmit.edu.au/accountancy')
    await t.getByLabel('Course page for Bachelor of Business (Accountancy)').press('Tab')
    await expect.poll(() => page.l3calls.find(c => c.p_action === 'set_official_url')?.p_args).toEqual({ url: 'https://www.rmit.edu.au/accountancy' })
    await page.getByRole('button', { name: 'Done editing' }).click()
    await expect(page.locator('[data-list-edit]')).toHaveCount(0)
  })
})
