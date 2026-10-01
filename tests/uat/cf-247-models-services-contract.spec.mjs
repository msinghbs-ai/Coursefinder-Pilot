// v2.15.118 Platform settings › Models & services: on/off switch for every AI model and page-fetching service.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { PAGES, SECTIONS } from '../../src/nav-map.js'
import { mockAdmin } from './support/admin-mock.mjs'

const read = p => fs.readFileSync(p, 'utf8')

test('Models & services is a Platform settings page; switching is role-checked, logged, and a model off leaves every operation screen', () => {
  expect(SECTIONS.find(s => s.label === 'Platform settings').pages).toEqual(['environment', 'scrapers', 'services', 'dataModel', 'migration'])
  expect(PAGES.services.min).toBe(4)
  const m = read('supabase/migrations/20260930160000_cf247_models_services_toggles.sql')
  expect(m).toContain("if auth.uid() is null or security.current_role_rank() < 5 then raise exception 'PIM Operator role or above required'")
  expect(m).toContain('update pipeline.layer3_route_tiers set active = false, updated_at = now() where profile_id = p_id and active;')
  expect(m).toContain("raise exception 'this model was retired after failing its tests and cannot be switched on here'")
  expect(m).toContain("insert into pipeline.admin_control_events(area, action, target, detail, actor)")
  expect(m).toContain('and p.enabled and not p.paused and p.retired_at is null')
  for (const f of ['admin_services_read()', 'admin_services_control(text, uuid, boolean, text)']) {
    expect(m).toContain(`revoke all on function public.${f} from public, anon;`)
    expect(m).toContain(`grant execute on function public.${f} to authenticated;`)
  }
})

test.describe('mocked browser', () => {
  test('switch a model off (its steps go too), switch a service on; off items are greyed, retired ones cannot be switched', async ({ page }) => {
    await mockAdmin(page)
    const prompts = []
    page.on('dialog', d => { prompts.push(d.message()); d.accept('Too slow') })
    await page.goto('/#models-services')
    await expect(page.locator('[data-model="sonnet-english"]')).toHaveClass(/ms-off/)
    await expect(page.locator('[data-model="old-model"] [role="switch"]')).toHaveCount(0)
    await expect(page.locator('.ms-retired summary')).toContainText('Retired models (1)')
    // v2.15.122: a model that has not passed its test cannot be switched on.
    await expect(page.getByRole('switch', { name: 'Switch on vendor/new-candidate' })).toBeDisabled()
    await expect(page.locator('[data-model="new-candidate"]')).toContainText('Pass its test first')
    await page.getByRole('switch', { name: 'Switch off qwen/qwen3-30b-a3b' }).click()
    await expect.poll(() => page.l3calls.find(c => c.p_kind === 'model')).toEqual({ p_kind: 'model', p_id: 'm1', p_enabled: false, p_reason: 'Too slow' })
    expect(prompts[0]).toContain('English step 1, Intake step 1')
    await expect(page.getByRole('status')).toContainText('qwen/qwen3-30b-a3b switched off; 2 cascade steps switched off.')
    await expect(page.locator('[data-model="qwen3-30b"]')).toHaveClass(/ms-off/)
    await page.getByRole('switch', { name: 'Switch on Custom gateway' }).click()
    await expect.poll(() => page.l3calls.find(c => c.p_kind === 'service')?.p_enabled).toBe(true)
    await expect(page.locator('[data-service="custom-gateway"] [role="switch"]')).toHaveAttribute('aria-checked', 'true')
  })
})

test('v2.15.122: one home — Environment holds keys only, Layer 3 Models is Models & services, switching on needs a passed test, cascades never switch a model on', () => {
  const env = read('src/EnvironmentMigrationWorkspace.jsx')
  expect(env).not.toContain('Activate profile')
  expect(env).not.toContain('Pause profile')
  expect(env).not.toContain('Enabled</label>')
  expect(env).toContain('href="#models-services"')
  const m = read('supabase/migrations/20261001120000_cf247_one_home_models.sql')
  expect(m).toContain("raise exception 'this model has not passed its tests for any task yet, so it cannot be switched on';")
  expect(m).toContain("raise exception 'switch this model on in Platform settings › Models & services first'")
  expect(m).toContain("position('set enabled=true, paused=false' in v_new) > 0")
  expect(read('src/layer2-provider-entry.jsx')).toContain('A new service starts switched off.')
})
