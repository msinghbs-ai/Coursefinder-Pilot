// Guards: CF-247 (S77) v2.15.296. Platform Admin, 20 Oct 2026 06:33: "flag the failed one with reason so they dont get tried again, only operator and above can unflag them".
// CF-247 (S77) v2.15.296. Platform Admin, 20 Oct 2026 06:33: "flag the failed one with reason so they dont get tried again, only operator and
// above can unflag them". A provider held for "course pages not found" is out of page search, discovery, AI matching and Build adapter;
// a Pipeline Operator or above may release it, which starts its onboarding again.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const mig = fs.readFileSync('supabase/migrations/20261020010000_cf247_course_pages_not_found_flag.sql', 'utf8')
const ui = fs.readFileSync('src/FlagsPanel.jsx', 'utf8')

test('the hold stops every spend; operators may release only this reason; release restarts onboarding', () => {
  expect(mig).toContain("select not security.flag_provider_held_v1(p_provider_id, array['course_pages_not_found'])")
  expect(mig).toContain("v_pids := array(select i from unnest(v_pids) i where not security.flag_provider_held_v1(i, array[''course_pages_not_found'']));")
  expect(mig).toContain("where x.reason_code <> ''course_pages_not_found'')) then raise exception ''your role cannot change flags''")
  expect(mig).toContain("'flag.course_pages_release_min_rank'")
  expect(mig).toContain("return 'onboarding and site discovery';")
  expect(mig).toContain("and not exists (select 1 from pipeline.uni_adapters u where u.provider_id = b.provider_id);")
  expect(mig).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(ui).toContain("course_pages_not_found:'Course pages not found'")
})

test.describe('mocked browser', () => {
  test('a Pipeline Operator sees Release on a course-pages flag only', async ({ page }) => {
    await mockAdmin(page, { rank: 4 })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_flags', async route => {
      const b = route.request().postDataJSON()
      if (b.p_action === 'summary') return route.fulfill({ json: { can_change: false, release_codes: ['course_pages_not_found'], by_reason: [], last_24h: {} } })
      return route.fulfill({ json: { total: 2, items: [
        { id: 1, entity: 'provider', reason_code: 'course_pages_not_found', reason: 'Re-find wave 1: no course pages', state: 'raised', kind: 'hard', provider_name: 'Alpha College', flagged_at: '2026-10-19T20:00:00Z' },
        { id: 2, entity: 'provider', reason_code: 'site_unreachable', reason: 'Website does not answer', state: 'raised', kind: 'hard', provider_name: 'Beta College', flagged_at: '2026-10-19T20:00:00Z' }] } })
    })
    await page.goto('/#coverage?tab=flags')
    const rows = page.locator('table.dense-table tbody tr')
    await expect(rows).toHaveCount(2)
    await expect(rows.nth(0).getByRole('button', { name: 'Release' })).toBeVisible()
    await expect(rows.nth(1).getByRole('button', { name: 'Release' })).toHaveCount(0)
    await expect(rows.nth(0)).toContainText('Course pages not found')
  })
})
