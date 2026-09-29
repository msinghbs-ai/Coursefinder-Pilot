// v2.15.113 priority queue: pin universities, states, countries or courses to the front and reorder them.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { PAGES } from '../../src/nav-map.js'
import { mockAdmin } from './support/admin-mock.mjs'

const read = p => fs.readFileSync(p, 'utf8')

test('Scheduled jobs has a Priority queue tab; database changes are guarded and admin-only', () => {
  expect(PAGES.jobs.tabs.map(t => t.key)).toEqual(['automations', 'priority', 'jobs', 'schedules'])
  expect(PAGES.jobs.tabs.find(t => t.key === 'priority').min).toBe(3)
  const m = read('supabase/migrations/20260930100000_cf247_priority_queue.sql')
  expect(m).toContain("'c2df6a98e847cc625f9567bc8ed49876'")
  expect(m).toContain("'e6d35639281928c42a50e791545bed84'")
  expect(m).toContain("'2311d33b952f004a9a82c55da489de72'")
  expect(m).toContain("security.current_role_rank()<5 then raise exception 'Platform Admin role required'")
  expect(m).toContain("kind in ('provider','state','country','course')")
  expect(m).toContain('order by coalesce(cp.sort,1000000), coalesce(pp.rank,100000), md5(')
  for (const f of ['admin_priority_read()', 'admin_priority_search(text,text)', 'admin_priority_control(text,jsonb)']) expect(m).toContain(`revoke all on function public.${f} from public, anon;`)
})

test.describe('mocked browser', () => {
  test('pins listed in order, move up/down, remove, send a provider to the front, add a state and a university', async ({ page }) => {
    await mockAdmin(page)
    page.on('dialog', d => d.accept())
    await page.goto('/#scheduled-jobs?tab=priority')
    await expect(page.getByRole('tab', { name: 'Priority queue' })).toHaveAttribute('aria-selected', 'true')
    const pins = page.locator('.pq-pins tbody tr')
    await expect(pins).toHaveCount(2)
    await expect(pins.nth(0)).toContainText('The University of Melbourne')
    await page.getByRole('button', { name: 'Move Victoria up' }).click()
    await expect.poll(() => page.l3calls.find(c => c.p_action === 'move')?.p_args).toEqual({ id: 12, direction: 'up' })
    await page.getByRole('button', { name: 'Remove Victoria' }).click()
    await expect.poll(() => page.l3calls.find(c => c.p_action === 'remove')?.p_args).toEqual({ id: 12 })
    const order = page.locator('.pq-order tbody tr')
    await expect(order.nth(1)).toContainText('Pinned state')
    await expect(order.nth(2)).toContainText('By size')
    await page.getByRole('button', { name: 'Move UNSW Sydney to the front' }).click()
    await expect.poll(() => page.l3calls.find(c => c.p_action === 'add')?.p_args).toEqual({ kind: 'provider', target_id: 'p-unsw', top: true })
    await page.getByLabel('What to prioritise').selectOption('state')
    await page.getByLabel('State').selectOption('s-nsw')
    await page.getByRole('button', { name: 'Add', exact: true }).click()
    await expect.poll(() => page.l3calls.filter(c => c.p_action === 'add').map(c => c.p_args)).toContainEqual({ kind: 'state', target_id: 's-nsw', top: false })
    await page.getByLabel('What to prioritise').selectOption('provider')
    await page.getByLabel('Find a university').fill('Macq')
    await page.getByRole('button', { name: 'Add Macquarie University' }).click()
    await expect.poll(() => page.l3calls.filter(c => c.p_action === 'add').map(c => c.p_args)).toContainEqual({ kind: 'provider', target_id: 'p-mq', top: false })
  })
})
