// v2.15.130 Campuses and scholarships can be corrected by hand in the list (screen review cmp-readonly, sch-no-edit).
// A person's entry always wins: a guard keeps locked columns on every automated update (migration 20261001150000).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

test('database: locks extended, guard on both tables, role-checked edits logged, list read guarded', () => {
  const m = fs.readFileSync('supabase/migrations-archive/20261001150000_cf247_campus_scholarship_edit.sql', 'utf8')
  expect(m).toContain("if v is distinct from '116a2708a1d1c91465a8c0a22fcfeafa' then")
  expect(m).toContain("check (entity in ('course','provider','campus','scholarship'))")
  expect(m).toContain("create trigger manual_lock_guard before update on catalogue.campuses for each row execute function security.manual_column_guard('campus');")
  expect(m).toContain("create trigger manual_lock_guard before update on scholarship.scholarships for each row execute function security.manual_column_guard('scholarship');")
  expect(m).toContain("if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required'")
  expect(m).toContain("if auth.uid() is null or v_rank < 5 then raise exception 'PIM Operator role or above required'")
  expect(m.match(/insert into pipeline\.manual_edit_log/g).length).toBe(3)
  expect(m).toContain("v_locks := array['award_amount','award_percentage','award_value_type','award_currency_code'];")
})

test.describe('mocked browser', () => {
  test('scholarship amount and closing date, campus address, in the list', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#scholarships')
    await page.getByRole('button', { name: 'Edit in list' }).click()
    const t = page.locator('[data-list-edit="scholarship"]'), n = 'RMIT David Phillips Memorial Scholarship'
    await expect(t.locator('[data-edit-row="s2"] .le-lock')).toHaveCount(1)
    await expect(t).toContainText('30/11/2026')
    await t.getByRole('button', { name: `Edit Applications close for ${n}` }).click()
    await t.getByLabel(`Applications close for ${n}`).fill('31/10/2026')
    await t.getByLabel(`Applications close for ${n}`).press('Enter')
    await expect.poll(() => page.l3calls.find(c => c.p_args?.field === 'application_close_date')).toEqual({ p_scholarship_id: 's2', p_action: 'set_core', p_args: { field: 'application_close_date', value: '2026-10-31' } })
    await t.getByRole('button', { name: `Edit Amount (A$) for ${n}` }).click()
    await t.getByLabel(`Amount (A$) for ${n}`).fill('5000')
    await t.getByLabel(`Amount (A$) for ${n}`).press('Enter')
    await expect.poll(() => page.l3calls.find(c => c.p_args?.field === 'award_amount')?.p_args).toEqual({ field: 'award_amount', value: '5000' })
    await t.getByRole('button', { name: `Edit Applications close for ${n}` }).click()
    await t.getByLabel(`Applications close for ${n}`).fill('2026-10-31')
    await t.getByLabel(`Applications close for ${n}`).press('Enter')
    await expect(t.locator('.le-err-row')).toContainText('enter the date as dd/mm/yyyy')
    await page.goto('/#providers?tab=campuses')
    await page.getByRole('button', { name: 'Edit in list' }).click()
    const c = page.locator('[data-list-edit="campus"]')
    await c.getByRole('button', { name: 'Edit Street address for RMIT Brunswick' }).click()
    await c.getByLabel('Street address for RMIT Brunswick').fill('25 Dawson Street')
    await c.getByLabel('Street address for RMIT Brunswick').press('Enter')
    await expect.poll(() => page.l3calls.find(c => c.p_campus_id)).toEqual({ p_campus_id: 'cp2', p_action: 'set_core', p_args: { field: 'address_line1', value: '25 Dawson Street' } })
  })
})
