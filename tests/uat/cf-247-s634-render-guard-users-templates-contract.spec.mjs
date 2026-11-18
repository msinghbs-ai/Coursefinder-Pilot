// Guards: Platform Admin 18 Nov 2026 12:23 (hotfix ref ZDUFMC): Users & roles › Links & Email Templates renders once its settings load (every hook of the screen is called above its early returns, so a later render never calls more hooks than the first: React error #310), and the four-step Create user flow opens and moves through its steps without a render error.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const body = '<p>Hello {{user_name}}, <a href="{{link}}">sign in</a>. Guide: {{guide_link}}. Role: {{role}}.</p>'
const settings = { site_url: 'https://admin.example.test', guide_link: 'https://admin.example.test/#platform-guide', templates: { invite: { subject: 'Your StudySearch invitation', body }, recovery: { subject: 'Reset your password', body } } }

test('the template screen calls no hook below an early return', () => {
  const src = fs.readFileSync('src/AuthEmailTemplates.jsx', 'utf8')
  const fn = src.slice(src.indexOf('export default function AuthEmailTemplates'))
  const firstReturn = fn.search(/\n  if\([^\n]*\)return /)
  expect(firstReturn).toBeGreaterThan(0)
  expect(fn.slice(firstReturn).split('\n  return <div className="aet"')[0]).not.toMatch(/\buse(State|Effect|Memo|Ref|Callback|LayoutEffect)\(/)
})

test.describe('mocked browser', () => {
  test('Links & Email Templates renders after its settings load, with no render error', async ({ page }) => {
    const errors = []
    page.on('pageerror', (e) => errors.push(String(e?.message || e)))
    await mockAdmin(page)
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_auth_template_settings_read', (r) => r.fulfill({ contentType: 'application/json',
      body: JSON.stringify({ settings, defaults: settings, last_events: [{ at: '2026-11-18T00:00:00Z', action: 'auth_template_test', synced: true, note: 'sent' }] }) }))
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_email_delivery_read', (r) => r.fulfill({ contentType: 'application/json',
      body: JSON.stringify({ delivery: { email_provider: 'supabase', sender_name: 'StudySearch PIM Admin', from_email: '', key_saved: false } }) }))
    await page.goto('/#users')
    await page.getByRole('tab', { name: 'Links & Email Templates' }).or(page.getByRole('button', { name: 'Links & Email Templates' })).first().click()
    await expect(page.locator('[data-auth-email-templates]')).toBeVisible()
    await expect(page.locator('[data-aet-route="supabase"]')).toContainText('Supabase Built-in')
    await expect(page.locator('[data-aet-route-verified]')).toContainText('accepted')
    await expect(page.locator('[data-rte-frame]')).toBeVisible()
    await page.locator('[data-aet-kind="recovery"]').click()
    await page.locator('[data-rte-html]').click()
    await expect(page.locator('[data-aet-body]')).toHaveValue(/sign in/)
    await expect(page.getByText('Workspace could not render')).toHaveCount(0)
    expect(errors.filter((e) => /Minified React error|Rendered more hooks|Rendered fewer hooks/.test(e))).toEqual([])
  })

  test('Create user opens and moves through its four steps with no render error', async ({ page }) => {
    const errors = []
    page.on('pageerror', (e) => errors.push(String(e?.message || e)))
    await mockAdmin(page)
    await page.route('https://example.supabase.co/functions/v1/admin-user-management', (r) => r.fulfill({ contentType: 'application/json',
      body: JSON.stringify({ users: [], events: [], roles: [{ code: 'viewer', name: 'Viewer', rank: 1, description: 'Read' }, { code: 'curator', name: 'Curator', rank: 3, description: 'Curate' }] }) }))
    await page.goto('/#users')
    await page.getByRole('button', { name: 'Create user' }).click()
    const m = page.locator('.cuw')
    await m.locator('[data-cuw-email]').fill('alex@example.edu.au')
    for (const step of ['role', 'signin', 'review']) { await m.locator('[data-cuw-next]').click(); await expect(m).toHaveAttribute('data-cuw-step', step) }
    await m.locator('[data-cuw-back]').click()
    await expect(m).toHaveAttribute('data-cuw-step', 'signin')
    await expect(page.getByText('Workspace could not render')).toHaveCount(0)
    expect(errors.filter((e) => /Minified React error|Rendered more hooks|Rendered fewer hooks/.test(e))).toEqual([])
  })
})
