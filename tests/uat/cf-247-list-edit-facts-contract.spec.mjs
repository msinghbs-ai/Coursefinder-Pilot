// v2.15.130 Edit in list for Courses covers tuition, intakes and English (screen review crs-listedit-fields).
// Saves reuse admin_course_edit set_tuition / set_intakes / set_english; start dates and sub-scores already held are kept.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

test('database: guarded replacement returns tuition, intakes, English and the active tests', () => {
  const m = fs.readFileSync('supabase/migrations-archive/20261001140000_cf247_list_edit_course_facts.sql', 'utf8')
  expect(m).toContain("if v is distinct from 'dca6b9564c88f13482ba11ed56a54952' then")
  for (const k of ["'tuition'", "'intakes'", "'english'", "'english_tests'", "'start_date', i.start_date", "'components', e.component_scores"]) expect(m).toContain(k)
  expect(m).toContain('grant execute on function public.admin_catalogue_edit_rows(text, uuid[]) to authenticated;')
})

test.describe('mocked browser', () => {
  test('edit tuition, intakes and English in the list', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#courses')
    await page.getByRole('button', { name: 'Edit in list' }).click()
    const t = page.locator('[data-list-edit="course"]'), row = t.locator('[data-edit-row="c2"]'), name = 'Bachelor of Business (Accountancy)'
    await expect(row).toContainText('A$60,952 per year · 2027')
    await expect(row).toContainText('Semester 1 2027, Semester 2 2027')
    await expect(row).toContainText('IELTS 6.5, PTE 64')
    await t.getByRole('button', { name: `Edit Tuition for ${name}` }).click()
    await t.getByLabel(`Tuition for ${name} amount`).fill('62000')
    await t.getByLabel(`Tuition for ${name} amount`).press('Enter')
    await expect.poll(() => page.l3calls.find(c => c.p_action === 'set_tuition')?.p_args).toEqual({ amount: '62000', fee_year: '2027', basis: 'annual' })
    await t.getByRole('button', { name: `Edit Intakes for ${name}` }).click()
    await t.getByLabel(`Intakes for ${name}`).fill('Semester 1 2027, Summer 2027')
    await t.getByLabel(`Intakes for ${name}`).press('Enter')
    await expect.poll(() => page.l3calls.find(c => c.p_action === 'set_intakes')?.p_args).toEqual({ intakes: [{ label: 'Semester 1', year: 2027, start_date: '2027-02-22' }, { label: 'Summer', year: 2027, start_date: null }] })
    await t.getByRole('button', { name: `Edit English for ${name}` }).click()
    await t.getByLabel(`English for ${name}`).fill('IELTS 6.5, PTE 65, TOEFL 90')
    await t.getByLabel(`English for ${name}`).press('Enter')
    await expect.poll(() => page.l3calls.find(c => c.p_action === 'set_english')?.p_args).toEqual({ tests: [{ test: 'IELTS', overall: '6.5', components: { reading: 6, writing: 6 } }, { test: 'PTE', overall: '65', components: {} }, { test: 'TOEFL_IBT', overall: '90', components: {} }] })
    await t.getByRole('button', { name: `Edit English for ${name}` }).click()
    await t.getByLabel(`English for ${name}`).fill('Duolingo 120')
    await t.getByLabel(`English for ${name}`).press('Enter')
    await expect(t.locator('.le-err-row')).toContainText('"Duolingo" is not a known English test')
  })
})
