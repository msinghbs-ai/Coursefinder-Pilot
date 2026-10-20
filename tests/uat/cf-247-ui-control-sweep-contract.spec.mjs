// v2.15.110 UI control sweep: every scheduled automation and scholarship publishing are operated from the admin UI
// (moving review items back to the AI retired with Layer 3 in v2.15.252). Source checks plus a mocked browser run against the local dev server.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { PAGES, resolveTarget, hrefFor } from '../../src/nav-map.js'
import { describeSchedule } from '../../src/automation-schedule.js'
import { utcClockToMelbourne } from '../../src/lib/format.js'
import { mockAdmin } from './support/admin-mock.mjs'

const read = p => fs.readFileSync(p, 'utf8')

test('menu: Automations and Publishing tabs; old links still land', () => {
  expect(PAGES.jobs.tabs.map(t => t.key)).toEqual(['automations', 'jobs', 'tasks']) // v2.15.300: Priority queue retired // v2.15.197: Task manager
  expect(PAGES.layer4.tabs.map(t => t.key)).toEqual(['inbox']) // v2.15.300: the old Layer 4 tabs are Inbox kinds
  // v2.15.252 (Platform Admin, 12 Oct 2026): Send back to AI retired with Layer 3; the old address opens the Review queue.
  expect(resolveTarget('layer-4-review', new URLSearchParams({ tab: 'sendback' }))).toMatchObject({ page: 'layer4', tab: 'inbox' })
  expect(PAGES.scholarships.tabs.map(t => [t.key, t.min])).toEqual([['list', 1], ['coverage', 3], ['extraction', 3]]) // v2.15.240: Coverage; v2.15.174: Course links retired; Publishing is Layer 4
  expect(PAGES.scholarships.min).toBe(1)
  expect(resolveTarget('jobs').params?.get?.('tab') ?? 'jobs').toBe('jobs')
  expect(resolveTarget('layer-4-review', new URLSearchParams({ tab: 'publishing' }))).toMatchObject({ page: 'scholarships', tab: 'coverage' })
  expect(hrefFor('scholarships', 'coverage')).toBe('#scholarships?tab=coverage')
})

test('schedules read in plain words, times in Melbourne time (v2.15.131)', () => {
  expect(describeSchedule('* * * * *')).toEqual({ text: 'Every minute', every: 1 })
  expect(describeSchedule('3-59/10 * * * *')).toEqual({ text: 'Every 10 minutes', every: 10 })
  expect(describeSchedule('*/5 * * * *').every).toBe(5)
  expect(describeSchedule('12 * * * *').text).toBe('Every hour (at :12)')
  expect(describeSchedule('17 */6 * * *')).toEqual({ text: 'Every 6 hours', every: 360 })
  expect(describeSchedule('17 20 * * *').text).toBe(`Daily at ${utcClockToMelbourne(20, 17).time}`)
  expect(utcClockToMelbourne(20, 17, new Date('2026-09-30T00:00:00Z'))).toEqual({ time: '6:17 am', dayShift: 1 })
  expect(utcClockToMelbourne(20, 17, new Date('2026-10-10T00:00:00Z'))).toEqual({ time: '7:17 am', dayShift: 1 })
  expect(describeSchedule('0 14 * * 0').text).toContain('Monday')
  expect(describeSchedule('27,57 * * * *').text).toBe('2 times an hour')
  expect(describeSchedule('20 5 * * 0').text).toContain('Sunday')
  expect(describeSchedule('23 21 * 10-12 1').text).toContain('Oct–Dec')
  expect(describeSchedule('30 seconds').text).toBe('Every 30 seconds')
})

