// v2.15.115 scholarship course links: one decision per scholarship (all, matching courses, none).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { PAGES } from '../../src/nav-map.js'
import { mockAdmin } from './support/admin-mock.mjs'

const read = p => fs.readFileSync(p, 'utf8')

test('Scholarships has a Course links tab; decisions are role-checked, logged and govern the sweep', () => {
  expect(PAGES.scholarships.tabs.map(t => [t.key, t.min])).toEqual([['list', 1], ['links', 3], ['publishing', 3]])
  const m = read('supabase/migrations/20260930130000_cf247_scholarship_course_links.sql')
  expect(m).toContain("security.current_role_rank() < 4 then raise exception 'Pipeline Operator role or above required'")
  expect(m).toContain("check (decision in ('all','filter','none'))")
  expect(m).toContain("insert into pipeline.layer4_mass_operations")
  for (const f of ['admin_scholarship_links_read(text, text)', 'admin_scholarship_links_detail(uuid, text, jsonb)', 'admin_scholarship_links_decide(uuid, text, jsonb, text)']) {
    expect(m).toContain(`revoke all on function public.${f} from public, anon;`)
    expect(m).toContain(`grant execute on function public.${f} to authenticated;`)
  }
  const w = read('supabase/migrations/20260930133000_cf247_scholarship_decision_wins.sql')
  expect(w).toContain("'714ab7f0d99c5657cd083a8bbb5f3403'")
  expect(w).toContain('create trigger scholarship_decision_guard before insert or update on scholarship.course_mappings')
  expect(read('supabase/migrations/20260930131000_cf247_scholarship_suggest_fix.sql')).toContain("'47fc4f2ab27d7a2d3c7f466e029b55b1'")
  expect(read('supabase/migrations/20260930132000_cf247_scholarship_suggest_title.sql')).toContain("'8585e3c95f386a721c9a33c19adad04e'")
})

test.describe('mocked browser', () => {
  test('list, open a scholarship, use the suggestion, narrow by level and save', async ({ page }) => {
    await mockAdmin(page)
    page.on('dialog', d => d.accept())
    await page.goto('/#scholarships?tab=links')
    await expect(page.getByRole('tab', { name: 'Course links' })).toHaveAttribute('aria-selected', 'true')
    await expect(page.locator('.sl-list tbody tr')).toHaveCount(2)
    await page.getByRole('button', { name: 'Master of Global Medicines Development Pioneers Scholarship' }).click()
    const panel = page.locator('[data-decide="sch-mgmd"]')
    await expect(panel).toContainText('Suggested: Only matching courses')
    await expect(panel).toContainText('1 course will be linked, 580 rejected.')
    await expect(panel.getByLabel('Only matching courses')).toBeChecked()
    await panel.getByLabel(/Masters Degree \(Coursework\)/).check()
    await panel.getByLabel(/^Reason/).fill('Scholarship page names this one course')
    await panel.getByRole('button', { name: 'Save decision' }).click()
    await expect.poll(() => page.l3calls.find(c => c.p_decision)).toEqual({ p_scholarship_id: 'sch-mgmd', p_decision: 'filter', p_filter: { levels: ['lv-mc'], title: 'Master of Global Medicines Development' }, p_reason: 'Scholarship page names this one course' })
    await expect(panel).toContainText('Saved: 1 linked, 580 rejected, 24 automatic links removed.')
    await panel.getByLabel('No courses').check()
    await expect.poll(() => page.l3calls.filter(c => c.detail?.p_decision === 'none').length).toBeGreaterThan(0)
  })
})
