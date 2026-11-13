// Guards: CF-247 models services: v2.15.118 Platform settings › Models & services: on/off switch for every AI model and page-fetching service.
// v2.15.118 Platform settings › Models & services: on/off switch for every AI model and page-fetching service.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { PAGES, SECTIONS } from '../../src/nav-map.js'
import { mockAdmin } from './support/admin-mock.mjs'

const read = p => fs.readFileSync(p, 'utf8')

test('Models & services is a Platform settings page; switching is role-checked, logged, and a model off leaves every operation screen', () => {
  expect(SECTIONS.find(s => s.label === 'Platform settings').pages).toEqual(['environment', 'services', 'migration']) // v2.15.301: Data model retired, Storage & retention on Platform health
  expect(PAGES.services.min).toBe(4) // v2.16.0: Scholarship extraction (Curator) is under Scholarships › Coverage; both tabs are Pipeline Operator and above
  const m = read('supabase/migrations-archive/20260930160000_cf247_models_services_toggles.sql')
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
  // v2.16.0 (Platform Admin 13 Nov 2026 19:14): the AI model switches left this screen (the one model list is Models & services › AI, guarded by
  // cf-247-ai-models-services-ui); the model half of this test is retired with them. The page-service switch stays.
  test('switch a page service on from Services & limits, with the reason kept', async ({ page }) => {
    await mockAdmin(page)
    page.on('dialog', d => d.accept('Too slow'))
    await page.goto('/#models-services') // the page-service switches are on Services & limits, one card per service
    await page.locator('[data-fold="other-services"] > summary').click() // a gateway that is neither Firecrawl nor direct read
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
  const m = read('supabase/migrations-archive/20261001120000_cf247_one_home_models.sql')
  expect(m).toContain("raise exception 'this model has not passed its tests for any task yet, so it cannot be switched on';")
  expect(m).toContain("raise exception 'switch this model on in Platform settings › Models & services first'")
  expect(m).toContain("position('set enabled=true, paused=false' in v_new) > 0")
  expect(read('src/layer2-provider-entry.jsx')).toContain('A new service starts switched off.')
})