test('controls are guarded, logged and admin-only', () => {
  const m = read('supabase/migrations-archive/20260930050000_cf247_ui_control_sweep.sql')
  for (const f of ['admin_automations_read', 'admin_automation_control', 'admin_requeue_read', 'admin_requeue', 'admin_scholarship_publishing_read', 'admin_scholarship_publishing']) {
    expect(m).toContain(`revoke all on function public.${f}(`)
  }
  expect(m).toContain("security.current_role_rank()<3")
  expect(m).toContain("v_rank<5 then raise exception 'Platform Admin role required'")
  expect(m).toContain("if v_rank<coalesce(c.control_rank,6)")
  expect(m).toContain("the eligible list changed; refresh and check again")
  expect(m).toContain("insert into pipeline.admin_control_events")
  expect((m.match(/insert into pipeline\.automation_catalogue/g) || []).length).toBe(1)
  expect((m.match(/^ \('/gm) || []).length).toBe(58)
  const f1 = read('supabase/migrations-archive/20260930051000_cf247_ui_control_sweep_reason_groups.sql')
  const f2 = read('supabase/migrations-archive/20260930052000_cf247_ui_control_sweep_failed_counts.sql')
  expect(f1).toContain("'3eb0b56824f911f29298e5755e179adc'")
  expect(f2).toContain("'efd0bf3fb2468382aa45d0f194bed300'")
  expect(f2).toContain("not like 'released:%'")
  const pin = read('supabase/migrations-archive/20260930061000_cf247_l3_pinned_model_from_layer4.sql')
  expect(pin).toContain("'8e8733c8f2318d2614e1d77ad4b88400'")
  expect(pin).toContain("'f4f00fc0e7b957e9bd3d4b42c3fbb96d'")
  expect(pin).toContain('(t.active or t.profile_id=v_pin)')
  // v2.15.252: layer3-model-routing was deleted with Layer 3, so its pinned-model check was removed.
})

test.describe('mocked browser', () => {
  test('Automations: grouped by area, plain schedules, pause, run now, frequency, batch, area pause', async ({ page }) => {
    await mockAdmin(page)
    page.on('dialog', d => d.accept())
    await page.goto('/#scheduled-jobs')
    await expect(page.getByRole('tab', { name: 'Automations' })).toHaveAttribute('aria-selected', 'true')
    await expect(page.locator('.au-area')).toHaveCount(4)
    const read = page.locator('tr[data-job="coverage-read"]')
    await expect(read).toContainText('Read course pages')
    await expect(read).toContainText('Every 2 minutes')
    await expect(read).toContainText('60 per run')
    await expect(page.locator('tr[data-job="coverage-discover"]')).toContainText('Took too long and was stopped by the database time limit')
    await expect(page.locator('tr[data-job="course-completeness-build"]')).toContainText(`Daily at ${utcClockToMelbourne(20, 17).time}`)
    await expect(page.locator('tr[data-job="cron-history-retention"]')).toContainText('Top admin only')
    await read.getByRole('button', { name: 'Pause' }).click()
    await expect.poll(() => page.l3calls.map(c => c.p_action)).toContain('pause')
    await read.getByRole('button', { name: 'Run now' }).click()
    await expect.poll(() => page.l3calls.map(c => c.p_action)).toContain('run_now')
    await read.getByLabel('How often Read course pages runs').selectOption('5')
    await expect.poll(() => page.l3calls.find(c => c.p_action === 'set_every')?.p_args).toEqual({ minutes: 5 })
    await read.getByLabel('Batch size for Read course pages').fill('40')
    await read.getByRole('button', { name: 'Save' }).click()
    await expect.poll(() => page.l3calls.find(c => c.p_action === 'set_batch')?.p_args).toEqual({ batch: 40 })
    await page.locator('.au-area[data-area="Layer 3 AI"]').getByRole('button', { name: 'Pause area' }).click()
    await expect.poll(() => page.l3calls.find(c => c.p_action === 'pause_area')?.p_args).toEqual({ area: 'Layer 3 AI' })
    await page.getByLabel('Show').selectOption('failed')
    await expect(page.locator('.au-table tbody tr')).toHaveCount(1)
  })

  // v2.15.252 (Platform Admin, 12 Oct 2026): Send back to AI and the Layer 3 task cards retired with Layer 3.
  test('old Send back to AI address opens the Layer 4 Inbox on course links', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#layer-4-review?tab=sendback')
    await expect(page).toHaveURL(/kind=course_link/) // v2.15.300
    await expect(page.getByRole('tab', { name: 'Send back to AI' })).toHaveCount(0)
    await expect(page.locator('.sb-field')).toHaveCount(0)
  })

  // v2.15.253 (Platform Admin, 12 Oct 2026): Layer 4 › Scholarship publishing retired; publishing is on Scholarships › Coverage.
  test('Scholarships list opens directly on the list; tabs are Scholarships and Coverage (v2.15.240)', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#scholarships')
    await expect(page.locator('[data-sch-count]')).toBeVisible()
    await expect(page.getByRole('tab')).toHaveText(['Scholarships', 'Coverage', 'Extraction'])
    await expect(page.locator('[data-sch-count]')).toBeVisible()
  })
})
