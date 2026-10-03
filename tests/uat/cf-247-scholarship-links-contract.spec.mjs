// v2.15.115 scholarship course links: one decision per scholarship (all, matching courses, none).
// v2.15.174 (Platform Admin, 4 Oct 2026 01:57): the Course links tab is retired; links come from each scholarship's
// page (Layer 2). The database decisions already made stay in force (the decision guard is unchanged).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { PAGES, resolveTarget } from '../../src/nav-map.js'
import { mockAdmin } from './support/admin-mock.mjs'

const read = p => fs.readFileSync(p, 'utf8')

test('Course links tab retired; the decisions made earlier keep governing the sweep', () => {
  expect(PAGES.scholarships.tabs.map(t => [t.key, t.min])).toEqual([['list', 1]])
  expect(resolveTarget('scholarships', new URLSearchParams('tab=links'))).toMatchObject({ page: 'scholarships', tab: 'list' })
  expect(fs.existsSync('src/ScholarshipLinks.jsx')).toBe(false)
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
  test('the old Course links address opens the list, with no tabs and no heading', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#scholarships?tab=links')
    await expect(page.getByRole('tab', { name: 'Course links' })).toHaveCount(0)
    await expect(page.getByText('Scholarship catalogue')).toHaveCount(0)
    await expect(page.locator('[data-sch-count]')).toContainText('published')
  })
})
